"""Pollinations — one keyed API for both face-referenced stills and video.

Why it is here
--------------
Pollinations fronts a catalogue that includes the models this product actually
wants, behind a single OpenAI-shaped endpoint:

    stills  nanobanana (Gemini 2.5 Flash Image), kontext, seedream, gptimage
    video   wan, wan-fast, seedance-pro, veo, grok-imagine-video-1.5

`wan` is the same family the client's ComfyUI workflow targets, which makes
this the closest thing to a drop-in stand-in for the RunPod render while that
is still being built.

What it costs
-------------
Measured against the live API, not taken from the docs:

* **Anonymous is not viable.** Un-keyed requests get roughly one generation per
  hour per IP. The first call succeeds and everything after it is 401. Fine for
  a smoke test, useless for an app.
* **Face-referenced editing and every video model require a key**, on both
  `/v1/images/edits` and `GET /image/{prompt}`. There is no free face path.

So this provider is deliberately hard-disabled without `POLLINATIONS_API_KEY`.
Keys come from https://enter.pollinations.ai/keys and are metered in "pollen".

Multipart, not URLs
-------------------
The face is uploaded as multipart to `/v1/images/edits`. The alternative — the
`?image=<url>` form — would mean publishing users' faces at a public URL to let
a third party fetch them, which is not an acceptable thing to do with people's
photographs.
"""

from __future__ import annotations

import asyncio
import base64
import logging

import httpx

from .base import Asset, ImageProvider, ProgressHook, ProviderError, VideoProvider

log = logging.getLogger(__name__)

DEFAULT_BASE_URL = "https://gen.pollinations.ai"

_STILL_INSTRUCTION = (
    "Recreate the person from the supplied photo in this scene: {scenario}. "
    "Keep their face clearly recognisable. Vertical portrait framing, "
    "photorealistic, no text or watermarks."
)

_VIDEO_INSTRUCTION = (
    "Animate the person from the supplied photo in this scene: {scenario}. "
    "Keep their face clearly recognisable throughout. Smooth natural motion, "
    "vertical portrait video, no text or watermarks."
)


class _PollinationsBase:
    def __init__(
        self,
        api_key: str,
        model: str,
        *,
        base_url: str = DEFAULT_BASE_URL,
        timeout_s: int = 600,
    ) -> None:
        self._key = api_key
        self._model = model
        self._base = base_url.rstrip("/")
        self._timeout = timeout_s

    @property
    def enabled(self) -> bool:
        return bool(self._key)

    @property
    def disabled_reason(self) -> str | None:
        if self.enabled:
            return None
        return (
            "POLLINATIONS_API_KEY is unset — anonymous access is capped at about "
            "one generation per hour per IP, and every face-referenced or video "
            "model requires a key (https://enter.pollinations.ai/keys)"
        )

    async def _edit(self, *, prompt: str, face: bytes, face_mime: str) -> Asset:
        """POST the face plus an instruction, get media back."""
        if not self.enabled:
            raise ProviderError(self.disabled_reason or "pollinations is not configured")

        async with httpx.AsyncClient(timeout=self._timeout) as http:
            try:
                response = await http.post(
                    f"{self._base}/v1/images/edits",
                    headers={"Authorization": f"Bearer {self._key}"},
                    data={"model": self._model, "prompt": prompt},
                    files={"image": ("face.jpg", face, face_mime)},
                )
            except httpx.HTTPError as exc:
                raise ProviderError(
                    f"Could not reach Pollinations: {exc}", retryable=True
                ) from exc

        if response.status_code in (401, 403):
            raise ProviderError(
                "Pollinations rejected the key. Check POLLINATIONS_API_KEY, and "
                "that the account has pollen left."
            )
        if response.status_code == 429:
            raise ProviderError("Pollinations rate limit reached", retryable=True)
        if response.status_code >= 500:
            raise ProviderError(
                f"Pollinations is unavailable ({response.status_code})", retryable=True
            )
        if response.status_code != 200:
            raise ProviderError(
                f"Pollinations returned {response.status_code}: {response.text[:400]}"
            )

        return await _read_asset(response, self._base, self._key, self._timeout)


class PollinationsImageProvider(_PollinationsBase, ImageProvider):
    name = "pollinations-image"

    def __init__(self, api_key: str, model: str = "nanobanana", **kwargs) -> None:
        super().__init__(api_key, model, **kwargs)

    async def generate_image(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template_id: str | None = None,
    ) -> Asset:
        return await self._edit(
            prompt=_STILL_INSTRUCTION.format(scenario=prompt),
            face=face,
            face_mime=face_mime,
        )


class PollinationsVideoProvider(_PollinationsBase, VideoProvider):
    name = "pollinations-video"

    def __init__(self, api_key: str, model: str = "wan-fast", **kwargs) -> None:
        super().__init__(api_key, model, **kwargs)

    async def generate_video(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template: object | None = None,
        on_progress: ProgressHook | None = None,
    ) -> Asset:
        # `template` is deliberately ignored: this vendor generates a scene from
        # the prompt rather than swapping into an existing clip. Accepting and
        # dropping it keeps the two strategies interchangeable behind one call.
        # The endpoint is a single blocking call with no progress channel, so
        # the caller gets a coarse "started" and then the finished file. The
        # staged progress the app draws comes from RenderService, not here.
        if on_progress:
            on_progress(0.0, f"queued on {self._model}")

        asset = await self._edit(
            prompt=_VIDEO_INSTRUCTION.format(scenario=prompt),
            face=face,
            face_mime=face_mime,
        )

        if not asset.mime_type.startswith("video/"):
            raise ProviderError(
                f"{self._model} returned {asset.mime_type}, not a video — check "
                "POLLINATIONS_VIDEO_MODEL names a video-capable model"
            )
        if on_progress:
            on_progress(1.0, "downloaded")
        return asset


async def _read_asset(
    response: httpx.Response, base: str, key: str, timeout_s: int
) -> Asset:
    """Normalise the three shapes this API answers with.

    Binary is the common case; the OpenAI-compatible JSON forms (`b64_json` and
    a `url` to fetch) show up on some models, and video is likeliest to use the
    URL form because the files are large.
    """
    content_type = response.headers.get("content-type", "").split(";")[0].strip()

    if content_type and not content_type.startswith("application/json"):
        return Asset(data=response.content, mime_type=content_type)

    try:
        payload = response.json()
    except ValueError as exc:
        raise ProviderError("Pollinations returned an unreadable response") from exc

    items = payload.get("data") or []
    if not items:
        message = (payload.get("error") or {}).get("message") or str(payload)[:300]
        raise ProviderError(f"Pollinations returned no media: {message}")

    item = items[0]

    if item.get("b64_json"):
        return Asset(
            data=base64.b64decode(item["b64_json"]),
            mime_type=item.get("mime_type") or "image/jpeg",
        )

    url = item.get("url") or item.get("video_url")
    if not url:
        raise ProviderError(f"Pollinations returned no media: {str(item)[:300]}")

    async with httpx.AsyncClient(timeout=timeout_s, follow_redirects=True) as http:
        fetched = await http.get(
            url, headers={"Authorization": f"Bearer {key}"} if url.startswith(base) else {}
        )
    if fetched.status_code != 200:
        raise ProviderError(f"Could not download the result ({fetched.status_code})")

    return Asset(
        data=fetched.content,
        mime_type=fetched.headers.get("content-type", "application/octet-stream")
        .split(";")[0]
        .strip(),
    )
