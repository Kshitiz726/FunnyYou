"""Async client for a running ComfyUI instance.

ComfyUI has no official SDK. This wraps the four HTTP endpoints and the
websocket that the web UI itself uses:

    POST /upload/image      push the user's face in
    POST /prompt            queue a workflow, get a prompt_id
    WS   /ws?clientId=...   live progress
    GET  /history/{id}      find the rendered file
    GET  /view?filename=... download it
"""

from __future__ import annotations

import asyncio
import json
import logging
import uuid
from dataclasses import dataclass
from typing import Any, AsyncIterator

import httpx
import websockets

log = logging.getLogger(__name__)

# ComfyUI nodes report finished media under one of these output keys,
# depending on which save node the workflow uses.
_MEDIA_KEYS = ("gifs", "videos", "images")


class ComfyError(RuntimeError):
    """ComfyUI rejected the workflow or died mid-render."""


class ComfyRenderFailed(ComfyError):
    """The render reached a terminal failure — retrying cannot help.

    Separated from ComfyError because callers poll history to find out when a
    render finished, and "not there yet" and "it failed" both arrive as an
    absence of outputs. Without this distinction a failed render is
    indistinguishable from a slow one and gets waited on until the timeout.
    """


@dataclass(frozen=True)
class ComfyProgress:
    """A step of the render, normalised to 0..1.

    `step`/`steps` are the raw counters ComfyUI puts on the wire — the same
    numbers its console prints as `3/8`. They are kept alongside the ratio
    because "3 of 8" tells a waiting user something the ratio alone does not:
    how many units are left, and therefore whether the wait is nearly over.
    """

    value: float
    node: str | None = None
    stage: str | None = None
    step: int | None = None
    steps: int | None = None
    node_type: str | None = None


@dataclass(frozen=True)
class ComfyAsset:
    filename: str
    subfolder: str
    type: str


