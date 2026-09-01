"""Convert a ComfyUI **UI-format** workflow into the queueable **API format**.

    python scripts/workflow_convert.py \
        --url https://<pod>-8188.proxy.runpod.net \
        --in workflows/client_replace_person.ui.json \
        --out workflows/wan_animate_replace.json

Why not just use ComfyUI's "Export (API)"
-----------------------------------------
That requires opening the graph in a browser and clicking, every time the
client sends a new revision. This does it from the command line, so a workflow
handed over on Discord becomes a bindable backend asset in one step.

The three things that make this non-trivial
-------------------------------------------
1. **Widget names are not in the file.** A node records `widgets_values` as a
   bare list; which input each value belongs to is only knowable from the
   server's `/object_info`. So conversion is done against a live pod — the same
   pod that will run it, which also means an unrunnable graph fails here rather
   than at render time.

2. **Seeds carry an extra value.** Any INT widget with `control_after_generate`
   contributes *two* entries ("randomize", "fixed", ...), so a naive positional
   walk silently shifts every later widget by one.

3. **SetNode / GetNode / Reroute are not real nodes.** They are wire shortcuts
   the frontend resolves at export. `Get_clip_vision` must become a direct link
   back to whatever fed `Set_clip_vision`. Resolving them here is also why the
   pod does not need the newer KJNodes that provides them.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# Nodes that carry no computation: they exist only to move a wire or annotate.
VIRTUAL = {"Reroute", "SetNode", "GetNode", "Note", "MarkdownNote", "PrimitiveNode"}

# Input types that are rendered as widgets rather than sockets. Anything else
# (MODEL, IMAGE, LATENT, ...) can only arrive over a link.
WIDGET_SCALARS = {"INT", "FLOAT", "STRING", "BOOLEAN"}


def is_widget_type(type_: Any) -> bool:
    """Combos arrive in several spellings and new ones keep appearing.

    A bare list is the classic form, "COMBO" the named one, and ComfyUI now
    also emits "COMFY_DYNAMICCOMBO_V3" for inputs whose options depend on other
    inputs (SaveVideo's `codec`). Matching on the substring keeps this working
    as the server adds more rather than silently treating a widget as a socket.
    """
    if isinstance(type_, list):
        return True
    return type_ in WIDGET_SCALARS or "COMBO" in str(type_).upper()


def fetch_object_info(base: str) -> dict[str, Any]:
    req = urllib.request.Request(
        base.rstrip("/") + "/object_info", headers={"User-Agent": "Mozilla/5.0"}
    )
    with urllib.request.urlopen(req, timeout=300) as response:
        return json.load(response)


def load_ui(path: Path) -> dict[str, Any]:
    """Read a workflow, tolerating text pasted around it.

    Files that arrive over Discord's file viewer come wrapped in UI chrome
    ("Page 1 / 1", "Displaying <name>."), which is not JSON. The graph itself
    is the outermost {...}, so slice to that.
    """
    raw = path.read_text(encoding="utf-8", errors="replace")
    start, end = raw.find("{"), raw.rfind("}")
    if start == -1 or end == -1:
        raise SystemExit(f"{path.name} contains no JSON object")
    return json.loads(raw[start : end + 1])


def widget_inputs(spec: dict[str, Any]) -> list[tuple[str, bool]]:
    """Ordered (name, has_control_after_generate) for a node type's widgets."""
    result: list[tuple[str, bool]] = []
    for section in ("required", "optional"):
        for name, definition in (spec.get("input", {}).get(section) or {}).items():
            if not isinstance(definition, list) or not definition:
                continue
            type_ = definition[0]
            options = definition[1] if len(definition) > 1 else {}
            if not is_widget_type(type_):
                continue
            extra = bool(isinstance(options, dict) and options.get("control_after_generate"))
            result.append((name, extra))
    return result


def default_for(definition: list) -> Any:
    """The value the server would use if the widget were never touched."""
    type_ = definition[0]
    options = definition[1] if len(definition) > 1 else {}
    if isinstance(options, dict) and "default" in options:
        return options["default"]
    if isinstance(type_, list):  # classic combo — first entry is the default
        return type_[0] if type_ else None
    # Dynamic combos carry their choices in options["options"], each either a
    # plain string or a {"key": ..., "inputs": {...}} record.
    choices = options.get("options") if isinstance(options, dict) else None
    if choices:
        first = choices[0]
        return first.get("key") if isinstance(first, dict) else first
    return {"INT": 0, "FLOAT": 0.0, "STRING": "", "BOOLEAN": False}.get(type_)


def fill_required_defaults(spec: dict[str, Any], inputs: dict[str, Any]) -> list[str]:
    """Supply required inputs the authored graph never knew about.

    A workflow saved against an older ComfyUI has no value for widgets added
    since — `SaveVideo` gained `codec`, for instance. The node then raises
    `missing 1 required positional argument` at execution time, *after* the
    expensive sampling has already run. Filling from the server's own declared
    default fails safe and keeps old graphs runnable.
    """
    added: list[str] = []
    for name, definition in (spec.get("input", {}).get("required") or {}).items():
        if name in inputs or not isinstance(definition, list) or not definition:
            continue
        if not is_widget_type(definition[0]):
            continue  # a socket left unwired — a real error, not ours to invent
        inputs[name] = default_for(definition)
        added.append(f"{name}={inputs[name]!r}")
    return added


def convert(ui: dict[str, Any], object_info: dict[str, Any]) -> dict[str, Any]:
    nodes = {n["id"]: n for n in ui.get("nodes", [])}
    # link id -> (origin node id, origin output slot)
    links = {l[0]: (l[1], l[2]) for l in ui.get("links", []) if len(l) >= 3}

    # Set_<name> -> the link feeding it, so Get_<name> can be traced back.
    set_source: dict[str, int | None] = {}
    for node in ui.get("nodes", []):
        if node.get("type") == "SetNode":
            key = (node.get("widgets_values") or [None])[0]
            inputs = node.get("inputs") or [{}]
            set_source[key] = inputs[0].get("link")

    def resolve(link_id: int | None) -> list | None:
        """Follow a link through virtual nodes to a real [node_id, slot]."""
        seen: set[int] = set()
        while link_id is not None and link_id not in seen:
            seen.add(link_id)
            origin = links.get(link_id)
            if not origin:
                return None
            node_id, slot = origin
            node = nodes.get(node_id)
            if node is None:
                return None
            kind = node.get("type")
            if kind == "Reroute":
                link_id = (node.get("inputs") or [{}])[0].get("link")
            elif kind == "SetNode":
                link_id = (node.get("inputs") or [{}])[0].get("link")
            elif kind == "GetNode":
                link_id = set_source.get((node.get("widgets_values") or [None])[0])
            else:
                return [str(node_id), slot]
        return None

    api: dict[str, Any] = {}
    warnings: list[str] = []

    for node in ui.get("nodes", []):
        kind = node.get("type")
        if kind in VIRTUAL:
            continue
        # Muted (2) and bypassed (4) nodes are disabled in the UI; queueing them
        # would run work the author deliberately turned off.
        if node.get("mode") in (2, 4):
            continue

        spec = object_info.get(kind)
        if spec is None:
            warnings.append(f"node {node['id']} ({kind}): not installed on this pod")
            continue

        inputs: dict[str, Any] = {}

        # 1. Sockets — whatever is actually wired.
        for slot in node.get("inputs") or []:
            name = slot.get("name")
            target = resolve(slot.get("link"))
            if name and target:
                inputs[name] = target

        # 2. Widgets — positional, unless the node stores them by name.
        raw_widgets = node.get("widgets_values")
        if isinstance(raw_widgets, dict):
            # VideoHelperSuite keeps a dict, which is unambiguous — use it.
            for name, value in raw_widgets.items():
                if name not in inputs:
                    inputs[name] = value
        else:
            values = list(raw_widgets or [])
            index = 0
            for name, has_control in widget_inputs(spec):
                if index >= len(values):
                    break
                if name not in inputs:
                    inputs[name] = values[index]
                index += 1
                if has_control:
                    index += 1  # skip "randomize"/"fixed"

        filled = fill_required_defaults(spec, inputs)
        if filled:
            print(f"  filled  {node['id']} ({kind}): {', '.join(filled)}")

        api[str(node["id"])] = {
            "class_type": kind,
            "inputs": inputs,
            "_meta": {"title": node.get("title") or kind},
        }

    for warning in warnings:
        print(f"  WARNING  {warning}")
    return api


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True, help="a running ComfyUI to read /object_info from")
    parser.add_argument("--in", dest="source", required=True)
    parser.add_argument("--out", dest="target", required=True)
    args = parser.parse_args()

    source = Path(args.source)
    ui = load_ui(source)
    print(f"Reading {source.name}: {len(ui.get('nodes', []))} nodes")

    object_info = fetch_object_info(args.url)
    api = convert(ui, object_info)

    target = Path(args.target)
    target.write_text(json.dumps(api, indent=2), encoding="utf-8")
    print(f"Wrote {target} : {len(api)} nodes")

    dangling = [
        f"{nid} ({node['class_type']}).{key}"
        for nid, node in api.items()
        for key, value in node["inputs"].items()
        if isinstance(value, list) and len(value) == 2 and str(value[0]) not in api
    ]
    if dangling:
        print(f"  WARNING  {len(dangling)} input(s) point at missing nodes: {dangling[:6]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
