"""Funny You render API.

    POST /v1/renders              start a video render      -> job
    GET  /v1/renders/{id}         poll progress             -> job
    DELETE /v1/renders/{id}       cancel
    GET  /v1/videos/{file}        download the finished mp4
    POST /v1/previews             free Gemini style stills
    GET  /v1/health               readiness + config check
"""

from __future__ import annotations

import json
import logging
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse

from .config import Settings, get_settings
from .jobs import JobStore
from .preview_service import PreviewError, PreviewService
from .providers import build_image_provider
from .render_service import RenderService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
)
log = logging.getLogger("funnyyou")

settings = get_settings()
store = JobStore()
renders = RenderService(settings, store)
previews = PreviewService(build_image_provider(settings))

log.info(
    # Plain ASCII: this goes to a console, and Windows defaults to cp1252.
    "Providers - previews: %s%s, video: %s",
    previews.provider_name,
    "" if previews.enabled else f" (disabled: {previews.disabled_reason})",
    renders.provider_name,
)

app = FastAPI(title="Funny You API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def require_key(authorization: str | None = Header(default=None)) -> None:
    """Bearer-token gate. Disabled when API_KEY is unset (local dev)."""
    if not settings.api_key:
        return
    expected = f"Bearer {settings.api_key}"
    if authorization != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")


async def _read_upload(file: UploadFile) -> bytes:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="Empty image upload")
    if len(data) > settings.max_upload_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"Image exceeds {settings.max_upload_bytes // (1024 * 1024)} MB",
        )
    return data


@app.get("/v1/health")
async def health() -> JSONResponse:
    detail = await renders.health()
    detail["previewProvider"] = previews.provider_name
    detail["previewsEnabled"] = previews.enabled
    detail["previewError"] = previews.disabled_reason
    detail["authRequired"] = bool(settings.api_key)

    # Ready means the paid path works. Previews are a nice-to-have: without
    # them the app falls back to designed artwork and still sells videos.
    ready = bool(detail.get("videoEnabled")) and bool(
        detail.get("comfyReachable", True)
    ) and bool(detail.get("workflowValid", True))

    return JSONResponse(
        {"ready": ready, **detail},
        status_code=200 if ready else 503,
    )


@app.post("/v1/renders", dependencies=[Depends(require_key)])
async def create_render(
    image: UploadFile = File(...),
    prompt: str = Form(...),
    template_id: str | None = Form(default=None),
) -> JSONResponse:
    if not prompt.strip():
        raise HTTPException(status_code=400, detail="prompt must not be empty")

    job = renders.start(
        face_image=await _read_upload(image),
        prompt=prompt.strip(),
        template_id=template_id,
    )
    return JSONResponse(job.to_json(), status_code=202)


@app.get("/v1/renders/{job_id}", dependencies=[Depends(require_key)])
async def get_render(job_id: str) -> JSONResponse:
    job = store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Unknown job")
    return JSONResponse(job.to_json())


@app.delete("/v1/renders/{job_id}", dependencies=[Depends(require_key)])
async def cancel_render(job_id: str) -> JSONResponse:
    if not await store.cancel(job_id):
        raise HTTPException(status_code=404, detail="Unknown or finished job")
    return JSONResponse({"cancelled": True})


@app.get("/v1/videos/{filename}")
async def get_video(filename: str) -> FileResponse:
    # Resolve and confirm containment — never trust a path segment.
    root = Path(settings.output_dir).resolve()
    path = (root / filename).resolve()
    if not str(path).startswith(str(root)) or not path.is_file():
        raise HTTPException(status_code=404, detail="Video not found")
    return FileResponse(path, media_type="video/mp4", filename=path.name)


@app.post("/v1/previews", dependencies=[Depends(require_key)])
async def create_previews(
    image: UploadFile = File(...),
    scenarios: str = Form(...),
) -> JSONResponse:
    """Generate free style stills.

    `scenarios` is a JSON object of {templateId: prompt}. Returns base64 images
    plus a per-template error map — partial success is expected on a free tier.
    """
    if not previews.enabled:
        raise HTTPException(
            status_code=503,
            detail=previews.disabled_reason or "Previews are disabled",
        )

    try:
        parsed = json.loads(scenarios)
        if not isinstance(parsed, dict) or not parsed:
            raise ValueError("expected a non-empty object")
    except ValueError as exc:
        raise HTTPException(
            status_code=400, detail=f"scenarios must be a JSON object: {exc}"
        ) from exc

    if len(parsed) > 40:
        raise HTTPException(status_code=400, detail="At most 40 scenarios per request")

    import base64

    try:
        results, errors = await previews.generate_batch(
            face_image=await _read_upload(image),
            scenarios={str(k): str(v) for k, v in parsed.items()},
        )
    except PreviewError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc

    return JSONResponse(
        {
            "previews": [
                {
                    "templateId": p.template_id,
                    "mimeType": p.mime_type,
                    "imageBase64": base64.b64encode(p.image).decode(),
                }
                for p in results
            ],
            "errors": errors,
        }
    )