class ComfyClient:
    def __init__(self, base_url: str, timeout_s: int = 1800) -> None:
        self._base = base_url.rstrip("/")
        self._timeout = timeout_s
        self._client_id = str(uuid.uuid4())
        # ComfyUI's websocket names the running node by id only. Remembering
        # the graph we queued is what lets progress say "Sam2Segmentation"
        # instead of "node 365".
        self._node_types: dict[str, str] = {}

    def session(self) -> "ComfyClient":
        """A clone of this client with its own websocket identity.

        ComfyUI keys its socket registry by `clientId` and *overwrites* the
        entry when a second socket connects with the same one, so two renders
        sharing a client starve the first: every progress frame and the final
        `node: null` go to the newer socket, and the older `watch()` waits for
        a completion that never arrives until it times out.

        Previews are generated six at a time, so concurrency here is the normal
        case rather than an edge case — every render takes its own session.
        """
        return ComfyClient(self._base, self._timeout)

    @property
    def _ws_url(self) -> str:
        scheme = "wss" if self._base.startswith("https") else "ws"
        host = self._base.split("://", 1)[1]
        return f"{scheme}://{host}/ws?clientId={self._client_id}"

    async def health(self) -> bool:
        try:
            async with httpx.AsyncClient(timeout=10) as http:
                response = await http.get(f"{self._base}/system_stats")
                return response.status_code == 200
        except (httpx.HTTPError, OSError):
            return False

    async def upload_image(self, data: bytes, filename: str) -> str:
        """Push an image into ComfyUI's input folder. Returns its input name."""
        try:
            async with httpx.AsyncClient(timeout=120) as http:
                response = await http.post(
                    f"{self._base}/upload/image",
                    files={"image": (filename, data, "image/jpeg")},
                    data={"overwrite": "true", "type": "input"},
                )
        except httpx.HTTPError as exc:
            raise ComfyError(f"Could not upload {filename}: {exc!r}") from exc
        if response.status_code != 200:
            raise ComfyError(f"Upload failed ({response.status_code}): {response.text}")

        payload = response.json()
        name = payload.get("name")
        if not name:
            raise ComfyError(f"Upload returned no filename: {payload}")

        subfolder = payload.get("subfolder") or ""
        return f"{subfolder}/{name}" if subfolder else name

    async def queue(self, workflow: dict[str, Any]) -> str:
        self._node_types = {
            node_id: str(node.get("class_type"))
            for node_id, node in workflow.items()
            if isinstance(node, dict) and node.get("class_type")
        }
        try:
            async with httpx.AsyncClient(timeout=120) as http:
                response = await http.post(
                    f"{self._base}/prompt",
                    json={"prompt": workflow, "client_id": self._client_id},
                )
        except httpx.HTTPError as exc:
            raise ComfyError(f"Could not reach ComfyUI to queue: {exc!r}") from exc

        if response.status_code != 200:
            # ComfyUI returns a structured validation error — surface the part
            # that says which node is wrong, it's the only useful bit.
            detail = response.text
            try:
                body = response.json()
                detail = json.dumps(body.get("error", body), indent=2)[:1200]
            except ValueError:
                pass
            raise ComfyError(f"Workflow rejected:\n{detail}")

        prompt_id = response.json().get("prompt_id")
        if not prompt_id:
            raise ComfyError("ComfyUI accepted the job but returned no prompt_id")
        return prompt_id

    async def watch(self, prompt_id: str) -> AsyncIterator[ComfyProgress]:
        """Yield progress until the given prompt finishes executing."""
        try:
            async with websockets.connect(
                self._ws_url, max_size=None, open_timeout=60
            ) as socket:
                async for raw in self._with_timeout(socket):
                    if isinstance(raw, bytes):
                        continue  # binary preview frames — not useful here

                    message = json.loads(raw)
                    kind = message.get("type")
                    data = message.get("data", {})

                    if data.get("prompt_id") not in (None, prompt_id):
                        continue

                    if kind == "progress":
                        maximum = max(int(data.get("max", 1)), 1)
                        current = int(data.get("value", 0))
                        yield ComfyProgress(
                            value=min(current / maximum, 1.0),
                            node=str(data.get("node")),
                            stage="sampling",
                            step=current,
                            steps=maximum,
                        )
                    elif kind == "executing":
                        if data.get("node") is None:
                            return  # null node == this prompt is done
                        yield ComfyProgress(
                            value=0.0,
                            node=str(data.get("node")),
                            stage="executing",
                            node_type=self._node_types.get(str(data.get("node"))),
                        )
                    elif kind == "execution_error":
                        raise ComfyError(
                            data.get("exception_message")
                            or "ComfyUI failed while executing the workflow"
                        )
        except websockets.WebSocketException as exc:
            raise ComfyError(f"Lost connection to ComfyUI: {exc}") from exc

    async def _with_timeout(self, socket: Any) -> AsyncIterator[Any]:
        loop = asyncio.get_running_loop()
        deadline = loop.time() + self._timeout
        while True:
            remaining = deadline - loop.time()
            if remaining <= 0:
                raise ComfyError(f"Render exceeded {self._timeout}s")
            try:
                yield await asyncio.wait_for(socket.recv(), timeout=remaining)
            except asyncio.TimeoutError as exc:
                raise ComfyError(f"Render exceeded {self._timeout}s") from exc
            except websockets.ConnectionClosedOK:
                return

    async def outputs(self, prompt_id: str) -> list[ComfyAsset]:
        try:
            async with httpx.AsyncClient(timeout=120) as http:
                response = await http.get(f"{self._base}/history/{prompt_id}")
        except httpx.HTTPError as exc:
            # The pod is reached through an SSH tunnel that drops from time to
            # time. Surfaced as ComfyError so the caller's poll loop treats it
            # as "ask again" rather than letting a transport error escape as
            # an unexplained failure — the render itself is untouched.
            raise ComfyError(f"Could not reach ComfyUI: {exc!r}") from exc

        if response.status_code != 200:
            raise ComfyError(f"History unavailable ({response.status_code})")

        entry = response.json().get(prompt_id)
        if not entry:
            raise ComfyError("ComfyUI has no history for this render")

        status = entry.get("status") or {}
        if status.get("status_str") == "error":
            raise ComfyRenderFailed(_describe_failure(status))

        assets: list[ComfyAsset] = []
        for node_output in entry.get("outputs", {}).values():
            for key in _MEDIA_KEYS:
                for item in node_output.get(key, []):
                    assets.append(
                        ComfyAsset(
                            filename=item["filename"],
                            subfolder=item.get("subfolder", ""),
                            type=item.get("type", "output"),
                        )
                    )
        if not assets:
            # Only terminal once ComfyUI says it is done; before that this is
            # simply a render still in flight.
            if status.get("completed") is True:
                raise ComfyRenderFailed("Render finished but produced no media")
            raise ComfyError("Render has not produced its output yet")
        return assets

    async def download(self, asset: ComfyAsset) -> bytes:
        try:
            return await self._download(asset)
        except httpx.HTTPError as exc:
            raise ComfyError(f"Could not download {asset.filename}: {exc!r}") from exc

    async def _download(self, asset: ComfyAsset) -> bytes:
        async with httpx.AsyncClient(timeout=600) as http:
            response = await http.get(
                f"{self._base}/view",
                params={
                    "filename": asset.filename,
                    "subfolder": asset.subfolder,
                    "type": asset.type,
                },
            )
        if response.status_code != 200:
            raise ComfyError(f"Could not download {asset.filename}")
        return response.content


def _describe_failure(status: dict) -> str:
    """Pull the node error out of ComfyUI's status blob, if it left one."""
    for entry in status.get("messages") or []:
        if isinstance(entry, list) and len(entry) == 2 and entry[0] == "execution_error":
            detail = entry[1] or {}
            node = detail.get("node_type") or detail.get("node_id") or "a node"
            message = detail.get("exception_message") or "no detail given"
            return f"ComfyUI failed in {node}: {message}"
    return "ComfyUI reported the render failed"
