"""Loads a ComfyUI workflow and binds the app's inputs into it.

Design note — why binding is by *title* and not by node id
----------------------------------------------------------
Wan 2.2 Animate graphs differ between ComfyUI versions, custom-node versions
and quantisations. Hard-coding node ids ("node 47 is the KSampler") breaks the
moment anyone re-exports the graph.

Instead, this module binds by node title. You build and prove the workflow in
the ComfyUI web UI, rename five nodes (right-click → Title), export as
**API format**, and drop the JSON in `workflows/`. Nothing here changes.

Required titles
---------------
    FY_INPUT_IMAGE    LoadImage      — the user's face
    FY_POSITIVE       CLIPTextEncode — scenario prompt
    FY_OUTPUT         SaveVideo / VHS_VideoCombine

Optional titles
---------------
    FY_NEGATIVE        CLIPTextEncode — negative prompt
    FY_SAMPLER         KSampler       — seed lives here
    FY_LATENT          any node with width/height/length/num_frames inputs
    FY_TEMPLATE_VIDEO  VHS_LoadVideo  — the scenario's driving clip

Missing an optional marker is fine; the value is simply left as authored.

Why FY_TEMPLATE_VIDEO exists
----------------------------
Character-swap rendering does not generate a scene from nothing: it takes an
already-made template clip and replaces the performer with the customer. So a
render needs *two* inputs — the customer's photo and the scenario's video — and
which video to use is chosen per template by the caller, not baked into the
graph.
"""

from __future__ import annotations

import json
import random
from dataclasses import dataclass
from pathlib import Path
from typing import Any

MARKER_IMAGE = "FY_INPUT_IMAGE"
MARKER_POSITIVE = "FY_POSITIVE"
MARKER_NEGATIVE = "FY_NEGATIVE"
MARKER_SAMPLER = "FY_SAMPLER"
MARKER_LATENT = "FY_LATENT"
MARKER_OUTPUT = "FY_OUTPUT"
MARKER_TEMPLATE_VIDEO = "FY_TEMPLATE_VIDEO"
MARKER_TEMPLATE_STILL = "FY_TEMPLATE_STILL"
MARKER_POINTS = "FY_POINTS"

# FY_POSITIVE is deliberately absent: a pure face-swap graph has no text
# conditioning at all. It copies the template's costume, lighting and motion
# verbatim and replaces only the face, so there is nothing for a prompt to
# steer. Generative graphs (Wan Animate, Z-Image) still carry the marker and
# still get the prompt bound — build() patches it when present.
REQUIRED_MARKERS = (MARKER_IMAGE, MARKER_OUTPUT)

DEFAULT_NEGATIVE = (
    "blurry, low quality, distorted face, extra limbs, deformed hands, "
    "watermark, text, oversaturated, jpeg artifacts"
)

# Frame-count inputs vary by node pack; patch whichever is present.
_LENGTH_KEYS = ("length", "num_frames", "frame_count", "video_frames", "batch_size")


class WorkflowError(RuntimeError):
    """The workflow file is missing something the app needs."""


@dataclass(frozen=True)
class RenderParams:
    image_name: str
    prompt: str
    negative: str = DEFAULT_NEGATIVE
    seed: int | None = None
    width: int | None = None
    height: int | None = None
    frames: int | None = None
    template_video: str | None = None
    template_still: str | None = None
    points: dict | None = None


