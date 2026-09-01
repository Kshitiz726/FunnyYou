"""Shared test setup.

The important job here is isolation from the developer's own machine.
`app.config` loads `backend/.env` at import time so real keys never have to be
typed on a command line — but that means a local `.env` would otherwise change
what the tests assert, and a suite that passes for you and fails in CI (or the
reverse) is worse than no suite.
"""

from __future__ import annotations

import os

import pytest

# Every variable that changes which provider runs or how it is configured.
_PROVIDER_ENV = (
    "PREVIEW_PROVIDER",
    "VIDEO_PROVIDER",
    "GEMINI_API_KEY",
    "GEMINI_BASE_URL",
    "GEMINI_IMAGE_MODEL",
    "POLLINATIONS_API_KEY",
    "POLLINATIONS_BASE_URL",
    "POLLINATIONS_IMAGE_MODEL",
    "POLLINATIONS_VIDEO_MODEL",
    "COMFY_URL",
    "COMFY_WORKFLOW",
    "COMFY_IMAGE_WORKFLOW",
    "COMFY_IMAGE_TIMEOUT_S",
    "PREVIEW_WIDTH",
    "PREVIEW_HEIGHT",
    "API_KEY",
    "OUTPUT_DIR",
    "PUBLIC_BASE_URL",
)


@pytest.fixture(autouse=True)
def _hermetic_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Run every test against defaults, not against whatever `.env` holds.

    Tests that want a specific provider set it themselves — explicitly, so the
    intent is visible in the test rather than in someone's untracked file.
    """
    for name in _PROVIDER_ENV:
        monkeypatch.delenv(name, raising=False)

    # Settings is lru_cached; a stale instance would outlive the cleanup above.
    from app.config import get_settings

    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


@pytest.fixture(autouse=True)
def _no_accidental_network(
    _hermetic_env: None, request: pytest.FixtureRequest
) -> None:
    """Fail loudly if a unit test reaches a real vendor.

    A test that silently calls Gemini or Pollinations spends real quota and
    real money, and only fails when someone else runs it offline.

    Depends on `_hermetic_env` so the cleanup is guaranteed to have run first.
    Two autouse fixtures have no defined order between them otherwise, so this
    would intermittently fire on the developer's own `.env` — the very keys the
    other fixture exists to remove.
    """
    if "allow_network" in request.keywords:
        return
    assert not os.environ.get("GEMINI_API_KEY"), "a test leaked a real key"
    assert not os.environ.get("POLLINATIONS_API_KEY"), "a test leaked a real key"
