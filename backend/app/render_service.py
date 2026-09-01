"""Drives one render from face photo to a finished file on disk.

Vendor-agnostic: the actual generation happens in a `VideoProvider`. This file
owns the parts that stay the same whoever renders — job bookkeeping, turning
whatever progress the provider offers into the five stages the app draws, and
writing the result somewhere the phone can fetch it.
"""

from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from .config import Settings
from .jobs import Job, JobStatus, JobStore, Stage
from .providers import ProviderError, VideoProvider, build_video_provider
from .template_library import TemplateLibrary

log = logging.getLogger(__name__)

# Providers report generation progress only — the long pole, but not the whole
# job. These weights turn "generating at 40%" into a believable overall number
# that matches the five stages the app draws.
_STAGE_SPAN = {
    Stage.UPLOADING: (0.00, 0.08),
    Stage.MATCHING_FACE: (0.08, 0.20),
    Stage.BUILDING_SCENE: (0.20, 0.32),
    Stage.RENDERING: (0.32, 0.90),
    Stage.FINISHING: (0.90, 0.99),
}


def _blend(stage: Stage, fraction: float) -> float:
    low, high = _STAGE_SPAN[stage]
    return low + (high - low) * min(max(fraction, 0.0), 1.0)


class RenderService:
    def __init__(
        self,
        settings: Settings,
        store: JobStore,
        provider: VideoProvider | None = None,
    ) -> None:
        self._settings = settings
        self._store = store
        self._output_dir = Path(settings.output_dir)
        self._output_dir.mkdir(parents=True, exist_ok=True)

        self._provider = provider or build_video_provider(
            settings, workflow_dir=Path(__file__).parent.parent / "workflows"
        )
        self._templates = TemplateLibrary(settings.template_dir)

    @property
    def provider_name(self) -> str:
        return self._provider.name

    async def health(self) -> dict:
        detail: dict = {
            "videoProvider": self._provider.name,
            "videoEnabled": self._provider.enabled,
            "videoError": self._provider.disabled_reason,
        }

        # ComfyUI can say more than "configured" — it knows whether the GPU is
        # up and whether the workflow on disk is bindable.
        probe = getattr(self._provider, "health", None)
        if probe is not None:
            detail.update(await probe())
        else:
            # Keep the shape stable for clients that read these two keys.
            detail.setdefault("comfyReachable", self._provider.enabled)
            detail.setdefault("workflowValid", True)

        # Which scenarios can actually be rendered right now. A character swap
        # needs a template clip, and the clips arrive one at a time — without
        # this the app shows forty tiles and spends a credit discovering that
        # thirty-nine of them have nothing to swap into.
        # A Wan Animate graph also needs per-clip click points, so a clip
        # sitting on disk without its sidecar is not yet renderable — better
        # the tile stays marked "Soon" than the render aims at the wrong
        # person and charges for it.
        detail["renderableTemplates"] = (
            self._templates.available(
                require_points=self._provider.requires_points
            )
            if self._provider.requires_template
            else []
        )
        detail["requiresTemplate"] = self._provider.requires_template

        return detail

    def start(self, *, face_image: bytes, prompt: str, template_id: str | None) -> Job:
        job = self._store.create(template_id=template_id, prompt=prompt)
        job.task = asyncio.create_task(
            self._run(job.id, face_image, prompt, template_id)
        )
        return job

    async def _run(
        self, job_id: str, face_image: bytes, prompt: str, template_id: str | None
    ) -> None:
        try:
            await self._render(job_id, face_image, prompt, template_id)
        except asyncio.CancelledError:
            self._store.update(job_id, status=JobStatus.CANCELLED)
            raise
        except ProviderError as exc:
            log.error("Render %s failed: %s", job_id, exc)
            self._store.update(job_id, status=JobStatus.FAILED, error=str(exc))
        except Exception as exc:  # noqa: BLE001 — never let a job hang forever
            log.exception("Render %s crashed", job_id)
            self._store.update(
                job_id, status=JobStatus.FAILED, error=f"Unexpected error: {exc}"
            )

    async def _render(
        self, job_id: str, face_image: bytes, prompt: str, template_id: str | None
    ) -> None:
        if not self._provider.enabled:
            raise ProviderError(
                self._provider.disabled_reason or "no video provider is configured"
            )

        # Character-swap workflows render *into* a pre-made clip, so a missing
        # template is a hard failure — and one worth catching before uploading
        # anything or spending a second of GPU time.
        template = self._templates.get(template_id)
        if template is None and self._provider.requires_template:
            raise ProviderError(self._templates.missing_reason(template_id))

        # Same reasoning one step further in: the clip exists but nobody has
        # marked which person in it to replace.
        if (
            template is not None
            and self._provider.requires_points
            and template.points is None
        ):
            raise ProviderError(self._templates.missing_reason(template_id))

        self._store.update(
            job_id,
            status=JobStatus.RUNNING,
            stage=Stage.UPLOADING,
            progress=_blend(Stage.UPLOADING, 0.2),
        )

        def on_progress(value: float | None, note: str) -> None:
            # A `None` value means the renderer named its current phase without
            # having a fraction to report — the minutes of model loading and
            # segmentation before sampling starts. The number stays where it
            # is and only the detail line moves, which is the honest way to
            # show "still working" without inventing progress.
            if value is None:
                self._store.update(job_id, detail=note)
                return
            if value <= 0.0:
                self._store.update(
                    job_id,
                    stage=Stage.BUILDING_SCENE,
                    progress=_blend(Stage.BUILDING_SCENE, 0.5),
                    detail=note,
                )
                return
            self._store.update(
                job_id,
                stage=Stage.RENDERING,
                progress=_blend(Stage.RENDERING, value),
                detail=note,
            )
            log.debug("Render %s: %.0f%% (%s)", job_id, value * 100, note)

        self._store.update(
            job_id,
            stage=Stage.MATCHING_FACE,
            progress=_blend(Stage.MATCHING_FACE, 0.5),
        )

        asset = await self._provider.generate_video(
            prompt=prompt,
            face=face_image,
            template=template,
            on_progress=on_progress,
        )

        self._store.update(
            job_id, stage=Stage.FINISHING, progress=_blend(Stage.FINISHING, 0.4)
        )

        destination = self._output_dir / f"{job_id}{asset.extension}"
        destination.write_bytes(asset.data)

        self._store.update(
            job_id,
            status=JobStatus.COMPLETED,
            stage=Stage.DONE,
            progress=1.0,
            video_url=(
                f"{self._settings.public_base_url.rstrip('/')}"
                f"/v1/videos/{destination.name}"
            ),
        )
        log.info(
            "Render %s complete via %s: %s (%d bytes)",
            job_id,
            self._provider.name,
            destination.name,
            len(asset.data),
        )