def load(path: str | Path) -> dict[str, Any]:
    file = Path(path)
    if not file.is_file():
        raise WorkflowError(f"Workflow not found: {file}")

    try:
        graph = json.loads(file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise WorkflowError(f"{file.name} is not valid JSON: {exc}") from exc

    if not isinstance(graph, dict):
        raise WorkflowError(f"{file.name} is not a workflow object")

    # The UI's "Save" format nests everything under "nodes" as a list. Only the
    # "Save (API format)" export is queueable, so catch the common mistake.
    if "nodes" in graph and isinstance(graph.get("nodes"), list):
        raise WorkflowError(
            f"{file.name} looks like a UI export. In ComfyUI use "
            "Workflow → Export (API) instead."
        )

    return graph


def find_by_title(graph: dict[str, Any], title: str) -> str | None:
    for node_id, node in graph.items():
        if not isinstance(node, dict):
            continue
        if node.get("_meta", {}).get("title") == title:
            return node_id
    return None


def validate(graph: dict[str, Any]) -> list[str]:
    """Return the list of required markers this graph is missing."""
    return [m for m in REQUIRED_MARKERS if find_by_title(graph, m) is None]


def _set_input(graph: dict[str, Any], node_id: str, key: str, value: Any) -> bool:
    inputs = graph[node_id].setdefault("inputs", {})
    # Never overwrite a wired connection (those are [node_id, slot] lists) —
    # doing so silently detaches part of the graph.
    if isinstance(inputs.get(key), list):
        return False
    inputs[key] = value
    return True


def _set_prompt_text(graph: dict[str, Any], node_id: str, value: str) -> bool:
    """Write prompt text into whichever field this encoder actually uses.

    `CLIPTextEncode` calls it `text`; Qwen's `TextEncodeQwenImageEditPlus`
    calls it `prompt`. Writing `text` unconditionally left the real prompt
    untouched *and* added a field the node does not declare, so the graph
    carried a stray input and the baked-in prompt ran instead of the caller's.
    An empty value is left alone deliberately: the reference graph's prompt is
    part of the graph, and callers that pass "" mean "keep it".
    """
    if not value:
        return False
    inputs = graph[node_id].get("inputs", {})
    for key in ("text", "prompt"):
        if key in inputs:
            return _set_input(graph, node_id, key, value)
    return False


def _set_through_link(graph: dict[str, Any], node_id: str, key: str, value: Any) -> bool:
    """Set `key`, following a wired link back to the primitive that feeds it.

    Overwriting a wired input would detach the graph, so `_set_input` refuses —
    but refusing is not the same as succeeding, and `build` used to ignore the
    difference. In a graph where width, height and length are each fed by a
    PrimitiveInt (which is how these were authored in the ComfyUI editor), that
    made every one of those settings a silent no-op: the render simply used
    whatever was baked into the JSON.

    Writing the upstream primitive's `value` is what a human would do in the
    editor, and it keeps the wiring intact.
    """
    inputs = graph[node_id].setdefault("inputs", {})
    current = inputs.get(key)
    if not isinstance(current, list):
        inputs[key] = value
        return True
    upstream = graph.get(str(current[0]))
    if upstream is not None and "value" in (upstream.get("inputs") or {}):
        upstream["inputs"]["value"] = value
        return True
    return False


def build(graph: dict[str, Any], params: RenderParams) -> dict[str, Any]:
    """Return a copy of `graph` with the app's inputs bound into it."""
    missing = validate(graph)
    if missing:
        raise WorkflowError(
            "Workflow is missing required node titles: "
            + ", ".join(missing)
            + ". Rename the nodes in ComfyUI and re-export as API format."
        )

    patched = json.loads(json.dumps(graph))  # deep copy

    image_node = find_by_title(patched, MARKER_IMAGE)
    _set_input(patched, image_node, "image", params.image_name)

    positive_node = find_by_title(patched, MARKER_POSITIVE)
    if positive_node:
        _set_prompt_text(patched, positive_node, params.prompt)

    negative_node = find_by_title(patched, MARKER_NEGATIVE)
    if negative_node:
        _set_prompt_text(patched, negative_node, params.negative)

    if params.template_video:
        video_node = find_by_title(patched, MARKER_TEMPLATE_VIDEO)
        if video_node:
            _set_input(patched, video_node, "video", params.template_video)

    if params.template_still:
        still_node = find_by_title(patched, MARKER_TEMPLATE_STILL)
        if still_node:
            _set_input(patched, still_node, "image", params.template_still)

    if params.points:
        _bind_points(patched, params.points)

    sampler_node = find_by_title(patched, MARKER_SAMPLER)
    if sampler_node:
        seed = params.seed if params.seed is not None else random.randint(0, 2**32 - 1)
        # Node packs disagree on the field name.
        for key in ("seed", "noise_seed"):
            if key in patched[sampler_node].get("inputs", {}):
                _set_input(patched, sampler_node, key, seed)

    latent_node = find_by_title(patched, MARKER_LATENT)
    if latent_node:
        inputs = patched[latent_node].get("inputs", {})
        if params.width and "width" in inputs:
            _set_through_link(patched, latent_node, "width", params.width)
        if params.height and "height" in inputs:
            _set_through_link(patched, latent_node, "height", params.height)
        if params.frames:
            for key in _LENGTH_KEYS:
                if key in inputs:
                    _set_through_link(patched, latent_node, key, params.frames)
                    break

    return patched


def find_points_node(graph: dict[str, Any]) -> str | None:
    """The node that selects which person in the frame to replace.

    Found by title first so a workflow can be explicit, then by class so an
    unmodified export from ComfyUI still works.
    """
    node_id = find_by_title(graph, MARKER_POINTS)
    if node_id:
        return node_id
    for candidate, node in graph.items():
        if isinstance(node, dict) and node.get("class_type") == "PointsEditor":
            return candidate
    return None


def _resolve_int(graph: dict[str, Any], value: Any) -> int | None:
    """Read an input that may be a literal or a link to a primitive node."""
    if isinstance(value, int):
        return value
    if isinstance(value, list) and value and isinstance(value[0], str):
        source = graph.get(value[0])
        if isinstance(source, dict):
            inner = source.get("inputs", {}).get("value")
            if isinstance(inner, int):
                return inner
    return None


def _bind_points(graph: dict[str, Any], points: dict) -> None:
    """Bind a clip's own click points over whatever the graph was saved with.

    The saved coordinates belong to whichever clip the workflow was last
    authored against. Leaving them in place for a different clip does not
    fail — it segments the wrong subject and renders something plainly wrong,
    which is far worse than an error.

    Points are stored normalised (0..1) rather than in pixels, because the
    editor's coordinate space is the render size: the same clip authored at
    480x832 and rendered at 720x1248 needs the same *relative* points, and
    pixel values silently drift to the wrong part of the frame when the
    render size changes.
    """
    node_id = find_points_node(graph)
    if node_id is None:
        return

    inputs = graph[node_id].setdefault("inputs", {})
    width = _resolve_int(graph, inputs.get("width"))
    height = _resolve_int(graph, inputs.get("height"))

    def place(point: dict) -> dict:
        x, y = float(point.get("x", 0)), float(point.get("y", 0))
        # Values inside the unit square are relative; anything larger is
        # already in pixels and is passed through untouched.
        if width and height and 0.0 <= x <= 1.0 and 0.0 <= y <= 1.0:
            return {"x": round(x * width, 1), "y": round(y * height, 1)}
        return {"x": x, "y": y}

    positive = [place(p) for p in (points.get("positive") or [])]
    negative = [place(p) for p in (points.get("negative") or [])]

    inputs["points_store"] = json.dumps({"positive": positive, "negative": negative})
    inputs["coordinates"] = json.dumps(positive)
    inputs["neg_coordinates"] = json.dumps(negative)
