"""Gemini 2.5 Flash Image — the free way to put a real face in a scene.

This is the one genuinely free, genuinely usable option for previews: a key
from https://aistudio.google.com/apikey takes a minute, needs no credit card,
and the free tier is around 500 images a day. It does *image editing with a
reference photo*, which is exactly "keep this person's face, change everything
around it".

Free-tier limits move. Check before launch:
https://ai.google.dev/gemini-api/docs/rate-limits
"""

from __future__ import annotations

import asyncio
import base64
import logging

import httpx

from .base import Asset, ImageProvider, ProviderError

log = logging.getLogger(__name__)

DEFAULT_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

_INSTRUCTION = (
    "Recreate the person from the supplied photo in this scene: {scenario}. "
    "Keep their face, age, skin tone and hair clearly recognisable — this is a "
    "portrait of that specific person, not a generic model. "
    "Vertical 3:4 portrait framing, head and shoulders in the upper third, "
    "photorealistic, cinematic lighting, no text or watermarks."
)


class GeminiImageProvider(ImageProvider):
    name = "gemini"

    def __init__(
        self,
        api_key: str,
        model: str = "gemini-2.5-flash-image",
        *,
        base_url: str = DEFAULT_BASE_URL,
        concurrency: int = 3,
        timeout_s: int = 120,
    ) -> None:
        self._key = api_key
        self._model = model
        self._base = base_url.rstrip("/")
        self._timeout = timeout_s
        # The free tier is limited per minute; a small semaphore keeps a
        # 40-template batch from tripping it all at once.
        self._gate = asyncio.Semaphore(concurrency)

    @property
    def enabled(self) -> bool:
        return bool(self._key)

    @property
    def disabled_reason(self) -> str | None:
        if self.enabled:
            return None
        return "GEMINI_API_KEY is unset — get one free at https://aistudio.google.com/apikey"

    async def generate_image(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template_id: str | None = None,
    ) -> Asset:
        # template_id is part of the ImageProvider contract for providers that
        # paste into the scenario's own artwork. Gemini builds the scene from
        # the prompt, so it has nothing to look up — but it still has to accept
        # the argument or every call through the interface raises TypeError.
        if not self.enabled:
            raise ProviderError(self.disabled_reason or "gemini is not configured")

        body = {
            "contents": [
                {
                    "role": "user",
                    "parts": [
                        {"text": _INSTRUCTION.format(scenario=prompt)},
                        {
                            "inline_data": {
                                "mime_type": face_mime,
                                "data": base64.b64encode(face).decode(),
                            }
                        },
                    ],
                }
            ],
            "generationConfig": {"responseModalities": ["IMAGE"]},
        }

        async with self._gate:
            async with httpx.AsyncClient(timeout=self._timeout) as http:
                try:
                    response = await http.post(
                        f"{self._base}/models/{self._model}:generateContent",
                        headers={
                            "x-goog-api-key": self._key,
                            "Content-Type": "application/json",
                        },
                        json=body,
                    )
                except httpx.HTTPError as exc:
                    raise ProviderError(f"Could not reach Gemini: {exc}", retryable=True) from exc

        if response.status_code == 429:
            raise ProviderError(_quota_message(response.text), retryable=True)
        if response.status_code >= 500:
            raise ProviderError(
                f"Gemini is unavailable ({response.status_code})", retryable=True
            )
        if response.status_code != 200:
            raise ProviderError(
                f"Gemini returned {response.status_code}: {response.text[:400]}"
            )

        data, mime = _first_image(response.json())
        if data is None:
            # Almost always a safety block on the uploaded face.
            raise ProviderError("Gemini returned no image (the prompt may be blocked)")

        return Asset(data=data, mime_type=mime)


def _quota_message(body: str) -> str:
    """Tell the two very different 429s apart.

    "limit: 0" does not mean the daily allowance ran out — it means this
    project has *no* image allowance at all, which is what you get when the key
    belongs to a Cloud project rather than an AI-Studio-managed one. Waiting
    never fixes it, so saying "try again later" sends people down a dead end.
    """
    if "limit: 0" in body:
        return (
            "This key's project has no image quota at all (limit: 0), so waiting "
            "will not help. Create a key at https://aistudio.google.com/apikey "
            "using 'Create API key in new project' — an AI-Studio-managed project "
            "carries the free image tier. Keys bound to an existing Google Cloud "
            "project often do not."
        )
    return "Gemini quota reached for now — try again shortly"


def _first_image(payload: dict) -> tuple[bytes | None, str]:
    for candidate in payload.get("candidates", []):
        for part in candidate.get("content", {}).get("parts", []):
            blob = part.get("inlineData") or part.get("inline_data")
            if blob and blob.get("data"):
                return (
                    base64.b64decode(blob["data"]),
                    blob.get("mimeType") or blob.get("mime_type") or "image/png",
                )
    return None, ""
