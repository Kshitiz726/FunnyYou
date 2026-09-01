"""In-process job registry.

Deliberately not Redis: a ComfyUI box renders one video at a time, so a dict
plus an asyncio task is the honest amount of machinery. Swap for Redis only if
you put more than one worker behind a load balancer.
"""

from __future__ import annotations

import asyncio
import time
import uuid
from dataclasses import dataclass, field
from enum import Enum


class JobStatus(str, Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Stage(str, Enum):
    """Mirrors GenerationStage in the Flutter app, one for one."""

    UPLOADING = "uploading"
    MATCHING_FACE = "matchingFace"
    BUILDING_SCENE = "buildingScene"
    RENDERING = "rendering"
    FINISHING = "finishing"
    DONE = "done"


@dataclass
class Job:
    id: str
    template_id: str | None
    prompt: str
    status: JobStatus = JobStatus.QUEUED
    stage: Stage = Stage.UPLOADING
    progress: float = 0.0
    detail: str | None = None
    """The exact phase the renderer is in, e.g. "Pass 1/2 - Rendering 3/8 - 37%"."""
    video_url: str | None = None
    error: str | None = None
    created_at: float = field(default_factory=time.time)
    updated_at: float = field(default_factory=time.time)
    task: asyncio.Task | None = field(default=None, repr=False)

    @property
    def eta_seconds(self) -> int | None:
        """Straight-line estimate from elapsed time and progress."""
        if self.progress <= 0.01 or self.status != JobStatus.RUNNING:
            return None
        elapsed = time.time() - self.created_at
        return max(int(elapsed / self.progress - elapsed), 0)

    def to_json(self) -> dict:
        return {
            "id": self.id,
            "status": self.status.value,
            "stage": self.stage.value,
            "progress": round(self.progress, 4),
            "detail": self.detail,
            "videoUrl": self.video_url,
            "error": self.error,
            "etaSeconds": self.eta_seconds,
            "templateId": self.template_id,
        }


class JobStore:
    def __init__(self, max_age_s: int = 3600) -> None:
        self._jobs: dict[str, Job] = {}
        self._max_age = max_age_s

    def create(self, *, template_id: str | None, prompt: str) -> Job:
        self._evict_stale()
        job = Job(id=uuid.uuid4().hex, template_id=template_id, prompt=prompt)
        self._jobs[job.id] = job
        return job

    def get(self, job_id: str) -> Job | None:
        return self._jobs.get(job_id)

    def update(
        self,
        job_id: str,
        *,
        status: JobStatus | None = None,
        stage: Stage | None = None,
        progress: float | None = None,
        detail: str | None = None,
        video_url: str | None = None,
        error: str | None = None,
    ) -> Job | None:
        job = self._jobs.get(job_id)
        if job is None:
            return None

        if status is not None:
            job.status = status
        if stage is not None:
            job.stage = stage
        if progress is not None:
            # Never let progress go backwards — it looks broken to the user.
            job.progress = max(job.progress, min(progress, 1.0))
        if detail is not None:
            job.detail = detail
        if video_url is not None:
            job.video_url = video_url
        if error is not None:
            job.error = error
        job.updated_at = time.time()
        return job

    async def cancel(self, job_id: str) -> bool:
        job = self._jobs.get(job_id)
        if job is None or job.status in {JobStatus.COMPLETED, JobStatus.FAILED}:
            return False
        if job.task and not job.task.done():
            job.task.cancel()
        job.status = JobStatus.CANCELLED
        job.updated_at = time.time()
        return True

    def _evict_stale(self) -> None:
        cutoff = time.time() - self._max_age
        for job_id in [j.id for j in self._jobs.values() if j.updated_at < cutoff]:
            self._jobs.pop(job_id, None)
