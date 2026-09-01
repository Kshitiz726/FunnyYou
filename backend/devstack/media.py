"""Synthesises real JPEGs and real MP4s from the uploaded face.

The fakes must return genuine, decodable media — not placeholder bytes. The
whole point of the dev stack is to exercise the app's actual image decoding,
video player, gallery save and share paths, and those all fail differently on
malformed files than on missing ones.

The output deliberately does not look AI-generated. It composites the real
uploaded face over a scenario-tinted card with the scenario name burned in, so
you can tell at a glance which template a tile belongs to and confirm the right
photo reached the right scenario.
"""

from __future__ import annotations

import hashlib
import io
import re
import subprocess
import tempfile
from pathlib import Path

import imageio_ffmpeg
from PIL import Image, ImageDraw, ImageFilter, ImageFont

_FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


_BOILERPLATE = re.compile(
    r"^\s*(?:a\s+|an\s+|the\s+)?"
    r"(?:cinematic\s+|photorealistic\s+)?"
    r"(?:portrait|photo|image|shot)?\s*(?:of\s+)?"
    r"(?:the\s+)?person\s*(?:as\s+(?:a|an)\s+)?",
    re.I,
)

_TRAILING = {"in", "a", "an", "the", "with", "and", "of", "on", "at", "his", "her"}


def scenario_label(prompt: str, words: int = 4) -> str:
    """The distinguishing part of a scenario prompt.

    Every template prompt opens the same way ("Portrait of the person as a…"),
    so a naive first-few-words label reads identically on all forty tiles.
    """
    text = _BOILERPLATE.sub("", (prompt or "").strip()) or prompt or "Scenario"
    picked = text.replace(",", " ").split()[:words]
    # Trim trailing filler so labels don't read "NASA astronaut in a".
    while picked and picked[-1].lower() in _TRAILING:
        picked.pop()
    return " ".join(picked)[:38] or "Scenario"


def _palette(seed: str) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    """Stable per-scenario colours, so a template always looks the same."""
    digest = hashlib.sha256(seed.encode()).digest()
    hue = digest[0] / 255.0
    top = _hsv(hue, 0.55, 0.85)
    bottom = _hsv((hue + 0.12) % 1.0, 0.75, 0.45)
    return top, bottom


def _hsv(h: float, s: float, v: float) -> tuple[int, int, int]:
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    r, g, b = [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]
    return int(r * 255), int(g * 255), int(b * 255)


def _font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    for name in ("segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _open_face(face: bytes) -> Image.Image:
    """Decode the upload, or fall back to flat grey if it is not an image."""
    try:
        return Image.open(io.BytesIO(face)).convert("RGB")
    except Exception:  # noqa: BLE001 — a bad upload must not crash the fake
        return Image.new("RGB", (512, 512), (90, 90, 100))


def _circle(image: Image.Image, size: int) -> tuple[Image.Image, Image.Image]:
    """Square-crop to a centred circle, returning (rgb, alpha mask)."""
    side = min(image.size)
    left = (image.width - side) // 2
    top = (image.height - side) // 2
    face = image.crop((left, top, left + side, top + side)).resize(
        (size, size), Image.LANCZOS
    )
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size * 4, size * 4), fill=255)
    return face, mask.resize((size, size), Image.LANCZOS)


def _card(
    face: bytes,
    label: str,
    size: tuple[int, int],
    *,
    offset: int = 0,
    banner: str = "DEV PREVIEW",
) -> Image.Image:
    width, height = size
    top, bottom = _palette(label)

    canvas = Image.new("RGB", (width, height), top)
    draw = ImageDraw.Draw(canvas)
    for y in range(height):
        blend = y / max(height - 1, 1)
        draw.line(
            [(0, y), (width, y)],
            fill=tuple(int(top[i] + (bottom[i] - top[i]) * blend) for i in range(3)),
        )

    portrait = _open_face(face)
    # Composed like a real 3:4 portrait: head and shoulders in the upper third,
    # small enough to survive a hard crop. An oversized face looked fine in the
    # square grid tiles and absurdly zoomed in the wide hero card.
    bubble = int(min(width, height) * 0.30)
    circle, mask = _circle(portrait, bubble)

    cx = (width - bubble) // 2
    cy = int(height * 0.20) - bubble // 2 + offset

    glow = Image.new("RGB", (width, height), (0, 0, 0))
    glow_mask = Image.new("L", (width, height), 0)
    glow_mask.paste(mask, (cx, cy))
    canvas.paste(
        glow.filter(ImageFilter.GaussianBlur(1)),
        (0, 0),
        glow_mask.filter(ImageFilter.GaussianBlur(bubble // 8)).point(
            lambda v: int(v * 0.45)
        ),
    )
    canvas.paste(circle, (cx, cy), mask)

    draw = ImageDraw.Draw(canvas)
    draw.ellipse(
        (cx - 3, cy - 3, cx + bubble + 3, cy + bubble + 3),
        outline=(255, 255, 255),
        width=max(3, bubble // 60),
    )

    title = _font(max(16, int(width * 0.055)))
    caption = _font(max(11, int(width * 0.032)))

    # Sits in the lower quarter so a wide crop drops it entirely, the way a real
    # generated portrait carries no text at all.
    text_y = int(height * 0.76)
    for line, font, alpha in ((label, title, 255), (banner, caption, 165)):
        box = draw.textbbox((0, 0), line, font=font)
        x = (width - (box[2] - box[0])) // 2
        draw.text((x + 2, text_y + 2), line, font=font, fill=(0, 0, 0))
        draw.text((x, text_y), line, font=font, fill=(255, 255, 255, alpha))
        text_y += (box[3] - box[1]) + int(height * 0.035)

    return canvas


def preview_jpeg(face: bytes, label: str, size: tuple[int, int] = (768, 1024)) -> bytes:
    """A still of the uploaded face in a scenario — stands in for Gemini."""
    buffer = io.BytesIO()
    _card(face, label, size, banner="DEV PREVIEW").save(
        buffer, format="JPEG", quality=88
    )
    return buffer.getvalue()


def render_mp4(
    face: bytes,
    label: str,
    *,
    width: int = 480,
    height: int = 832,
    frames: int = 81,
    fps: int = 16,
) -> bytes:
    """A genuinely playable H.264 clip — stands in for Wan 2.2 Animate.

    Encoded with yuv420p and +faststart because Android's MediaCodec and
    AVPlayer both reject anything else, and a fake that produces a file the app
    cannot play would test nothing.
    """
    import math

    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        for index in range(frames):
            phase = math.sin(index / frames * math.tau * 2)
            _card(
                face,
                label,
                (width, height),
                offset=int(phase * height * 0.02),
                banner="DEV RENDER",
            ).save(directory / f"{index:05d}.jpg", quality=85)

        output = directory / "out.mp4"
        subprocess.run(
            [
                _FFMPEG, "-y", "-loglevel", "error",
                "-framerate", str(fps),
                "-i", str(directory / "%05d.jpg"),
                "-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
                "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                str(output),
            ],
            check=True,
            capture_output=True,
        )
        return output.read_bytes()
