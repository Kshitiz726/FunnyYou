"""Runtime configuration, all via environment variables.

Nothing here has a secret default — the service refuses to start rather than
run with a placeholder key.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

_ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _load_env_file(path: Path = _ENV_FILE) -> None:
    """Read `backend/.env` into the environment, if it exists.

    Keeps API keys in a gitignored file instead of a shell history or a command
    line. Real environment variables always win, so container and CI config is
    never silently overridden by a stale local file.
    """
    if not path.is_file():
        return

    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip("'\"")
        if key and key not in os.environ:
            os.environ[key] = value


_load_env_file()


def _env(name: str, default: str | None = None, *, required: bool = False) -> str:
    value = os.getenv(name, default)
    if required and not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value or ""


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)))
    except ValueError:
        return default


def _env_bool(name: str, default: bool = False) -> bool:
    return os.getenv(name, str(default)).strip().lower() in {"1", "true", "yes", "on"}


@dataclass(frozen=True)
class Settings:
    # ── ComfyUI (the video renderer) ──────────────────────────────────────
    comfy_url: str = field(default_factory=lambda: _env("COMFY_URL", "http://127.0.0.1:8188"))
    comfy_timeout_s: int = field(default_factory=lambda: _env_int("COMFY_TIMEOUT_S", 1800))
    comfy_workflow: str = field(
        default_factory=lambda: _env("COMFY_WORKFLOW", "wan22_animate.json")
    )
    # An optional second pass over the first one's output — the face restore
    # that turns a Wan Animate render into the finished thing. Kept a separate
    # queued render rather than extra nodes because the two stages' models do
    # not fit in the box's memory limit at the same time. Empty means one pass.
    comfy_polish_workflow: str = field(
        default_factory=lambda: _env("COMFY_POLISH_WORKFLOW", "")
    )
    # Builds the costume reference Wan Animate conditions on: the customer's
    # head on the scenario's reference still. This is deliberately NOT
    # `comfy_swap_workflow` -- that one is a plain ReActor swap, which replaces
    # the face region only and leaves the still's own hair in place, so Wan
    # would copy that hair onto the customer. The Qwen graph replaces the whole
    # head, hair included, then ReActor sharpens the face. Empty means hand Wan
    # the bare photo, which renders the customer in their own clothes.
    comfy_reference_workflow: str = field(
        default_factory=lambda: _env(
            "COMFY_REFERENCE_WORKFLOW", "qwen_reactor_hybrid.json"
        )
    )
    # The sampler seed. Pinned by default to the value the approved pirate
    # render used, so a scenario keeps looking the way it was signed off on
    # instead of re-rolling the character every time. Set VIDEO_SEED= (empty)
    # to go back to a fresh random seed per render.
    video_seed: int | None = field(
        default_factory=lambda: (
            int(raw) if (raw := _env("VIDEO_SEED", "552391207544234")).strip() else None
        )
    )
    # Stills use a different, much cheaper graph than video, so they get their
    # own workflow and their own timeout — a preview that takes half an hour is
    # a failure even if it eventually succeeds.
    comfy_image_workflow: str = field(
        default_factory=lambda: _env("COMFY_IMAGE_WORKFLOW", "zimage_probe.json")
    )
    comfy_image_timeout_s: int = field(
        default_factory=lambda: _env_int("COMFY_IMAGE_TIMEOUT_S", 300)
    )

    # ── Gemini (the free style previews) ──────────────────────────────────
    gemini_api_key: str = field(default_factory=lambda: _env("GEMINI_API_KEY"))
    gemini_image_model: str = field(
        default_factory=lambda: _env("GEMINI_IMAGE_MODEL", "gemini-2.5-flash-image")
    )
    # Overridable so the stack can be pointed at a local stub (see devstack/)
    # or a regional/proxy endpoint without touching code.
    gemini_base_url: str = field(
        default_factory=lambda: _env(
            "GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta"
        )
    )

    # ── Which vendor does what ────────────────────────────────────────────
    # See app/providers/__init__.py for the valid values.
    preview_provider: str = field(
        default_factory=lambda: _env("PREVIEW_PROVIDER", "gemini")
    )
    video_provider: str = field(default_factory=lambda: _env("VIDEO_PROVIDER", "comfy"))

    # ── Pollinations (keyed; stills and video behind one API) ─────────────
    pollinations_api_key: str = field(
        default_factory=lambda: _env("POLLINATIONS_API_KEY")
    )
    pollinations_base_url: str = field(
        default_factory=lambda: _env("POLLINATIONS_BASE_URL", "https://gen.pollinations.ai")
    )
    pollinations_image_model: str = field(
        default_factory=lambda: _env("POLLINATIONS_IMAGE_MODEL", "nanobanana")
    )
    pollinations_video_model: str = field(
        default_factory=lambda: _env("POLLINATIONS_VIDEO_MODEL", "wan-fast")
    )

    # ── Storage ───────────────────────────────────────────────────────────
    output_dir: str = field(default_factory=lambda: _env("OUTPUT_DIR", "./data/outputs"))
    # The scenario clips a character swap renders into, named <template_id>.mp4.
    # The scenario artwork a face-swap preview pastes into. Defaults to the
    # app's own bundled tiles so there is one copy, not two.
    template_still_dir: str = field(
        default_factory=lambda: _env("TEMPLATE_STILL_DIR", "../assets/templates")
    )
    comfy_swap_workflow: str = field(
        default_factory=lambda: _env("COMFY_SWAP_WORKFLOW", "reactor_image_swap.json")
    )
    template_dir: str = field(
        default_factory=lambda: _env("TEMPLATE_DIR", "./data/templates")
    )
    public_base_url: str = field(
        default_factory=lambda: _env("PUBLIC_BASE_URL", "http://127.0.0.1:8000")
    )

    # ── Service ───────────────────────────────────────────────────────────
    api_key: str = field(default_factory=lambda: _env("API_KEY"))
    max_upload_bytes: int = field(
        default_factory=lambda: _env_int("MAX_UPLOAD_BYTES", 12 * 1024 * 1024)
    )
    video_seconds: int = field(default_factory=lambda: _env_int("VIDEO_SECONDS", 5))
    video_fps: int = field(default_factory=lambda: _env_int("VIDEO_FPS", 16))
    # 720x1248, not the 480x832 this used to default to. A clip's SAM points
    # are stored as absolute pixels for this frame size, and the graph feeds
    # the same width/height to the PointsEditor -- so rendering at any other
    # size silently moves every click point. At 480x832 the pirate's head point
    # landed 67% across the frame instead of 45%, dragging the mask onto the
    # torso, and Wan repainted the costume it was supposed to leave alone.
    # Changing these means re-authoring every points sidecar to match.
    video_width: int = field(default_factory=lambda: _env_int("VIDEO_WIDTH", 720))
    video_height: int = field(default_factory=lambda: _env_int("VIDEO_HEIGHT", 1248))
    # Previews are shown in a small tile, so they render smaller and faster
    # than the paid video. Only used by providers that let us pick a size.
    preview_width: int = field(default_factory=lambda: _env_int("PREVIEW_WIDTH", 768))
    preview_height: int = field(default_factory=lambda: _env_int("PREVIEW_HEIGHT", 1024))
    dev_mode: bool = field(default_factory=lambda: _env_bool("DEV_MODE", False))

    @property
    def previews_enabled(self) -> bool:
        return bool(self.gemini_api_key)

    @property
    def frame_count(self) -> int:
        """Wan samplers want 4n+1 frames."""
        raw = self.video_seconds * self.video_fps
        return raw - (raw % 4) + 1


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()
