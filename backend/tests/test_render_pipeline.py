"""End-to-end render pipeline against a fake ComfyUI.

Covers the job lifecycle the app depends on: stages advance in order, progress
never goes backwards, the video lands on disk, and failures surface as a
FAILED job rather than a hung one.

Exercises the real ComfyVideoProvider with only its HTTP client swapped, so the
workflow binding and progress reporting are the shipped code.
"""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
from typing import AsyncIterator

import pytest

from app.comfy_client import (
    ComfyAsset,
    ComfyError,
    ComfyProgress,
    ComfyRenderFailed,
)
from app.config import Settings
from app.jobs import JobStatus, JobStore, Stage
from app.providers.comfy import ComfyVideoProvider
from app.render_service import RenderService

WORKFLOW_DIR = Path(__file__).parent.parent / "workflows"

VIDEO_BYTES = b"\x00\x00\x00\x18ftypmp42fake-mp4-payload"


class FakeComfy:
    """Stands in for a running ComfyUI box."""

    def __init__(self, *, fail_at: str | None = None) -> None:
        self.fail_at = fail_at
        self.output_filenames = ["funnyyou_00001.png", "funnyyou_00001.mp4"]
        # A character-swap render uploads twice — the customer's face and the
        # scenario clip — so keep every one rather than only the last.
        self.uploads: list[tuple[str, bytes]] = []
        self.queued_graph: dict | None = None
        self.sessions = 0

    @property
    def uploaded(self) -> bytes | None:
        return self.uploads[0][1] if self.uploads else None

    def session(self) -> "FakeComfy":
        # The real client returns a *new* client here so concurrent renders get
        # separate websocket identities; the fake has no socket, so it counts
        # the calls instead and hands itself back.
        self.sessions += 1
        return self

    async def health(self) -> bool:
        return True

    async def upload_image(self, data: bytes, filename: str) -> str:
        if self.fail_at == "upload":
            raise ComfyError("upload exploded")
        self.uploads.append((filename, data))
        return filename

    async def queue(self, workflow: dict) -> str:
        if self.fail_at == "queue":
            raise ComfyError("workflow rejected: node 40 is missing an input")
        self.queued_graph = workflow
        return "prompt-1"

    async def watch(self, prompt_id: str) -> AsyncIterator[ComfyProgress]:
        for i in range(1, 6):
            if self.fail_at == "watch" and i == 3:
                raise ComfyError("CUDA out of memory")
            yield ComfyProgress(value=i / 5, node="40", stage="sampling")

    async def outputs(self, prompt_id: str) -> list[ComfyAsset]:
        if self.fail_at == "render":
            raise ComfyRenderFailed("ComfyUI failed in KSampler: out of memory")
        return [
            ComfyAsset(filename=name, subfolder="", type="output")
            for name in self.output_filenames
        ]

    async def download(self, asset: ComfyAsset) -> bytes:
        return VIDEO_BYTES


@pytest.fixture
def service(tmp_path: Path) -> tuple[RenderService, JobStore, FakeComfy]:
    templates = tmp_path / "templates"
    templates.mkdir()
    for name in ("chef", "pirate", "astronaut"):
        (templates / f"{name}.mp4").write_bytes(b"fake template clip")
        # A Wan Animate graph will not render a clip that has no click
        # points, so an installed clip means the sidecar too.
        (templates / f"{name}.points.json").write_text(
            json.dumps(
                {
                    "positive": [{"x": 0.5, "y": 0.3}],
                    "negative": [{"x": 0.05, "y": 0.05}],
                }
            ),
            encoding="utf-8",
        )

    settings = Settings(
        output_dir=str(tmp_path / "outputs"),
        template_dir=str(templates),
        public_base_url="https://render.example.com",
    )
    store = JobStore()

    provider = ComfyVideoProvider(
        base_url="http://comfy.invalid",
        workflow_path=WORKFLOW_DIR / settings.comfy_workflow,
        width=settings.video_width,
        height=settings.video_height,
        frames=settings.frame_count,
    )
    fake = FakeComfy()
    provider._client = fake  # noqa: SLF001 — deliberate seam for tests

    return RenderService(settings, store, provider), store, fake


