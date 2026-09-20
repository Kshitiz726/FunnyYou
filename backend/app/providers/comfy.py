"""ComfyUI on your own GPU — the RunPod path.

This is where the product is heading: a rented GPU running the client's own
proven workflow. Both providers here are ordinary `ImageProvider` /
`VideoProvider` implementations, so switching to them is `PREVIEW_PROVIDER=comfy`
or `VIDEO_PROVIDER=comfy` plus a reachable `COMFY_URL` — no code change anywhere
above this file.

Running previews here instead of Gemini matters more than it sounds: a rented
GPU has no daily cap and no per-image fee, so once the pod is up, previews stop
depending on a vendor free tier that may be zero.

Unlike the hosted providers these report real progress, because ComfyUI streams
sampler steps over a websocket.
"""

from __future__ import annotations

import asyncio
import io
import math
import logging
from pathlib import Path

from typing import TYPE_CHECKING

from .. import workflow as wf
from ..comfy_client import ComfyAsset, ComfyClient, ComfyError, ComfyRenderFailed
from ..gpu_guard import gpu_turn
from ..still_library import StillLibrary
from .base import Asset, ImageProvider, ProgressHook, ProviderError, VideoProvider

if TYPE_CHECKING:
    from ..template_library import TemplateClip

log = logging.getLogger(__name__)

# Workflows do not always end in an mp4: animated webp and png sequences are
# common Wan outputs, and a misconfigured graph can return a still. Labelling
# any of those "video/mp4" writes a .mp4 the player cannot open, which surfaces
# to the user as a broken video rather than as the workflow problem it is.
_MIME_BY_SUFFIX = {
    ".mp4": "video/mp4",
    ".webm": "video/webm",
    ".mkv": "video/x-matroska",
    ".gif": "image/gif",
    ".webp": "image/webp",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
}

_VIDEO_SUFFIXES = (".mp4", ".webm", ".mkv")
_IMAGE_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp")

# The costume reference's sampler seed. `build()` rolls a random seed whenever
# the caller passes none, which made every hybrid a fresh dice roll: the same
# face and the same still produced a usable head swap on one run and collapsed
# to the bare selfie on the next. A reference that cannot be reproduced cannot
# be judged, so this is pinned to the value the graph was authored with.
_REFERENCE_SEED = 362225868152841


def _mime_for(filename: str) -> str:
    return _MIME_BY_SUFFIX.get(Path(filename).suffix.lower(), "application/octet-stream")


def _pick(assets: list[ComfyAsset], prefer: tuple[str, ...]) -> ComfyAsset:
    """Choose the output the caller actually asked for.

    Graphs routinely save more than one thing — a poster frame beside a clip,
    or a debug still beside the real image. Falling back to `assets[0]` keeps a
    single-output graph working without special-casing it.

    **VideoHelperSuite writes the soundtrack as a second file.** When an `audio`
    input is connected it saves `name.mp4` (silent) *and* `name-audio.mp4`, and
    lists both. Picking the first match gets the silent one, which is why
    renders came back mute even with the audio wired and ffmpeg installed.
    """
    matching = [a for a in assets if a.filename.lower().endswith(prefer)]
    if not matching:
        return assets[0]
    return next(
        (a for a in matching if "-audio" in a.filename.lower()),
        matching[0],
    )


# ComfyUI names the running node by class. These are the ones a Wan Animate
# render actually spends time in, in the words a customer can act on -- anything
# unlisted reports nothing rather than leaking a class name into the UI.
_PHASES = {
    "UNETLoader": "Loading the model",
    "CheckpointLoaderSimple": "Loading the model",
    "CLIPLoader": "Loading the model",
    "VAELoader": "Loading the model",
    "LoraLoaderModelOnly": "Loading the model",
    "CLIPVisionLoader": "Loading the model",
    "DownloadAndLoadSAM2Model": "Loading the model",
    "VHS_LoadVideo": "Reading the template",
    "LoadImage": "Reading your photo",
    "Sam2Segmentation": "Finding the head",
    "DWPreprocessor": "Tracking the pose",
    "FaceMaskFromPoseKeypoints": "Tracking the face",
    "GrowMask": "Building the mask",
    "BlockifyMask": "Building the mask",
    "MaskComposite": "Building the mask",
    "CLIPVisionEncode": "Reading your face",
    "CLIPTextEncode": "Reading the scene",
    "WanAnimateToVideo": "Preparing the scene",
    "KSampler": "Rendering",
    "VAEDecode": "Decoding frames",
    "ImageScale": "Scaling frames",
    "ReActorFaceSwap": "Matching your face",
    "ReActorFaceBoost": "Sharpening your face",
    "VHS_VideoCombine": "Encoding the video",
}


