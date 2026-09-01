"""End-to-end tests over real HTTP and a real websocket.

Everything in `app/` runs unmodified here — the only substitutions are the two
services that need a GPU or a paid key, and those speak the real protocols (see
devstack/). So these cover the wiring that unit tests with mocked clients
cannot: multipart upload, ComfyUI's graph validation, the websocket progress
sequence, stage blending, file download and the path-traversal guard.

Skipped automatically when the dev-only deps are absent:

    pip install -r requirements-dev.txt
"""

from __future__ import annotations

import asyncio
import base64
import contextlib
import importlib
import io
import json
import socket
from pathlib import Path

import httpx
import pytest

pytest.importorskip("PIL", reason="requirements-dev.txt not installed")
pytest.importorskip("imageio_ffmpeg", reason="requirements-dev.txt not installed")

import uvicorn  # noqa: E402


def _free_port() -> int:
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


@contextlib.asynccontextmanager
async def _serve(app, port: int):
    """Run an ASGI app on a real port for the duration of the block."""
    server = uvicorn.Server(
        uvicorn.Config(app, host="127.0.0.1", port=port, log_level="error")
    )
    task = asyncio.create_task(server.serve())
    while not server.started:
        if task.done():
            task.result()
        await asyncio.sleep(0.02)
    try:
        yield f"http://127.0.0.1:{port}"
    finally:
        server.should_exit = True
        await task


def _face() -> bytes:
    from PIL import Image

    buffer = io.BytesIO()
    Image.new("RGB", (320, 400), (210, 170, 140)).save(buffer, format="JPEG")
    return buffer.getvalue()


@pytest.fixture
async def stack(tmp_path, monkeypatch):
    """The real API wired to the fake ComfyUI and fake Gemini."""
    from devstack import fake_comfy, fake_gemini

    # Keep the render short — this test is about wiring, not throughput.
    monkeypatch.setattr(fake_comfy, "SAMPLE_SECONDS", 1.0)
    monkeypatch.setattr(fake_comfy, "SAMPLE_STEPS", 4)
    monkeypatch.setattr(fake_gemini, "LATENCY_S", (0.0, 0.0))

    comfy_port, gemini_port = _free_port(), _free_port()

    async with _serve(fake_comfy.app, comfy_port) as comfy_url, _serve(
        fake_gemini.app, gemini_port
    ) as gemini_url:
        # The shipped graph is the client's 39-node Wan Animate export, which
        # needs weights and custom nodes no fake can stand in for. The dev stack
        # exists to exercise *the app*, so it runs a representative graph with
        # the same FY_ markers — including FY_TEMPLATE_VIDEO, so the character
        # swap path is covered rather than skipped.
        monkeypatch.setenv("COMFY_WORKFLOW", "devstack_video.json")

        templates = tmp_path / "templates"
        templates.mkdir()
        (templates / "astronaut.mp4").write_bytes(b"fake template clip")
        monkeypatch.setenv("TEMPLATE_DIR", str(templates))

        monkeypatch.setenv("COMFY_URL", comfy_url)
        monkeypatch.setenv("GEMINI_API_KEY", "test-key")
        monkeypatch.setenv("GEMINI_BASE_URL", gemini_url)
        monkeypatch.setenv("OUTPUT_DIR", str(tmp_path / "outputs"))
        monkeypatch.delenv("API_KEY", raising=False)

        from app import config

        config.get_settings.cache_clear()
        main = importlib.reload(importlib.import_module("app.main"))

        api_port = _free_port()
        async with _serve(main.app, api_port) as api_url:
            async with httpx.AsyncClient(base_url=api_url, timeout=120) as client:
                yield client

        config.get_settings.cache_clear()


async def test_health_reports_ready(stack):
    response = await stack.get("/v1/health")

    assert response.status_code == 200
    body = response.json()
    assert body["ready"] is True
    assert body["comfyReachable"] is True
    assert body["workflowValid"] is True, body["workflowError"]
    assert body["previewsEnabled"] is True


async def test_previews_return_decodable_jpegs(stack):
    from PIL import Image

    scenarios = {"astronaut": "floating above the Earth", "chef": "in a kitchen"}
    response = await stack.post(
        "/v1/previews",
        files={"image": ("face.jpg", _face(), "image/jpeg")},
        data={"scenarios": json.dumps(scenarios)},
    )

    assert response.status_code == 200
    body = response.json()
    assert body["errors"] == {}
    assert {p["templateId"] for p in body["previews"]} == set(scenarios)

    for preview in body["previews"]:
        image = Image.open(io.BytesIO(base64.b64decode(preview["imageBase64"])))
        image.verify()  # raises unless it is a genuine, complete image
        assert image.format == "JPEG"


async def test_previews_reject_more_than_forty(stack):
    response = await stack.post(
        "/v1/previews",
        files={"image": ("face.jpg", _face(), "image/jpeg")},
        data={"scenarios": json.dumps({f"t{i}": "scene" for i in range(41)})},
    )

    assert response.status_code == 400


async def test_render_produces_a_playable_mp4(stack):
    response = await stack.post(
        "/v1/renders",
        files={"image": ("face.jpg", _face(), "image/jpeg")},
        data={"prompt": "floating above the Earth", "template_id": "astronaut"},
    )
    assert response.status_code == 202

    job_id = response.json()["id"]
    stages: list[str] = []

    for _ in range(400):
        await asyncio.sleep(0.1)
        job = (await stack.get(f"/v1/renders/{job_id}")).json()
        if job["stage"] and job["stage"] not in stages:
            stages.append(job["stage"])
        if job["status"] in ("completed", "failed", "cancelled"):
            break

    assert job["status"] == "completed", job.get("error")
    assert job["progress"] == 1.0
    # Progress must have come from the websocket, not just the terminal update.
    assert "rendering" in stages

    video = await stack.get("/v1/videos/" + job["videoUrl"].rsplit("/", 1)[-1])
    assert video.status_code == 200
    assert video.headers["content-type"] == "video/mp4"
    # ISO base-media signature: anything else will not play on iOS or Android.
    assert video.content[4:8] == b"ftyp"
    assert len(video.content) > 10_000


async def test_render_rejects_an_empty_prompt(stack):
    response = await stack.post(
        "/v1/renders",
        files={"image": ("face.jpg", _face(), "image/jpeg")},
        data={"prompt": "   "},
    )

    assert response.status_code == 400


async def test_unknown_job_is_404(stack):
    assert (await stack.get("/v1/renders/does-not-exist")).status_code == 404


async def test_video_route_refuses_path_traversal(stack):
    response = await stack.get("/v1/videos/..%2F..%2Fconfig.py")

    assert response.status_code == 404


async def test_comfy_rejects_an_unuploaded_image(stack):
    """The binding-error path a real GPU would hit, without spending one."""
    from app import workflow as wf
    from app.comfy_client import ComfyClient, ComfyError
    from app.config import get_settings

    settings = get_settings()
    graph = wf.build(
        wf.load(Path(__file__).parent.parent / "workflows" / settings.comfy_workflow),
        wf.RenderParams(
            image_name="never-uploaded.jpg",
            prompt="scene",
            width=480,
            height=832,
            frames=81,
        ),
    )

    with pytest.raises(ComfyError, match="not in"):
        await ComfyClient(settings.comfy_url).queue(graph)