async def _drain(job) -> None:
    await asyncio.wait_for(job.task, timeout=10)


@pytest.mark.asyncio
async def test_successful_render_produces_a_playable_url(service) -> None:
    svc, store, fake = service

    job = svc.start(face_image=b"jpegbytes", prompt="the person as a chef",
                    template_id="chef")
    await _drain(job)

    done = store.get(job.id)
    assert done.status is JobStatus.COMPLETED
    assert done.stage is Stage.DONE
    assert done.progress == 1.0
    assert done.error is None
    assert done.video_url == f"https://render.example.com/v1/videos/{job.id}.mp4"

    # The mp4 was preferred over the png thumbnail, and written to disk intact.
    written = Path(svc._output_dir) / f"{job.id}.mp4"  # noqa: SLF001
    assert written.read_bytes() == VIDEO_BYTES

    # Both halves of a character swap reached ComfyUI: the customer's face and
    # the scenario clip it is being swapped into.
    assert ("face.jpg", b"jpegbytes") in fake.uploads
    assert ("chef.mp4", b"fake template clip") in fake.uploads


@pytest.mark.asyncio
async def test_prompt_reaches_the_workflow(service) -> None:
    svc, _, fake = service

    job = svc.start(face_image=b"x", prompt="the person as a pirate captain",
                    template_id="pirate")
    await _drain(job)

    texts = [
        node["inputs"]["text"]
        for node in fake.queued_graph.values()
        if node.get("class_type") == "CLIPTextEncode"
    ]
    assert "the person as a pirate captain" in texts


@pytest.mark.asyncio
async def test_progress_is_monotonic_and_stages_advance(service) -> None:
    svc, store, _ = service
    seen: list[tuple[Stage, float]] = []

    original = store.update

    def spy(job_id, **kwargs):
        result = original(job_id, **kwargs)
        if result:
            seen.append((result.stage, result.progress))
        return result

    store.update = spy  # type: ignore[method-assign]

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    await _drain(job)

    progresses = [p for _, p in seen]
    assert progresses == sorted(progresses), "progress went backwards"

    stages = [s for s, _ in seen]
    for stage in (Stage.UPLOADING, Stage.MATCHING_FACE, Stage.BUILDING_SCENE,
                  Stage.RENDERING, Stage.FINISHING, Stage.DONE):
        assert stage in stages, f"{stage} never reported"


@pytest.mark.asyncio
@pytest.mark.parametrize("fail_at", ["upload", "queue", "render"])
async def test_failures_land_as_failed_jobs_not_hangs(service, fail_at: str) -> None:
    svc, store, fake = service
    fake.fail_at = fail_at

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    await _drain(job)

    failed = store.get(job.id)
    assert failed.status is JobStatus.FAILED
    assert failed.error
    assert failed.video_url is None


@pytest.mark.asyncio
async def test_a_dropped_progress_stream_does_not_fail_the_render(service) -> None:
    """The websocket is how progress is reported, not how the render is run.

    Over an SSH tunnel to the pod the socket is the fragile part, and it
    drops on renders that are minutes long while the GPU carries on happily.
    Failing the job there would throw away a render that is about to land —
    so the provider stops listening and asks history instead.
    """
    svc, store, fake = service
    fake.fail_at = "watch"

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    await _drain(job)

    done = store.get(job.id)
    assert done.status is JobStatus.COMPLETED, done.error
    assert done.video_url


@pytest.mark.asyncio
async def test_cancel_stops_the_render(service) -> None:
    svc, store, _ = service

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    assert await store.cancel(job.id)

    with pytest.raises((asyncio.CancelledError, asyncio.TimeoutError)):
        await _drain(job)
    assert store.get(job.id).status is JobStatus.CANCELLED


