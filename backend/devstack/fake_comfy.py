"""A stand-in for a running ComfyUI instance.

Implements the five endpoints `app/comfy_client.py` actually uses, with the
same shapes and the same websocket message sequence the real server emits:

    GET  /system_stats        health
    POST /upload/image        {"name", "subfolder", "type"}
    POST /prompt              {"prompt_id"}  or 400 with {"error": {...}}
    WS   /ws?clientId=...     executing / progress / executed / executing(null)
    GET  /history/{id}        {"<id>": {"outputs": {...}}}
    GET  /view?filename=...   the bytes

It is not a renderer. It validates the graph it is handed and then produces a
real, playable H.264 clip from the uploaded face, so everything downstream of
the model — progress blending, polling, download, playback, gallery save — is
exercised for real.

Because it type-checks the graph the way ComfyUI does, it catches genuine
workflow-binding mistakes: an unuploaded image name, a dangling node reference,
or a missing FY_ marker all fail here exactly as they would on a GPU.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from dataclasses import dataclass, field
from typing import Any

from fastapi import FastAPI, File, Form, HTTPException, UploadFile, WebSocket
from fastapi.responses import JSONResponse, Response

from .media import render_mp4, scenario_label

app = FastAPI(title="Fake ComfyUI")

# Seconds of simulated sampling. Long enough to watch the app's progress ring
# and stage checklist behave; a real 5s Wan clip takes 3-8 minutes.
SAMPLE_SECONDS = 12.0
SAMPLE_STEPS = 20

_uploads: dict[str, bytes] = {}
_outputs: dict[str, bytes] = {}


@dataclass
class _Job:
    prompt_id: str
    graph: dict[str, Any]
    client_id: str
    history: dict[str, Any] = field(default_factory=dict)
    done: asyncio.Event = field(default_factory=asyncio.Event)


_queue: dict[str, list[_Job]] = {}
_jobs: dict[str, _Job] = {}


def _titled(graph: dict[str, Any], title: str) -> tuple[str, dict] | None:
    for node_id, node in graph.items():
        if node.get("_meta", {}).get("title") == title:
            return node_id, node
    return None


def _validate(graph: dict[str, Any]) -> None:
    """Reject the same graphs the real server would, with the same error shape."""
    if not isinstance(graph, dict) or not graph:
        raise HTTPException(400, detail={"error": {"message": "empty prompt"}})

    for node_id, node in graph.items():
        if "class_type" not in node:
            raise HTTPException(
                400,
                detail={
                    "error": {
                        "type": "invalid_prompt",
                        "message": f"Node {node_id} has no class_type",
                    }
                },
            )
        for key, value in node.get("inputs", {}).items():
            # A wired input is [source_node_id, slot]; the source must exist.
            if (
                isinstance(value, list)
                and len(value) == 2
                and isinstance(value[0], str)
                and value[0] not in graph
            ):
                raise HTTPException(
                    400,
                    detail={
                        "error": {
                            "type": "prompt_outputs_failed_validation",
                            "message": (
                                f"Node {node_id}.{key} references missing "
                                f"node {value[0]}"
                            ),
                        }
                    },
                )

    found = _titled(graph, "FY_INPUT_IMAGE")
    if found is None:
        raise HTTPException(
            400,
            detail={"error": {"message": "No node titled FY_INPUT_IMAGE"}},
        )

    name = found[1].get("inputs", {}).get("image")
    if isinstance(name, str) and name not in _uploads:
        raise HTTPException(
            400,
            detail={
                "error": {
                    "type": "value_not_in_list",
                    "message": (
                        f"Value not in list: image: '{name}' not in "
                        f"{sorted(_uploads)[:5]}"
                    ),
                }
            },
        )


def _label(graph: dict[str, Any]) -> str:
    found = _titled(graph, "FY_POSITIVE")
    text = (found[1].get("inputs", {}).get("text") if found else "") or "Scenario"
    return scenario_label(str(text))


def _literal(value: Any, fallback: int) -> int:
    """Read a widget value, tolerating one that is wired instead.

    Production graphs routinely drive geometry from other nodes — the
    character-swap workflow takes width/height/length from the template clip
    via PrimitiveInt nodes — so these inputs arrive as `[node_id, slot]` rather
    than numbers. The fake cannot evaluate a link, and guessing is fine here:
    it only decides the size of a stand-in clip.
    """
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        return fallback
    try:
        return int(value) or fallback
    except (TypeError, ValueError):
        return fallback


def _dimensions(graph: dict[str, Any]) -> tuple[int, int, int]:
    found = _titled(graph, "FY_LATENT")
    inputs = found[1].get("inputs", {}) if found else {}
    width = _literal(inputs.get("width"), 480)
    height = _literal(inputs.get("height"), 832)
    frames = _literal(inputs.get("length", inputs.get("batch_size")), 81)
    return width, height, frames


@app.get("/system_stats")
async def system_stats() -> dict:
    return {
        "system": {"comfyui_version": "fake-devstack", "os": "posix"},
        "devices": [{"name": "fake", "type": "cuda", "vram_total": 25_769_803_776}],
    }


@app.post("/upload/image")
async def upload_image(
    image: UploadFile = File(...),
    overwrite: str = Form(default="false"),
    type: str = Form(default="input"),
) -> dict:
    data = await image.read()
    if not data:
        raise HTTPException(400, detail="empty upload")
    name = image.filename or f"{uuid.uuid4()}.jpg"
    _uploads[name] = data
    return {"name": name, "subfolder": "", "type": type}


@app.post("/prompt")
async def prompt(payload: dict) -> JSONResponse:
    graph = payload.get("prompt") or {}
    _validate(graph)

    job = _Job(
        prompt_id=str(uuid.uuid4()),
        graph=graph,
        client_id=payload.get("client_id", ""),
    )
    _jobs[job.prompt_id] = job
    _queue.setdefault(job.client_id, []).append(job)

    return JSONResponse({"prompt_id": job.prompt_id, "number": len(_jobs)})


@app.websocket("/ws")
async def websocket(socket: WebSocket) -> None:
    client_id = socket.query_params.get("clientId", "")
    await socket.accept()
    await socket.send_text(
        json.dumps({"type": "status", "data": {"status": {"exec_info": {}}}})
    )

    # The client never sends anything, so a completed receive means it hung up.
    # Without watching for that, the idle loop below would keep this handler
    # alive forever and block the server from ever shutting down.
    hangup = asyncio.create_task(socket.receive())

    try:
        while not hangup.done():
            pending = _queue.get(client_id) or []
            if not pending:
                # The client connects right after queueing; if we got here
                # first, wait rather than closing the socket.
                await asyncio.sleep(0.05)
                continue
            await _execute(socket, pending.pop(0))
    except Exception:  # noqa: BLE001 — client hung up mid-send, which is normal
        pass
    finally:
        hangup.cancel()


async def _execute(socket: WebSocket, job: _Job) -> None:
    async def send(kind: str, data: dict) -> None:
        await socket.send_text(
            json.dumps({"type": kind, "data": {"prompt_id": job.prompt_id, **data}})
        )

    sampler = _titled(job.graph, "FY_SAMPLER")
    sampler_id = sampler[0] if sampler else next(iter(job.graph))

    for node_id in list(job.graph)[:3]:
        await send("executing", {"node": node_id})
        await asyncio.sleep(0.15)

    await send("executing", {"node": sampler_id})
    for step in range(1, SAMPLE_STEPS + 1):
        await asyncio.sleep(SAMPLE_SECONDS / SAMPLE_STEPS)
        await send(
            "progress", {"value": step, "max": SAMPLE_STEPS, "node": sampler_id}
        )

    width, height, frames = _dimensions(job.graph)
    video = await asyncio.to_thread(
        render_mp4,
        _uploads[
            _titled(job.graph, "FY_INPUT_IMAGE")[1]["inputs"]["image"]
        ],
        _label(job.graph),
        width=width,
        height=height,
        frames=min(frames, 81),
    )

    filename = f"FunnyYou_{job.prompt_id[:8]}.mp4"
    _outputs[filename] = video

    output_node = _titled(job.graph, "FY_OUTPUT")
    output_id = output_node[0] if output_node else sampler_id
    entry = {"filename": filename, "subfolder": "", "type": "output", "format": "video/h264-mp4"}

    job.history = {"outputs": {output_id: {"gifs": [entry]}}, "status": {"completed": True}}
    await send("executed", {"node": output_id, "output": {"gifs": [entry]}})

    # A null node is how ComfyUI signals "this prompt is finished".
    await send("executing", {"node": None})
    job.done.set()


@app.get("/history/{prompt_id}")
async def history(prompt_id: str) -> dict:
    job = _jobs.get(prompt_id)
    if job is None or not job.history:
        return {}
    return {prompt_id: job.history}


@app.get("/view")
async def view(filename: str, subfolder: str = "", type: str = "output") -> Response:
    data = _outputs.get(filename)
    if data is None:
        raise HTTPException(404, detail="not found")
    return Response(content=data, media_type="video/mp4")
