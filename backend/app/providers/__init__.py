"""Provider registry — the one place a vendor is chosen.

    PREVIEW_PROVIDER=comfy_swap|gemini|pollinations|comfy|none
    VIDEO_PROVIDER=comfy|pollinations|none

Defaults are deliberate: previews default to Gemini because it is the only
hosted option that is free and keeps a real face, and video defaults to ComfyUI
because that is where this is going. Both degrade to `none`, which reports
itself as disabled rather than failing at request time.

`PREVIEW_PROVIDER=comfy` runs previews on your own GPU instead. That is the way
out when the hosted free tiers are exhausted or unavailable — a pod you are
already paying for has no daily cap and no per-image fee.

`PREVIEW_PROVIDER=comfy_swap` goes further: it does not generate a scene at
all, it face-swaps the customer into the scenario artwork the app already
ships. Same picture they tapped, their face in it, ~20s instead of minutes.
"""

from __future__ import annotations

import logging
from pathlib import Path

from ..config import Settings
from .base import (
    Asset,
    ImageProvider,
    ProgressHook,
    Provider,
    ProviderError,
    VideoProvider,
)
from .comfy import (
    ComfyFaceSwapProvider,
    ComfyImageProvider,
    ComfyVideoProvider,
)
from .gemini import GeminiImageProvider
from .pollinations import PollinationsImageProvider, PollinationsVideoProvider

log = logging.getLogger(__name__)

__all__ = [
    "Asset",
    "ImageProvider",
    "ProgressHook",
    "Provider",
    "ProviderError",
    "VideoProvider",
    "ComfyFaceSwapProvider",
    "ComfyImageProvider",
    "ComfyVideoProvider",
    "GeminiImageProvider",
    "PollinationsImageProvider",
    "PollinationsVideoProvider",
    "build_image_provider",
    "build_video_provider",
    "PREVIEW_PROVIDERS",
    "VIDEO_PROVIDERS",
]

PREVIEW_PROVIDERS = ("comfy_swap", "gemini", "pollinations", "comfy", "none")
VIDEO_PROVIDERS = ("comfy", "pollinations", "none")

_WORKFLOW_DIR = Path(__file__).resolve().parent.parent.parent / "workflows"


class _NullImageProvider(ImageProvider):
    name = "none"

    @property
    def enabled(self) -> bool:
        return False

    @property
    def disabled_reason(self) -> str | None:
        return "PREVIEW_PROVIDER=none — style previews are turned off"

    async def generate_image(self, **_) -> Asset:  # pragma: no cover - never enabled
        raise ProviderError(self.disabled_reason or "previews are off")


class _NullVideoProvider(VideoProvider):
    name = "none"

    @property
    def enabled(self) -> bool:
        return False

    @property
    def disabled_reason(self) -> str | None:
        return "VIDEO_PROVIDER=none — rendering is turned off"

    async def generate_video(self, **_) -> Asset:  # pragma: no cover - never enabled
        raise ProviderError(self.disabled_reason or "rendering is off")


def build_image_provider(
    settings: Settings, *, workflow_dir: Path | None = None
) -> ImageProvider:
    choice = (settings.preview_provider or "gemini").strip().lower()

    if choice == "comfy_swap":
        return ComfyFaceSwapProvider(
            base_url=settings.comfy_url,
            workflow_path=(workflow_dir or _WORKFLOW_DIR) / settings.comfy_swap_workflow,
            still_dir=settings.template_still_dir,
            width=settings.preview_width,
            height=settings.preview_height,
            timeout_s=settings.comfy_image_timeout_s,
        )
    if choice == "comfy":
        return ComfyImageProvider(
            base_url=settings.comfy_url,
            workflow_path=(workflow_dir or _WORKFLOW_DIR) / settings.comfy_image_workflow,
            width=settings.preview_width,
            height=settings.preview_height,
            timeout_s=settings.comfy_image_timeout_s,
        )
    if choice == "gemini":
        return GeminiImageProvider(
            settings.gemini_api_key,
            settings.gemini_image_model,
            base_url=settings.gemini_base_url,
        )
    if choice == "pollinations":
        return PollinationsImageProvider(
            settings.pollinations_api_key,
            settings.pollinations_image_model,
            base_url=settings.pollinations_base_url,
        )
    if choice != "none":
        log.warning(
            "Unknown PREVIEW_PROVIDER %r — previews disabled. Valid: %s",
            choice,
            ", ".join(PREVIEW_PROVIDERS),
        )
    return _NullImageProvider()


def build_video_provider(settings: Settings, *, workflow_dir: Path) -> VideoProvider:
    choice = (settings.video_provider or "comfy").strip().lower()

    if choice == "comfy":
        return ComfyVideoProvider(
            base_url=settings.comfy_url,
            workflow_path=workflow_dir / settings.comfy_workflow,
            width=settings.video_width,
            height=settings.video_height,
            frames=settings.frame_count,
            timeout_s=settings.comfy_timeout_s,
            polish_workflow_path=(
                workflow_dir / settings.comfy_polish_workflow
                if settings.comfy_polish_workflow
                else None
            ),
            # Builds the costume reference: the customer's whole head on the
            # scenario's `<id>.ref.png`. Not the preview graph -- see
            # `comfy_reference_workflow` for why a face-only swap is wrong here.
            reference_workflow_path=(
                workflow_dir / settings.comfy_reference_workflow
                if settings.comfy_reference_workflow
                else None
            ),
            seed=settings.video_seed,
        )
    if choice == "pollinations":
        return PollinationsVideoProvider(
            settings.pollinations_api_key,
            settings.pollinations_video_model,
            base_url=settings.pollinations_base_url,
        )
    if choice != "none":
        log.warning(
            "Unknown VIDEO_PROVIDER %r — rendering disabled. Valid: %s",
            choice,
            ", ".join(VIDEO_PROVIDERS),
        )
    return _NullVideoProvider()
