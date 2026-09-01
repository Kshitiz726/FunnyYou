"""End-to-end check against a running stack.

    python -m devstack.run                 # terminal 1
    python scripts/verify_stack.py         # terminal 2

Drives the real HTTP surface the app drives — health, a preview batch, and a
full render from upload to downloadable mp4 — and writes what comes back to
`data/verify/` so you can open the files and look at them.

Works unchanged against the dev stack or against real Gemini and a real GPU;
that is the point of it.
"""

from __future__ import annotations

import argparse
import asyncio
import base64
import json
import sys
import time
from pathlib import Path

import httpx

# Windows consoles default to cp1252 and mangle punctuation coming back from
# the API into replacement characters.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

OUT = Path(__file__).resolve().parent.parent / "data" / "verify"

SCENARIOS = {
    "astronaut": "floating above the Earth in a white NASA spacesuit, helmet visor up",
    "superhero": "flying over a city skyline at sunset in a red and blue suit, cape flowing",
    "chef": "in a professional kitchen wearing chef whites, plating a dish",
    "rock_guitarist": "on a stadium stage playing electric guitar under spotlights",
}


def _ok(label: str, detail: str = "") -> None:
    print(f"  [PASS] {label}" + (f"  {detail}" if detail else ""))


def _fail(label: str, detail: str) -> None:
    print(f"  [FAIL] {label}  {detail}")


def _sample_face() -> bytes:
    """A synthetic portrait, so the check needs no photo on disk."""
    import io
    from PIL import Image, ImageDraw

    image = Image.new("RGB", (640, 800), (232, 214, 198))
    draw = ImageDraw.Draw(image)
    draw.ellipse((170, 130, 470, 520), fill=(228, 188, 158))
    draw.ellipse((240, 280, 280, 312), fill=(40, 32, 30))
    draw.ellipse((360, 280, 400, 312), fill=(40, 32, 30))
    draw.arc((265, 360, 375, 450), start=15, end=165, fill=(120, 70, 60), width=9)
    draw.polygon([(320, 300), (300, 380), (340, 380)], fill=(206, 166, 138))
    draw.ellipse((160, 100, 480, 300), fill=(58, 42, 36))
    draw.polygon([(150, 800), (240, 540), (400, 540), (490, 800)], fill=(64, 78, 122))

    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


async def check_health(client: httpx.AsyncClient) -> dict:
    print("\nHealth")
    response = await client.get("/v1/health")
    body = response.json()
    print("  " + json.dumps(body, indent=2).replace("\n", "\n  "))

    (_ok if body.get("videoEnabled") else _fail)(
        f"video provider: {body.get('videoProvider')}", body.get("videoError") or ""
    )
    if body.get("videoProvider") == "comfy":
        (_ok if body.get("comfyReachable") else _fail)(
            "ComfyUI reachable", body.get("comfyUrl", "")
        )
        (_ok if body.get("workflowValid") else _fail)(
            "workflow bindable", body.get("workflowError") or body.get("workflow", "")
        )
    (_ok if body.get("previewsEnabled") else _fail)(
        f"preview provider: {body.get('previewProvider')}", body.get("previewError") or ""
    )
    return body


async def check_previews(client: httpx.AsyncClient, face: bytes) -> bool:
    print(f"\nPreviews  ({len(SCENARIOS)} scenarios)")
    started = time.monotonic()

    response = await client.post(
        "/v1/previews",
        files={"image": ("face.jpg", face, "image/jpeg")},
        data={"scenarios": json.dumps(SCENARIOS)},
        timeout=300,
    )
    if response.status_code != 200:
        _fail("POST /v1/previews", f"{response.status_code} {response.text[:200]}")
        return False

    body = response.json()
    elapsed = time.monotonic() - started

    for item in body["previews"]:
        data = base64.b64decode(item["imageBase64"])
        path = OUT / f"preview_{item['templateId']}.jpg"
        path.write_bytes(data)
        # JPEG SOI marker — proof it decoded as a real image, not a stub.
        valid = data[:2] == b"\xff\xd8"
        (_ok if valid else _fail)(
            item["templateId"], f"{len(data) // 1024} KB -> {path.name}"
        )

    for template_id, error in (body.get("errors") or {}).items():
        _fail(template_id, error[:160])

    got = len(body["previews"])
    print(f"  {got}/{len(SCENARIOS)} in {elapsed:.1f}s")
    return got == len(SCENARIOS)


async def check_render(client: httpx.AsyncClient, face: bytes) -> bool:
    print("\nRender")
    response = await client.post(
        "/v1/renders",
        files={"image": ("face.jpg", face, "image/jpeg")},
        data={
            "prompt": SCENARIOS["astronaut"],
            "template_id": "astronaut",
        },
    )
    if response.status_code != 202:
        _fail("POST /v1/renders", f"{response.status_code} {response.text[:300]}")
        return False

    job = response.json()
    job_id = job["id"]
    _ok("queued", job_id)

    started = time.monotonic()
    seen: list[str] = []
    while time.monotonic() - started < 900:
        await asyncio.sleep(1.5)
        job = (await client.get(f"/v1/renders/{job_id}")).json()

        stage = job.get("stage")
        if stage and stage not in seen:
            seen.append(stage)
            print(f"    {stage:<16} {job.get('progress', 0) * 100:5.1f}%")

        if job["status"] in ("completed", "failed", "cancelled"):
            break
    else:
        _fail("render", "timed out after 900s")
        return False

    if job["status"] != "completed":
        _fail("render", job.get("error") or job["status"])
        return False

    _ok("stages", " -> ".join(seen))

    url = job["videoUrl"]
    video = await client.get("/v1/videos/" + url.rsplit("/", 1)[-1], timeout=600)
    if video.status_code != 200:
        _fail("download", f"{video.status_code} {url}")
        return False

    path = OUT / "render.mp4"
    path.write_bytes(video.content)

    # 'ftyp' at offset 4 is the ISO-BMFF signature; anything else will not play.
    playable = video.content[4:8] == b"ftyp"
    (_ok if playable else _fail)(
        "mp4 downloaded",
        f"{len(video.content) // 1024} KB -> {path.name}"
        + ("" if playable else "  NOT a valid mp4 container"),
    )
    return playable


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="http://127.0.0.1:8000")
    parser.add_argument("--key", default=None, help="Bearer token, if API_KEY is set")
    parser.add_argument("--skip-render", action="store_true")
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    face = _sample_face()
    (OUT / "face.jpg").write_bytes(face)

    headers = {"Authorization": f"Bearer {args.key}"} if args.key else {}

    print(f"Verifying {args.url}")
    async with httpx.AsyncClient(
        base_url=args.url, headers=headers, timeout=60
    ) as client:
        try:
            health = await check_health(client)
        except httpx.ConnectError:
            print(f"\n  Nothing listening on {args.url} — start `python -m devstack.run`")
            return 2

        results = [await check_previews(client, face)]
        if args.skip_render:
            print("\nRender  skipped")
        elif not health.get("videoEnabled"):
            print(f"\nRender  skipped — {health.get('videoError')}")
        elif health.get("videoProvider") == "comfy" and not health.get("comfyReachable"):
            print("\nRender  skipped — ComfyUI unreachable")
        else:
            results.append(await check_render(client, face))

    passed = all(results)
    print(f"\n{'ALL CHECKS PASSED' if passed else 'FAILURES ABOVE'}")
    print(f"Artifacts in {OUT}")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
