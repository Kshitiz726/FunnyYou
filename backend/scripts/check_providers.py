"""Call the real vendor APIs with whatever keys are in the environment.

    python scripts/check_providers.py               # everything configured
    python scripts/check_providers.py --video       # include a video render

This talks to the actual services — it spends real free-tier quota (and real
pollen on Pollinations). It exists to answer one question honestly: *is the AI
working with my keys, right now?*

Results land in `data/providers/` so you can open them and judge the quality,
which is the part no assertion can check for you.

    GEMINI_API_KEY         free, no card    https://aistudio.google.com/apikey
    POLLINATIONS_API_KEY   metered          https://enter.pollinations.ai/keys
"""

from __future__ import annotations

import argparse
import asyncio
import io
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

# Windows consoles default to cp1252 and mangle the punctuation in provider
# messages into replacement characters.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from app.providers import (  # noqa: E402
    GeminiImageProvider,
    PollinationsImageProvider,
    PollinationsVideoProvider,
    ProviderError,
)
from app.providers.base import ImageProvider, VideoProvider  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "data" / "providers"

SCENARIO = (
    "a NASA astronaut in a white spacesuit, helmet visor up, floating in orbit "
    "with Earth glowing behind them, cinematic lighting"
)


def _sample_face() -> bytes:
    """A synthetic portrait, so the check needs no photo on disk."""
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


async def _run(provider, face: bytes, kind: str) -> bool:
    label = f"{provider.name:<20}"

    if not provider.enabled:
        print(f"  [SKIP] {label} {provider.disabled_reason}")
        return True  # not configured is not a failure

    started = time.monotonic()
    try:
        if isinstance(provider, VideoProvider):
            asset = await provider.generate_video(prompt=SCENARIO, face=face)
        else:
            asset = await provider.generate_image(prompt=SCENARIO, face=face)
    except ProviderError as exc:
        tag = "RETRY" if exc.retryable else "FAIL"
        print(f"  [{tag}]  {label} {exc}")
        return exc.retryable
    except Exception as exc:  # noqa: BLE001 — a check script must not traceback
        print(f"  [FAIL]  {label} unexpected {type(exc).__name__}: {exc}")
        return False

    elapsed = time.monotonic() - started
    path = OUT / f"{kind}_{provider.name}{asset.extension}"
    path.write_bytes(asset.data)
    print(
        f"  [PASS]  {label} {len(asset.data) // 1024:>5} KB  {asset.mime_type:<12} "
        f"{elapsed:5.1f}s -> {path.name}"
    )
    return True


async def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--video",
        action="store_true",
        help="also render a clip (slow, and spends real credit)",
    )
    args = parser.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    face = _sample_face()
    (OUT / "face.jpg").write_bytes(face)

    gemini_key = os.getenv("GEMINI_API_KEY", "")
    poll_key = os.getenv("POLLINATIONS_API_KEY", "")

    print("\nStills (these are what fill the 40 tiles)")
    results = [
        await _run(GeminiImageProvider(gemini_key), face, "still"),
        await _run(PollinationsImageProvider(poll_key), face, "still"),
    ]

    if args.video:
        model = os.getenv("POLLINATIONS_VIDEO_MODEL", "wan-fast")
        print(f"\nVideo (model: {model} — this costs real credit and takes minutes)")
        results.append(
            await _run(PollinationsVideoProvider(poll_key, model), face, "video")
        )
    else:
        print("\nVideo  skipped — pass --video to spend credit on a real render")

    if not gemini_key and not poll_key:
        print(
            "\nNo keys set, so nothing was actually tested.\n"
            "  GEMINI_API_KEY is the free one: https://aistudio.google.com/apikey"
        )
        return 2

    ok = all(results)
    print(f"\n{'ALL CONFIGURED PROVIDERS WORK' if ok else 'FAILURES ABOVE'}")
    print(f"Artifacts in {OUT}  — open them and judge the quality yourself.")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
