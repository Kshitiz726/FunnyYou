"""Drive a real ComfyUI instance with the shipped client, end to end.

    python scripts/probe_comfy.py --url https://<pod>-8188.proxy.runpod.net

Answers one question: can this backend actually operate that GPU? It exercises
every part of the integration that only fails against the real thing —

    /system_stats          reachability
    /upload/image          multipart upload of the user's photo
    workflow.build()       binding by FY_ node title, validated by ComfyUI
    /prompt                queue, and the real validation error shape on reject
    ws://.../ws            live sampler progress
    /history/{id}          finding the output among the node outputs
    /view                  downloading the bytes

Defaults to `zimage_probe.json`, which needs only the models the Z-Image
template already downloads, so it works before any Wan or face-swap weights
exist. Point `--workflow` at the real graph once they do.

This costs a few seconds of GPU time on whatever pod you aim it at.
"""

from __future__ import annotations

import argparse
import asyncio
import io
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from app import workflow as wf  # noqa: E402
from app.comfy_client import ComfyClient, ComfyError  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "data" / "probe"
WORKFLOWS = Path(__file__).resolve().parent.parent / "workflows"

PROMPT = (
    "portrait of the person as a NASA astronaut in a white spacesuit, "
    "helmet visor up, Earth glowing behind them, cinematic lighting"
)


def _ok(label: str, detail: str = "") -> None:
    print(f"  [PASS] {label:<26} {detail}")


def _fail(label: str, detail: str) -> None:
    print(f"  [FAIL] {label:<26} {detail}")


def _sample_face() -> bytes:
    from PIL import Image, ImageDraw

    image = Image.new("RGB", (640, 800), (232, 214, 198))
    draw = ImageDraw.Draw(image)
    draw.ellipse((170, 130, 470, 520), fill=(228, 188, 158))
    draw.ellipse((240, 280, 280, 312), fill=(40, 32, 30))
    draw.ellipse((360, 280, 400, 312), fill=(40, 32, 30))
    draw.arc((265, 360, 375, 450), start=15, end=165, fill=(120, 70, 60), width=9)
    draw.ellipse((160, 100, 480, 300), fill=(58, 42, 36))
    draw.polygon([(150, 800), (240, 540), (400, 540), (490, 800)], fill=(64, 78, 122))

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="ComfyUI base URL")
    parser.add_argument("--workflow", default="zimage_probe.json")
    parser.add_argument("--face", help="path to a real photo (optional)")
    parser.add_argument("--width", type=int, default=640)
    parser.add_argument("--height", type=int, default=800)
    parser.add_argument("--frames", type=int, default=81)
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    client = ComfyClient(args.url, timeout_s=900)

    print(f"\nProbing {args.url}")

    # ── reachability ──────────────────────────────────────────────────────
    if not await client.health():
        _fail("reachable", "no answer from /system_stats")
        return 2
    _ok("reachable")

    # ── the graph binds ───────────────────────────────────────────────────
    path = WORKFLOWS / args.workflow
    try:
        graph = wf.load(path)
    except wf.WorkflowError as exc:
        _fail("workflow loads", str(exc))
        return 1

    missing = wf.validate(graph)
    if missing:
        _fail("markers present", f"missing {', '.join(missing)}")
        return 1
    _ok("markers present", f"{args.workflow} ({len(graph)} nodes)")

    # ── upload ────────────────────────────────────────────────────────────
    face = Path(args.face).read_bytes() if args.face else _sample_face()
    (OUT / "face.jpg").write_bytes(face)
    try:
        image_name = await client.upload_image(face, "probe_face.jpg")
    except ComfyError as exc:
        _fail("upload", str(exc))
        return 1
    _ok("upload", f"{len(face) // 1024} KB -> {image_name}")

    bound = wf.build(
        graph,
        wf.RenderParams(
            image_name=image_name,
            prompt=PROMPT,
            width=args.width,
            height=args.height,
            frames=args.frames,
        ),
    )

    # ── queue ─────────────────────────────────────────────────────────────
    try:
        prompt_id = await client.queue(bound)
    except ComfyError as exc:
        # ComfyUI's validation is the real test of the binding, so print it in
        # full rather than truncating — it names the node and the bad value.
        _fail("queue", f"\n{exc}")
        return 1
    _ok("queue", prompt_id)

    # ── progress ──────────────────────────────────────────────────────────
    started = time.monotonic()
    steps = 0
    last = 0.0
    try:
        async for step in client.watch(prompt_id):
            if step.stage == "sampling":
                steps += 1
                last = step.value
                print(f"        sampling {step.value * 100:5.1f}%", end="\r")
    except ComfyError as exc:
        _fail("progress", str(exc))
        return 1

    elapsed = time.monotonic() - started
    if steps:
        _ok("websocket progress", f"{steps} updates, reached {last * 100:.0f}%")
    else:
        # Not fatal: some graphs finish before a single progress frame lands.
        print(f"  [WARN] websocket progress    none received in {elapsed:.1f}s")

    # ── collect ───────────────────────────────────────────────────────────
    try:
        assets = await client.outputs(prompt_id)
    except ComfyError as exc:
        _fail("history", str(exc))
        return 1
    _ok("history", f"{len(assets)} output(s): {[a.filename for a in assets]}")

    try:
        data = await client.download(assets[0])
    except ComfyError as exc:
        _fail("download", str(exc))
        return 1

    destination = OUT / assets[0].filename
    destination.write_bytes(data)
    _ok("download", f"{len(data) // 1024} KB -> {destination.name}")

    print(f"\nALL CHECKS PASSED in {elapsed:.1f}s")
    print(f"Artifacts in {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
