"""Free style previews — a still of the user inside each of the 40 scenarios.

Why this exists
---------------
Rendering a clip costs real GPU money. Showing someone their own face in 40
scenarios *before* they pay costs nothing on Gemini's free tier, and it is the
thing that actually sells the paid render.

So: previews are free stills, the final video is the paid thing. The vendor
behind them is chosen in `app/providers` — this file only orchestrates.
"""

from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass

from .providers import Asset, ImageProvider, ProviderError

log = logging.getLogger(__name__)


class PreviewError(RuntimeError):
    """The provider refused, rate-limited, or returned no image."""


@dataclass(frozen=True)
class Preview:
    template_id: str
    image: bytes
    mime_type: str

    @staticmethod
    def of(template_id: str, asset: Asset) -> "Preview":
        return Preview(
            template_id=template_id, image=asset.data, mime_type=asset.mime_type
        )


class PreviewService:
    def __init__(self, provider: ImageProvider) -> None:
        self._provider = provider

    @property
    def enabled(self) -> bool:
        return self._provider.enabled

    @property
    def provider_name(self) -> str:
        return self._provider.name

    @property
    def disabled_reason(self) -> str | None:
        return self._provider.disabled_reason

    async def generate(
        self,
        *,
        template_id: str,
        scenario_prompt: str,
        face_image: bytes,
        face_mime: str = "image/jpeg",
    ) -> Preview:
        try:
            asset = await self._provider.generate_image(
                prompt=scenario_prompt,
                face=face_image,
                face_mime=face_mime,
                template_id=template_id,
            )
        except ProviderError as exc:
            raise PreviewError(str(exc)) from exc
        return Preview.of(template_id, asset)

    async def generate_batch(
        self,
        *,
        face_image: bytes,
        scenarios: dict[str, str],
        face_mime: str = "image/jpeg",
    ) -> tuple[list[Preview], dict[str, str]]:
        """Render many scenarios at once.

        Returns (successes, {template_id: error}). Partial failure is normal on
        a free tier, so callers get both halves rather than an exception.
        """
        results = await asyncio.gather(
            *(
                self.generate(
                    template_id=template_id,
                    scenario_prompt=prompt,
                    face_image=face_image,
                    face_mime=face_mime,
                )
                for template_id, prompt in scenarios.items()
            ),
            return_exceptions=True,
        )

        previews: list[Preview] = []
        errors: dict[str, str] = {}
        for template_id, result in zip(scenarios, results):
            if isinstance(result, Preview):
                previews.append(result)
            else:
                errors[template_id] = str(result)
                log.warning("Preview failed for %s: %s", template_id, result)
        return previews, errors
