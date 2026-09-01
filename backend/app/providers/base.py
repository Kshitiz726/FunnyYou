"""The two things this product needs from an AI vendor.

`ImageProvider` turns a face photo into a still of that person in a scenario.
`VideoProvider` turns it into a short clip. Everything above this layer — the
job store, staged progress, the HTTP surface, the app — is written against
these two interfaces and never against a specific vendor.

That is what makes moving to RunPod later a config change rather than a
rewrite: a new provider is one file plus one line in the registry.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import TYPE_CHECKING, Callable

if TYPE_CHECKING:  # avoids a cycle: template_library imports nothing from here
    from ..template_library import TemplateClip

# Reports fractional progress (0..1) and a short human-readable note. Providers
# that cannot report progress simply never call it.
ProgressHook = Callable[[float, str], None]


class ProviderError(RuntimeError):
    """A provider refused, rate-limited, timed out, or returned nothing usable.

    Carries `retryable` so callers can tell a quota wall (wait and it clears)
    from a bad request (waiting will not help).
    """

    def __init__(self, message: str, *, retryable: bool = False) -> None:
        super().__init__(message)
        self.retryable = retryable


@dataclass(frozen=True)
class Asset:
    data: bytes
    mime_type: str

    @property
    def extension(self) -> str:
        return {
            "image/jpeg": ".jpg",
            "image/png": ".png",
            "image/webp": ".webp",
            "video/mp4": ".mp4",
            "video/webm": ".webm",
        }.get(self.mime_type, ".bin")


class Provider(ABC):
    """Common surface: a name to log and a reason it is or is not usable."""

    name: str = "provider"

    @property
    @abstractmethod
    def enabled(self) -> bool:
        """False when required configuration is missing."""

    @property
    def disabled_reason(self) -> str | None:
        """Why `enabled` is False, phrased so it can be shown in /v1/health."""
        return None if self.enabled else f"{self.name} is not configured"


class ImageProvider(Provider):
    """Generates a still of the supplied person inside a scenario."""

    @abstractmethod
    async def generate_image(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template_id: str | None = None,
    ) -> Asset:
        """Return one image, or raise ProviderError.

        `template_id` lets a provider that works by *swapping* rather than by
        generating find the scenario's reference still. Prompt-driven
        providers ignore it.

        `face` is the user's photo and the result must keep them recognisable —
        a provider that can only do text-to-image is not a valid ImageProvider
        for this product, because "someone else as an astronaut" is not the
        thing being sold.
        """


class VideoProvider(Provider):
    """Generates a short clip of the supplied person inside a scenario."""

    @property
    def requires_points(self) -> bool:
        """Whether a template also needs authored click points to render."""
        return False

    @property
    def requires_template(self) -> bool:
        """Whether a render is impossible without a scenario clip.

        True for character swap, which replaces the performer in an existing
        video; false for text-to-video, which builds the scene from the prompt.
        The caller uses this to fail early with a useful message instead of
        uploading a photo and then discovering the graph had nothing to swap
        into.
        """
        return False

    @abstractmethod
    async def generate_video(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template: "TemplateClip | None" = None,
        on_progress: ProgressHook | None = None,
    ) -> Asset:
        """Return one video, or raise ProviderError.

        `template` is the scenario's pre-made clip, for providers that work by
        character swap rather than by generating a scene from the prompt. It is
        optional because hosted text-to-video providers have nothing to do with
        it — they read the prompt and ignore this entirely.
        """
