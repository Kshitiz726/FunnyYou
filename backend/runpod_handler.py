"""RunPod Serverless entry point.

Serverless is the right shape for this workload: an idle GPU costs nothing and
you only pay for the ~3-8 minutes a clip actually takes.

Unlike the FastAPI service this handler is synchronous from the caller's point
of view — RunPod owns the queue and gives you /run (async) and /runsync. The
app polls RunPod's own /status/{id} endpoint, so there is no job store here.

Input:
    {
      "input": {
        "image_base64": "...",          # the user's face, required
        "prompt": "the person as a ...", # required
        "template_id": "superhero",
        "width": 480, "height": 832, "frames": 81, "seed": 12345
      }
    }

Output:
    {"video_base64": "...", "mime_type": "video/mp4", "template_id": "..."}
"""

from __future__ import annotations

import asyncio
import base64
import logging
import os
import subprocess
import sys
import time
from pathlib import Path

import runpod

sys.path.insert(0, str(Path(__file__).parent))

from app.comfy_client import ComfyClient, ComfyError  # noqa: E402
from app import workflow as wf  # noqa: E402

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("handler")

COMFY_URL = os.getenv("COMFY_URL", "http://127.0.0.1:8188")
COMFY_DIR = os.getenv("COMFY_DIR", "/workspace/ComfyUI")
WORKFLOW = Path(__file__).parent / "workflows" / os.getenv(
    "COMFY_WORKFLOW", "wan22_animate.json"
)
BOOT_TIMEOUT_S = int(os.getenv("COMFY_BOOT_TIMEOUT_S", "600"))

_comfy = ComfyClient(COMFY_URL, timeout_s=int(os.getenv("COMFY_TIMEOUT_S", "1800")))
_comfy_process: subprocess.Popen | None = None


def _ensure_comfy_running() -> None:
    """Start ComfyUI inside the worker if it is not already up.

    Cold starts dominate serverless cost, so the container should bake the
    models into the image (or mount a network volume) — see DEPLOYMENT.md.
    """
    global _comfy_process

    if _comfy_process is not None and _comfy_process.poll() is None:
        return

    main_py = Path(COMFY_DIR) / "main.py"
    if not main_py.is_file():
        raise RuntimeError(f"ComfyUI not found at {COMFY_DIR}")

    log.info("Starting ComfyUI from %s", COMFY_DIR)
    _comfy_process = subprocess.Popen(
        [sys.executable, "main.py", "--listen", "127.0.0.1", "--port", "8188"],
        cwd=COMFY_DIR,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )


async def _wait_for_comfy() -> None:
    deadline = time.time() + BOOT_TIMEOUT_S
    while time.time() < deadline:
        if await _comfy.health():
            return
        if _comfy_process is not None and _comfy_process.poll() is not None:
            raise RuntimeError("ComfyUI exited during start-up — check worker logs")
        await asyncio.sleep(2)
    raise RuntimeError(f"ComfyUI did not become ready within {BOOT_TIMEOUT_S}s")


async def _render(payload: dict) -> dict:
    image_b64 = payload.get("image_base64")
    prompt = (payload.get("prompt") or "").strip()

    if not image_b64:
        raise ValueError("image_base64 is required")
    if not prompt:
        raise ValueError("prompt is required")

    try:
        face = base64.b64decode(image_b64)
    except Exception as exc:  # noqa: BLE001
        raise ValueError(f"image_base64 is not valid base64: {exc}") from exc

    _ensure_comfy_running()
    await _wait_for_comfy()

    image_name = await _comfy.upload_image(face, "face.jpg")

    graph = wf.build(
        wf.load(WORKFLOW),
        wf.RenderParams(
            image_name=image_name,
            prompt=prompt,
            seed=payload.get("seed"),
            width=payload.get("width", 480),
            height=payload.get("height", 832),
            frames=payload.get("frames", 81),
        ),
    )

    prompt_id = await _comfy.queue(graph)

    # RunPod surfaces whatever we yield through /status, so progress is visible
    # to the app while the clip renders.
    async for step in _comfy.watch(prompt_id):
        if step.stage == "sampling":
            runpod.serverless.progress_update(
                {"progress": round(step.value, 3), "stage": "rendering"}
            )

    assets = await _comfy.outputs(prompt_id)
    video = next(
        (a for a in assets if a.filename.lower().endswith((".mp4", ".webm"))),
        assets[0],
    )
    data = await _comfy.download(video)

    log.info("Rendered %s (%d bytes)", video.filename, len(data))
    return {
        "video_base64": base64.b64encode(data).decode(),
        "mime_type": "video/mp4" if video.filename.endswith(".mp4") else "video/webm",
        "template_id": payload.get("template_id"),
        "filename": video.filename,
    }


def handler(event: dict) -> dict:
    payload = event.get("input") or {}
    try:
        return asyncio.run(_render(payload))
    except (ValueError, wf.WorkflowError) as exc:
        return {"error": str(exc), "retryable": False}
    except (ComfyError, RuntimeError) as exc:
        return {"error": str(exc), "retryable": True}


runpod.serverless.start({"handler": handler})