def test_frame_count_is_a_multiple_of_four_plus_one() -> None:
    # Wan's temporal VAE requires 4n+1 frames; a wrong count fails deep inside
    # the sampler with an unhelpful shape error.
    for seconds, fps in [(5, 16), (3, 24), (8, 16), (2, 30)]:
        frames = Settings(video_seconds=seconds, video_fps=fps).frame_count
        assert frames % 4 == 1, f"{seconds}s@{fps}fps produced {frames}"


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "filename,expected",
    [
        ("clip_00001.mp4", ".mp4"),
        ("clip_00001.webm", ".webm"),
        ("anim_00001.webp", ".webp"),
        ("still_00001.png", ".png"),
    ],
)
async def test_output_extension_follows_the_actual_file(
    service, filename: str, expected: str
) -> None:
    """A webp or png must not be written out as .mp4.

    Wan graphs legitimately emit animated webp, and a misconfigured graph emits
    a still. Labelling either one video/mp4 hands the app a file its player
    cannot open, which reads as a broken render rather than the workflow
    problem it actually is.
    """
    svc, store, fake = service
    fake.output_filenames = [filename]

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    await _drain(job)

    done = store.get(job.id)
    assert done.status is JobStatus.COMPLETED
    assert done.video_url.endswith(expected)
    assert (Path(svc._output_dir) / f"{job.id}{expected}").exists()  # noqa: SLF001


def test_each_render_gets_its_own_websocket_identity() -> None:
    """Concurrent renders must not share a ComfyUI clientId.

    ComfyUI overwrites its socket registry entry when a second socket connects
    with the same clientId, so the earlier render stops receiving progress and
    its completion message entirely — it hangs until the render timeout rather
    than failing. Previews run six at a time, so a shared id hangs five of six.
    """
    from app.comfy_client import ComfyClient

    client = ComfyClient("http://comfy.invalid", timeout_s=42)
    a, b = client.session(), client.session()

    assert a._client_id != b._client_id  # noqa: SLF001
    assert a._client_id != client._client_id  # noqa: SLF001
    # Everything else must carry over, or sessions would silently lose config.
    assert a._base == client._base and a._timeout == 42  # noqa: SLF001


@pytest.mark.asyncio
async def test_the_provider_opens_a_session_per_render(service) -> None:
    """Guards the wiring, not just the client — the bug was using self._client."""
    svc, _, fake = service

    await _drain(svc.start(face_image=b"x", prompt="p", template_id="chef"))
    await _drain(svc.start(face_image=b"x", prompt="p", template_id="chef"))

    assert fake.sessions == 2


@pytest.mark.asyncio
async def test_a_video_is_preferred_over_a_thumbnail(service) -> None:
    """Graphs that save a poster frame alongside the clip must yield the clip."""
    svc, store, fake = service
    fake.output_filenames = ["poster_00001.png", "clip_00001.mp4"]

    job = svc.start(face_image=b"x", prompt="p", template_id="chef")
    await _drain(job)

    assert store.get(job.id).video_url.endswith(".mp4")


@pytest.mark.asyncio
async def test_missing_template_fails_before_spending_gpu_time(service) -> None:
    """A character swap with no clip must fail early and say what is missing.

    The alternative is worse than an error: the graph still holds the author's
    own placeholder video, so without this guard a paying customer would get a
    render of a stranger performing the scenario.
    """
    svc, store, fake = service

    job = svc.start(face_image=b"x", prompt="p", template_id="wizard")
    await _drain(job)

    failed = store.get(job.id)
    assert failed.status is JobStatus.FAILED
    assert "wizard.mp4" in failed.error
    assert fake.uploads == [], "nothing should reach the GPU"


@pytest.mark.asyncio
async def test_the_template_clip_is_bound_into_the_graph(service) -> None:
    svc, _, fake = service

    await _drain(svc.start(face_image=b"x", prompt="p", template_id="astronaut"))

    from app import workflow as wf

    node = wf.find_by_title(fake.queued_graph, wf.MARKER_TEMPLATE_VIDEO)
    assert node, "the shipped graph lost its FY_TEMPLATE_VIDEO marker"
    assert fake.queued_graph[node]["inputs"]["video"] == "astronaut.mp4"