def _node_types(graph: dict) -> dict[str, str]:
    """{node id: class_type} — the websocket names nodes by id only."""
    return {
        node_id: node.get("class_type", "")
        for node_id, node in (graph or {}).items()
        if isinstance(node, dict)
    }


# Only these advance the overall number; every other node's bar is detail.
_SAMPLER_NODES = {"KSampler", "KSamplerAdvanced", "SamplerCustom"}


def _phase(node_type: str | None) -> str | None:
    return _PHASES.get(node_type or "")


def _span(report: ProgressHook, low: float, high: float) -> ProgressHook:
    """Re-aim a pass's own 0..1 at its slice of the whole render's bar.

    A pass knows how far through itself it is and nothing about the pass
    beside it, so left alone each one drives the bar from empty to full.
    """

    def scaled(value: float | None, note: str) -> None:
        report(None if value is None else low + value * (high - low), note)

    return scaled


class _ComfyProvider:
    """Upload, bind, queue, follow, download — shared by both providers."""

    def __init__(
        self,
        *,
        base_url: str,
        workflow_path: Path,
        width: int,
        height: int,
        frames: int | None = None,
        timeout_s: int = 1800,
        polish_workflow_path: Path | None = None,
        reference_workflow_path: Path | None = None,
        seed: int | None = None,
    ) -> None:
        self._client = ComfyClient(base_url, timeout_s)
        self._workflow_path = workflow_path
        self._polish_workflow_path = polish_workflow_path
        self._reference_workflow_path = reference_workflow_path
        self._seed = seed
        self._width = width
        self._height = height
        self._frames = frames
        self._base_url = base_url

    # How long to keep asking history for a finished render, and how long to
    # tolerate silence on the progress websocket before abandoning it.
    _poll_interval_s = 2.0
    _poll_timeout_s = 1800.0
    _progress_idle_timeout_s = 120.0

    # How the two queued passes divide the bar. Pass one — segmentation,
    # pose, then eight sampler steps on a 14B model — is the long one; pass
    # two runs a face restore over frames that already exist. Measured on
    # the pod at roughly thirteen minutes against six.
    #
    # Both passes used to report into the same 0..1, and the store refuses
    # to let progress go backwards, so pass one finishing pinned the ring at
    # its maximum and the whole of pass two ran inside that last pixel.
    _pass_one_share = 0.7

    # When the progress socket goes quiet we keep the ring creeping toward,
    # but never onto, the end of the pass. Sized to the silence we actually
    # see: the Wan sampler emits nothing across its whole eight-step run.
    _stall_time_constant_s = 360.0
    _stall_ceiling = 0.97

    async def _await_outputs(self, client, prompt_id: str, on_wait=None):
        """Poll history for the finished render.

        The websocket is a nicety for the progress bar; history is the source
        of truth. Over an SSH tunnel to the pod the socket is the fragile part
        — a dropped connection leaves `watch` waiting for a completion message
        that already happened. Polling cannot miss it, because the result is
        sitting in history either way.
        """
        loop = asyncio.get_running_loop()
        started = loop.time()
        deadline = started + self._poll_timeout_s
        last_error: ComfyError | None = None

        while loop.time() < deadline:
            try:
                return await client.outputs(prompt_id)
            except ComfyRenderFailed:
                # The render is over and it went wrong — say so now rather
                # than waiting out the timeout on a job that cannot recover.
                raise
            except ComfyError as exc:
                # "no history yet" simply means it is still queued or running.
                last_error = exc
                if on_wait is not None:
                    on_wait(loop.time() - started)
                await asyncio.sleep(self._poll_interval_s)

        raise ComfyError(
            f"Render did not finish within {self._poll_timeout_s}s"
            + (f" ({last_error})" if last_error else "")
        )

    def _creep(self, report: ProgressHook, reached: float, note: str):
        """Keep a pass's share of the bar moving while we poll history blind.

        Asymptotic on purpose: it has no idea how much is left, so it must
        never be able to arrive. A ring that crawls is honest about not
        knowing; a ring parked at the end is a promise the render breaks.
        """
        ceiling = max(reached, self._stall_ceiling)

        def on_wait(elapsed: float) -> None:
            share = 1.0 - math.exp(-elapsed / self._stall_time_constant_s)
            report(reached + (ceiling - reached) * share, note)

        return on_wait

    async def _polish(self, client, data, chosen, image_name, prefer, report):
        """Run the face-restore pass as a second queued render.

        Both passes could live in one graph, and briefly did — but the render
        box has a 62 GB container limit, and holding Wan's ~28 GB of weights
        resident while ReActor loads its own is enough to get the whole server
        OOM-killed at the final encode, after fifteen minutes of work. It is
        also how these renders were originally produced.

        Splitting them is not on its own enough: ComfyUI keeps a finished
        prompt's models loaded, so pass two stacked its weights on pass one's
        and hit the cap anyway — the server died with no traceback, mid
        ReActor, and the job hung until it timed out. The unload below is the
        part that actually makes the split work.
        """
        second = _span(report, self._pass_one_share, 1.0)
        second(0.0, "sharpening the face")

        # The first stage's result lives in ComfyUI's *output* folder; a
        # loader reads from *input*, so it has to go back over the wire.
        stage_one = await client.upload_image(data, "fy_stage1.mp4")

        graph = wf.build(
            wf.load(self._polish_workflow_path),
            wf.RenderParams(
                image_name=image_name,
                prompt="",
                template_video=stage_one,
            ),
        )
        # Taking the turn empties the box first, so pass two's weights never
        # land on top of pass one's. This is the boundary that used to kill
        # the server fifteen minutes into a render, with no traceback.
        async with gpu_turn(client, "render pass 2"):
            prompt_id = await client.queue(graph)
            finished, reached = await self._stream_progress(
                client, prompt_id, second,
                pass_label="Pass 2/2 · ",
                node_types=_node_types(graph),
            )
            waiting = (
                None
                if finished
                else self._creep(
                    second, reached, "Pass 2/2 · Sharpening the frames"
                )
            )
            assets = await self._await_outputs(client, prompt_id, on_wait=waiting)
            polished = _pick(assets, prefer)
            return await client.download(polished), polished

    async def _stream_progress(
        self,
        client,
        prompt_id: str,
        report,
        *,
        pass_label: str = "",
        node_types: dict[str, str] | None = None,
    ) -> tuple[bool, float]:
        """Follow progress, but never let the progress stream end the render.

        A face swap reports almost nothing between "node started" and "node
        finished" — it is one node chewing through every frame — so long
        silences are normal and cannot be told apart from a dead socket. Either
        way the right move is the same: stop listening and go ask history. The
        cost of guessing wrong is a progress bar that stops moving; the cost of
        waiting on a dead socket is a render that never returns.

        Returns whether the stream saw the render through to the end, and the
        last sampler fraction it managed to report. Giving up is not the same
        as finishing, and the caller has to be able to tell the two apart —
        treating a dead socket as a completed pass is what used to throw the
        ring to the top of the bar with a quarter of an hour still to run.
        """
        last = 0.0
        iterator = client.watch(prompt_id).__aiter__()
        while True:
            try:
                step = await asyncio.wait_for(
                    iterator.__anext__(), self._progress_idle_timeout_s
                )
            except StopAsyncIteration:
                return True, last
            except (asyncio.TimeoutError, ComfyError, OSError) as exc:
                log.warning(
                    "progress stream for %s gave up (%s) — polling history",
                    prompt_id,
                    exc,
                )
                return False, last
            if step.stage == "sampling":
                # The exact counters ComfyUI prints to its own console. A user
                # watching a 20-minute render wants the real numbers, not a
                # bar that could be stuck.
                kind = (node_types or {}).get(step.node or "") or step.node_type
                percent = round(step.value * 100)
                note = (
                    f"{pass_label}{_phase(kind) or 'Working'}"
                    f" {step.step}/{step.steps} · {percent}%"
                )
                # Only the sampler's count means "the render is this far
                # along". Segmentation and pose report their own bars, and one
                # of them finishing at 1/1 used to slam the ring to its maximum
                # while the actual work had barely started. Those move the
                # detail line and leave the number alone.
                if kind in _SAMPLER_NODES:
                    last = max(last, step.value)
                    report(step.value, note)
                else:
                    report(None, note)
            elif step.stage == "executing":
                # Sampling is only the last third of a Wan render; before it
                # come model loads, segmentation and pose estimation, which
                # report no fraction at all. Naming the running node is what
                # keeps the screen alive across those minutes instead of
                # showing a frozen number.
                kind = (node_types or {}).get(step.node or "") or step.node_type
                phase = _phase(kind)
                if phase:
                    report(None, f"{pass_label}{phase}")

    @property
    def enabled(self) -> bool:
        # Reachability is checked in `health`, not here — a GPU that is
        # temporarily down is a different problem from one never configured.
        return bool(self._base_url)

    async def health(self) -> dict:
        graph_ok, graph_error = True, None
        try:
            missing = wf.validate(wf.load(self._workflow_path))
            if missing:
                graph_ok = False
                graph_error = f"workflow missing markers: {', '.join(missing)}"
        except wf.WorkflowError as exc:
            graph_ok, graph_error = False, str(exc)

        return {
            "comfyReachable": await self._client.health(),
            "comfyUrl": self._base_url,
            "workflow": self._workflow_path.name,
            "workflowValid": graph_ok,
            "workflowError": graph_error,
        }

    async def _build_reference(self, client, *, face_name: str, template) -> str:
        """Swap the customer's face onto the scenario's costume still.

        Returns the name of the uploaded hybrid, or falls back to `face_name`
        if the step is unavailable or fails. Falling back renders the customer
        in their own clothes, which is wrong but watchable; raising here would
        lose a render that is otherwise fine.
        """
        # An approved reference beats a generated one: the generator's output
        # swings between a good head swap and a stranger's face, and the whole
        # render is built on top of whatever it produces.
        if template.hybrid is not None:
            try:
                return await client.upload_image(
                    template.hybrid.read_bytes(), template.hybrid.name
                )
            except (ComfyError, ProviderError, OSError) as exc:
                log.warning("Approved reference unusable (%s) — generating one", exc)

        if self._reference_workflow_path is None:
            return face_name
        try:
            still_name = await client.upload_image(
                template.reference.read_bytes(), template.reference.name
            )
            graph = wf.build(
                wf.load(self._reference_workflow_path),
                # Empty prompt AND empty negative on purpose: this graph's own
                # text is the whole point of it. Its positive replaces the head
                # (hair included) and its negative names what goes wrong --
                # "grey hair", "changed hairstyle", "older man". Unlike Wan,
                # this sampler runs at cfg 4, so that negative is live. Passing
                # the render's generic negative here silently overwrote it and
                # let the still's own grey hair back in.
                wf.RenderParams(image_name=face_name, prompt="",
                                negative="", seed=_REFERENCE_SEED,
                                template_still=still_name),
            )
            async with gpu_turn(client, "costume reference"):
                prompt_id = await client.queue(graph)
                assets = await self._await_outputs(client, prompt_id)
                data = await client.download(_pick(assets, _IMAGE_SUFFIXES))
            # Stable name per scenario so repeat renders overwrite rather than
            # filling the pod's input folder.
            return await client.upload_image(data, f"{template.template_id}.ref.hybrid.png")
        except (ComfyError, wf.WorkflowError, ProviderError) as exc:
            log.warning("Costume reference failed (%s) — using the bare photo", exc)
            return face_name

    async def _run(
        self,
        *,
        prompt: str,
        face: bytes,
        prefer: tuple[str, ...],
        template: "TemplateClip | None" = None,
        on_progress: ProgressHook | None = None,
    ) -> Asset:
        def report(value: float, note: str) -> None:
            if on_progress:
                on_progress(value, note)

        # Its own websocket identity — see ComfyClient.session(). Sharing one
        # across concurrent renders hangs all but the last of them.
        client = self._client.session()

        try:
            image_name = await client.upload_image(face, "face.jpg")

            # Wan Animate treats its reference image as the whole character,
            # clothing included -- hand it a bare selfie and the customer is
            # rendered in the shirt they were photographed in, on the ship.
            # Swapping their face onto the scenario's costume still first is
            # what preserves the coat, the hat and the scene.
            if template is not None and template.reference is not None:
                report(0.0, "Dressing you for the part")
                image_name = await self._build_reference(
                    client, face_name=image_name, template=template
                )

            template_name = None
            if template is not None:
                # ComfyUI reads the driving clip from its own input folder, so
                # the file has to be pushed there before the graph references
                # it. Uploading under the template id keeps the name stable, so
                # repeat renders of the same scenario overwrite rather than
                # filling the pod's disk with copies.
                template_name = await client.upload_image(
                    template.read(), template.filename
                )

            graph = wf.build(
                wf.load(self._workflow_path),
                wf.RenderParams(
                    image_name=image_name,
                    prompt=prompt,
                    seed=self._seed,
                    width=self._width,
                    height=self._height,
                    frames=self._frames,
                    template_video=template_name,
                    points=template.points if template else None,
                ),
            )

            # `gpu_turn` empties the box and holds it for the whole pass.
            # Both halves matter: whatever ran before left its weights loaded
            # -- most often the ReActor preview swaps the app fires the moment
            # the selfie is taken -- and anything arriving during the pass
            # would stack its own on top. Either way Wan's ~28 GB is what
            # pushes the 62 GB container over. See `gpu_guard`.
            two_pass = self._polish_workflow_path is not None
            label = "Pass 1/2 · " if two_pass else ""
            first = _span(
                report, 0.0, self._pass_one_share if two_pass else 1.0
            )

            async with gpu_turn(client, "render pass 1"):
                prompt_id = await client.queue(graph)
                # Zero means "accepted, not sampling yet" — the caller renders
                # that as scene setup rather than as generation progress.
                report(0.0, "queued")

                finished, reached = await self._stream_progress(
                    client, prompt_id, first,
                    pass_label=label,
                    node_types=_node_types(graph),
                )

                if finished:
                    first(1.0, "Collecting the output")
                    waiting = None
                else:
                    # The socket went quiet, not the render. Calling that a
                    # finished pass is what parked the ring at its maximum
                    # with most of the work still ahead of it.
                    waiting = self._creep(
                        first, reached, f"{label}Rendering the frames"
                    )

                assets = await self._await_outputs(
                    client, prompt_id, on_wait=waiting
                )
                chosen = _pick(assets, prefer)
                data = await client.download(chosen)

            if two_pass:
                data, chosen = await self._polish(
                    client, data, chosen, image_name, prefer, report
                )
        except ComfyError as exc:
            raise ProviderError(str(exc)) from exc
        except wf.WorkflowError as exc:
            raise ProviderError(f"Workflow problem: {exc}") from exc

        return Asset(data=data, mime_type=_mime_for(chosen.filename))


