"""Provider selection and vendor response handling.

The registry decides which vendor runs, and each provider has to cope with the
shapes its API actually returns — including the failure shapes, which are the
ones that reach users on a free tier.
"""

from __future__ import annotations

import base64
import os

import httpx
import pytest

from app.config import Settings
from app.providers import (
    ComfyImageProvider,
    ComfyVideoProvider,
    GeminiImageProvider,
    PollinationsImageProvider,
    PollinationsVideoProvider,
    ProviderError,
    build_image_provider,
    build_video_provider,
)
from app.providers.pollinations import _read_asset


def _settings(**kwargs) -> Settings:
    return Settings(**kwargs)


# ── registry ──────────────────────────────────────────────────────────────


def test_previews_default_to_gemini() -> None:
    provider = build_image_provider(_settings(gemini_api_key="k"))

    assert isinstance(provider, GeminiImageProvider)
    assert provider.enabled


def test_previews_can_be_switched_to_pollinations() -> None:
    provider = build_image_provider(
        _settings(preview_provider="pollinations", pollinations_api_key="k")
    )

    assert isinstance(provider, PollinationsImageProvider)
    assert provider.enabled


def test_previews_can_run_on_your_own_gpu(tmp_path) -> None:
    """The escape hatch when the hosted free tiers are exhausted.

    A pod costs the same whether it renders one preview or a thousand, so this
    is the only preview path with no daily cap — and the only one that works
    with no API key at all.
    """
    provider = build_image_provider(
        _settings(preview_provider="comfy", comfy_url="http://pod.invalid:8188"),
        workflow_dir=tmp_path,
    )

    assert isinstance(provider, ComfyImageProvider)
    assert provider.enabled
    assert provider.disabled_reason is None


def test_comfy_previews_use_the_image_workflow_not_the_video_one(tmp_path) -> None:
    """Stills and video are different graphs; crossing them wastes GPU minutes."""
    settings = _settings(
        preview_provider="comfy",
        comfy_url="http://pod.invalid:8188",
        comfy_workflow="wan22_animate.json",
        comfy_image_workflow="zimage_probe.json",
    )
    image = build_image_provider(settings, workflow_dir=tmp_path)
    video = build_video_provider(settings, workflow_dir=tmp_path)

    assert image._workflow_path.name == "zimage_probe.json"  # noqa: SLF001
    assert video._workflow_path.name == "wan22_animate.json"  # noqa: SLF001


def test_video_can_be_switched_between_vendors(tmp_path) -> None:
    comfy = build_video_provider(_settings(), workflow_dir=tmp_path)
    hosted = build_video_provider(
        _settings(video_provider="pollinations", pollinations_api_key="k"),
        workflow_dir=tmp_path,
    )

    assert isinstance(comfy, ComfyVideoProvider)
    assert isinstance(hosted, PollinationsVideoProvider)


@pytest.mark.parametrize("value", ["none", "typo-provider"])
def test_unknown_or_none_provider_disables_rather_than_crashes(value, tmp_path) -> None:
    """A bad env var must not take the service down at import time."""
    image = build_image_provider(_settings(preview_provider=value))
    video = build_video_provider(
        _settings(video_provider=value), workflow_dir=tmp_path
    )

    assert not image.enabled
    assert not video.enabled
    assert image.disabled_reason
    assert video.disabled_reason


def test_missing_keys_explain_themselves() -> None:
    gemini = build_image_provider(_settings(gemini_api_key=""))
    pollinations = build_image_provider(
        _settings(preview_provider="pollinations", pollinations_api_key="")
    )

    assert not gemini.enabled
    # The message has to be actionable — this string is surfaced in /v1/health.
    assert "aistudio.google.com" in gemini.disabled_reason
    assert "POLLINATIONS_API_KEY" in pollinations.disabled_reason


# ── Gemini ────────────────────────────────────────────────────────────────


async def test_gemini_returns_the_inline_image(monkeypatch) -> None:
    payload = {
        "candidates": [
            {
                "content": {
                    "parts": [
                        {
                            "inlineData": {
                                "mimeType": "image/jpeg",
                                "data": base64.b64encode(b"JPEGBYTES").decode(),
                            }
                        }
                    ]
                }
            }
        ]
    }
    _patch_httpx(monkeypatch, httpx.Response(200, json=payload))

    asset = await GeminiImageProvider("k").generate_image(
        prompt="as an astronaut", face=b"face"
    )

    assert asset.data == b"JPEGBYTES"
    assert asset.mime_type == "image/jpeg"
    assert asset.extension == ".jpg"


async def test_gemini_quota_is_reported_as_retryable(monkeypatch) -> None:
    _patch_httpx(monkeypatch, httpx.Response(429, json={}))

    with pytest.raises(ProviderError) as caught:
        await GeminiImageProvider("k").generate_image(prompt="p", face=b"f")

    assert caught.value.retryable
    assert "quota" in str(caught.value).lower()


async def test_gemini_blocked_prompt_is_not_retryable(monkeypatch) -> None:
    # A safety block returns 200 with no image part — the easiest failure to
    # mistake for success.
    _patch_httpx(monkeypatch, httpx.Response(200, json={"candidates": []}))

    with pytest.raises(ProviderError) as caught:
        await GeminiImageProvider("k").generate_image(prompt="p", face=b"f")

    assert not caught.value.retryable