class ComfyVideoProvider(_ComfyProvider, VideoProvider):
    name = "comfy"

    @property
    def requires_template(self) -> bool:
        """A graph with FY_TEMPLATE_VIDEO is a character swap, and cannot run
        without a clip to swap into. Read from the workflow rather than
        configured separately, so swapping the graph cannot leave a stale flag
        behind."""
        try:
            graph = wf.load(self._workflow_path)
        except wf.WorkflowError:
            return False
        return wf.find_by_title(graph, wf.MARKER_TEMPLATE_VIDEO) is not None

    @property
    def requires_points(self) -> bool:
        """Whether this graph aims at a subject using click points.

        Wan Animate does; a plain face swap does not. Read from the workflow
        so swapping the graph cannot leave a stale flag behind.
        """
        try:
            graph = wf.load(self._workflow_path)
        except wf.WorkflowError:
            return False
        return wf.find_points_node(graph) is not None

    async def generate_video(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template: "TemplateClip | None" = None,
        on_progress: ProgressHook | None = None,
    ) -> Asset:
        return await self._run(
            prompt=prompt,
            face=face,
            prefer=_VIDEO_SUFFIXES,
            template=template,
            on_progress=on_progress,
        )


class ComfyImageProvider(_ComfyProvider, ImageProvider):
    """Style previews on your own GPU, with no free-tier ceiling.

    Uses an img2img graph — the user's photo is encoded to a latent and
    re-sampled at partial denoise, so the pose and framing survive while the
    scenario prompt repaints everything around them.
    """

    name = "comfy"

    async def generate_image(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template_id: str | None = None,
    ) -> Asset:
        return await self._run(prompt=prompt, face=face, prefer=_IMAGE_SUFFIXES)


class ComfyFaceSwapProvider(_ComfyProvider, ImageProvider):
    """Previews by face swap: the scenario's own artwork, with the customer's
    face pasted in.

    The alternative — generating a whole new image from the prompt — costs a
    full diffusion run, drifts away from the artwork the user just tapped, and
    on this audience regularly comes back as somebody else entirely. Swapping
    keeps costume, lighting, framing and background exactly as authored and
    changes only the face, which is the one thing the customer is looking for.

    ~20s per preview on an RTX PRO 4500, against minutes for a Wan render.
    """

    name = "comfy_swap"

    # ComfyUI saves PNG, which comes back at 1.2-1.7 MB per preview. Five of
    # those is a 7 MB response for five phone-sized tiles. Re-encoding to JPEG
    # at tile resolution cuts it to roughly a tenth with no visible loss at the
    # size these are ever displayed.
    _MAX_EDGE = (900, 1200)
    _JPEG_QUALITY = 86

    # A preview is ~20s of work; anything past four minutes is a fault, not
    # a slow queue, and the caller should hear about it while the user is
    # still looking at the screen.
    _poll_timeout_s = 240.0

    def __init__(self, *, still_dir: str, **kwargs) -> None:
        super().__init__(**kwargs)
        self._stills = StillLibrary(still_dir)

    async def health(self) -> dict:
        base = await super().health()
        return base | {
            "stillDir": str(self._stills.directory),
            "stillsInstalled": len(self._stills.available()),
        }

    async def generate_image(
        self,
        *,
        prompt: str,
        face: bytes,
        face_mime: str = "image/jpeg",
        template_id: str | None = None,
    ) -> Asset:
        still = self._stills.get(template_id)
        if still is None:
            # Not retryable: no amount of waiting puts the file on disk.
            raise ProviderError(self._stills.missing_reason(template_id))

        client = self._client.session()
        try:
            face_name = await client.upload_image(face, "fy_face.jpg")
            # Named after the scenario so repeat previews overwrite rather than
            # filling the pod's input folder with copies of the same artwork.
            still_name = await client.upload_image(still.read(), still.filename)

            graph = wf.build(
                wf.load(self._workflow_path),
                wf.RenderParams(
                    image_name=face_name,
                    prompt=prompt,
                    template_still=still_name,
                ),
            )

            # Previews queue behind a render rather than beside it. They are
            # small, but ReActor still holds GFPGAN, inswapper and the NSFW
            # detector, and that is exactly what used to be resident when a
            # render arrived and pushed the box past its limit.
            async with gpu_turn(client, "preview swap"):
                prompt_id = await client.queue(graph)
                assets = await self._await_outputs(client, prompt_id)
                chosen = _pick(assets, _IMAGE_SUFFIXES)
                data = await client.download(chosen)
        except ComfyError as exc:
            raise ProviderError(str(exc)) from exc
        except wf.WorkflowError as exc:
            raise ProviderError(f"Workflow problem: {exc}") from exc

        return Asset(data=self._to_tile_jpeg(data), mime_type="image/jpeg")

    @classmethod
    def _to_tile_jpeg(cls, data: bytes) -> bytes:
        """Shrink to tile size and re-encode. Falls back to the original bytes
        if Pillow is unavailable — a heavy preview beats no preview."""
        try:
            from PIL import Image
        except ImportError:  # pragma: no cover - Pillow is in requirements
            log.warning("Pillow missing — returning the raw PNG preview")
            return data

        with Image.open(io.BytesIO(data)) as image:
            image = image.convert("RGB")
            image.thumbnail(cls._MAX_EDGE, Image.LANCZOS)
            buffer = io.BytesIO()
            image.save(
                buffer,
                "JPEG",
                quality=cls._JPEG_QUALITY,
                optimize=True,
                progressive=True,
            )
        return buffer.getvalue()