async def test_gemini_without_a_key_never_calls_out(monkeypatch) -> None:
    def explode(*args, **kwargs):
        raise AssertionError("should not have made a request")

    monkeypatch.setattr(httpx.AsyncClient, "post", explode)

    with pytest.raises(ProviderError):
        await GeminiImageProvider("").generate_image(prompt="p", face=b"f")


# ── Pollinations ──────────────────────────────────────────────────────────


async def test_pollinations_requires_a_key(monkeypatch) -> None:
    def explode(*args, **kwargs):
        raise AssertionError("should not have made a request")

    monkeypatch.setattr(httpx.AsyncClient, "post", explode)

    with pytest.raises(ProviderError):
        await PollinationsImageProvider("").generate_image(prompt="p", face=b"f")


async def test_pollinations_binary_response(monkeypatch) -> None:
    _patch_httpx(
        monkeypatch,
        httpx.Response(200, content=b"JPEGDATA", headers={"content-type": "image/jpeg"}),
    )

    asset = await PollinationsImageProvider("k").generate_image(
        prompt="as a chef", face=b"face"
    )

    assert asset.data == b"JPEGDATA"
    assert asset.mime_type == "image/jpeg"


async def test_pollinations_b64_json_response(monkeypatch) -> None:
    body = {"data": [{"b64_json": base64.b64encode(b"PNGDATA").decode()}]}
    _patch_httpx(monkeypatch, httpx.Response(200, json=body))

    asset = await PollinationsImageProvider("k").generate_image(prompt="p", face=b"f")

    assert asset.data == b"PNGDATA"


async def test_pollinations_bad_key_is_not_retryable(monkeypatch) -> None:
    _patch_httpx(monkeypatch, httpx.Response(401, json={"error": {"message": "nope"}}))

    with pytest.raises(ProviderError) as caught:
        await PollinationsImageProvider("bad").generate_image(prompt="p", face=b"f")

    assert not caught.value.retryable
    assert "POLLINATIONS_API_KEY" in str(caught.value)


async def test_pollinations_video_rejects_a_non_video_result(monkeypatch) -> None:
    """Naming a still model in POLLINATIONS_VIDEO_MODEL must fail loudly.

    Otherwise a JPEG gets written as `.mp4` and the app shows a broken player
    with no explanation.
    """
    _patch_httpx(
        monkeypatch,
        httpx.Response(200, content=b"JPEG", headers={"content-type": "image/jpeg"}),
    )

    with pytest.raises(ProviderError, match="not a video"):
        await PollinationsVideoProvider("k", "nanobanana").generate_video(
            prompt="p", face=b"f"
        )


async def test_pollinations_video_reports_progress(monkeypatch) -> None:
    _patch_httpx(
        monkeypatch,
        httpx.Response(200, content=b"MP4", headers={"content-type": "video/mp4"}),
    )
    seen: list[float] = []

    asset = await PollinationsVideoProvider("k").generate_video(
        prompt="p", face=b"f", on_progress=lambda v, _: seen.append(v)
    )

    assert asset.mime_type == "video/mp4"
    assert seen and seen[0] == 0.0 and seen[-1] == 1.0


async def test_pollinations_empty_payload_explains_itself() -> None:
    response = httpx.Response(
        200,
        json={"data": [], "error": {"message": "content filtered"}},
        headers={"content-type": "application/json"},
    )

    with pytest.raises(ProviderError, match="content filtered"):
        await _read_asset(response, "http://base", "k", 5)


# ── helper ────────────────────────────────────────────────────────────────


def _patch_httpx(monkeypatch, response: httpx.Response) -> None:
    """Make every AsyncClient.post return `response`."""

    async def post(self, *args, **kwargs):  # noqa: ANN001
        return response

    monkeypatch.setattr(httpx.AsyncClient, "post", post)


# ── .env loading ──────────────────────────────────────────────────────────


def test_env_file_fills_gaps_but_never_overrides(tmp_path, monkeypatch) -> None:
    """A stale local .env must not silently override container or CI config."""
    from app.config import _load_env_file

    env_file = tmp_path / ".env"
    env_file.write_text(
        "\n".join(
            [
                "# a comment",
                "",
                "GEMINI_API_KEY=from-file",
                "POLLINATIONS_API_KEY='quoted-value'",
                "not a pair",
            ]
        ),
        encoding="utf-8",
    )

    monkeypatch.setenv("GEMINI_API_KEY", "from-real-env")
    monkeypatch.delenv("POLLINATIONS_API_KEY", raising=False)

    _load_env_file(env_file)

    assert os.environ["GEMINI_API_KEY"] == "from-real-env"
    assert os.environ["POLLINATIONS_API_KEY"] == "quoted-value"


def test_missing_env_file_is_not_an_error(tmp_path) -> None:
    from app.config import _load_env_file

    _load_env_file(tmp_path / "does-not-exist")


async def test_gemini_distinguishes_no_quota_from_used_up_quota(monkeypatch) -> None:
    """`limit: 0` is a dead end, not a wait — the message must say so."""
    _patch_httpx(
        monkeypatch,
        httpx.Response(
            429,
            text='{"error":{"message":"Quota exceeded ... limit: 0, model: x"}}',
        ),
    )

    with pytest.raises(ProviderError) as caught:
        await GeminiImageProvider("k").generate_image(prompt="p", face=b"f")

    message = str(caught.value)
    assert "aistudio.google.com" in message
    assert "will not help" in message
