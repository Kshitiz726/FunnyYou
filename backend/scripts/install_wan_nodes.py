"""Install the custom nodes the client's Wan Animate workflows need.

    python scripts/install_wan_nodes.py --url https://<pod>-8188.proxy.runpod.net

ComfyUI-Manager permits git-clone installs from a public origin (unlike pip
installs and reboots, which it refuses — correctly, since the pod has no auth).
So the node packs can be installed remotely; only the restart afterwards needs
someone with pod access.

Which packs, and why
--------------------
Derived by diffing the workflows' node types against the pod's /object_info,
not guessed:

    VHS_*                        ComfyUI-VideoHelperSuite   load/save the driving video
    Sam2Segmentation             segment-anything-2         isolate the person to replace
    DWPreprocessor               controlnet_aux             body pose from the template
    PoseAndFaceDetection         WanAnimatePreprocess       Wan Animate's own preprocessing
    SetNode / GetNode            KJNodes (newer)            the workflow's wire shortcuts
    FaceMaskFromPoseKeypoints    KJNodes (newer)            face region for the swap

KJNodes is already on the pod but too old for several of these, so it is
updated rather than installed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

UA = {"User-Agent": "Mozilla/5.0"}

# id in ComfyUI-Manager's registry -> what it unblocks
PACKS = {
    "comfyui-videohelpersuite": "video load/save (VHS_*)",
    "comfyui-segment-anything-2": "person segmentation (Sam2*)",
    "comfyui_controlnet_aux": "pose extraction (DWPreprocessor)",
    # Owns FaceMaskFromPoseKeypoints — confirmed against Manager's node
    # mappings, not assumed. It is not a KJNodes node despite the author.
    # The registry id is case-sensitive; the lowercase form matches nothing and
    # the script would report success while installing nothing at all.
    "ComfyUI-WanVideoWrapper": "FaceMaskFromPoseKeypoints",
}

# SetNode / GetNode are deliberately absent from this list. They are wire
# shortcuts, not computation: a GetNode just re-emits whatever its matching
# SetNode was fed. ComfyUI's own "Export (API)" resolves them away, and so does
# `workflow_convert.py`, so the pod never needs the KJNodes version that has
# them — which matters, because updating KJNodes on this pod fails
# (`res.action=update-git`, the slim image ships a clone git cannot fast-forward).
FORCE_UPDATE: set[str] = set()


def _get(base: str, path: str, timeout: int = 180):
    req = urllib.request.Request(base + path, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return json.load(response)


def _post(base: str, path: str, payload: dict | None = None, timeout: int = 300):
    # Always send a JSON body, even an empty one. `queue/start` with no body
    # answers 200 and quietly does nothing; with `{}` and the JSON content type
    # it answers 201 and actually runs the queue. That difference cost an hour.
    headers = dict(UA)
    headers["Content-Type"] = "application/json"
    body = json.dumps(payload if payload is not None else {}).encode()
    try:
        req = urllib.request.Request(base + path, data=body, headers=headers)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.status, response.read().decode(errors="replace")[:200]
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace")[:200]


def registry(base: str) -> dict[str, dict]:
    data = _get(base, "/api/customnode/getlist?mode=cache")
    packs = data.get("node_packs") or data
    if isinstance(packs, dict):
        packs = list(packs.values())
    return {p.get("id"): p for p in packs if p.get("id")}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    args = parser.parse_args()
    base = args.url.rstrip("/")

    print(f"Installing Wan Animate node packs on {base}\n")
    index = registry(base)

    queued = 0
    for pack_id, why in PACKS.items():
        entry = index.get(pack_id)
        if not entry:
            print(f"  [SKIP] {pack_id:32} not in registry")
            continue

        state = entry.get("state")
        forced = pack_id in FORCE_UPDATE
        if state in {"installed", "enabled"} and not forced:
            print(f"  [HAVE] {pack_id:32} {why}")
            continue

        payload = dict(entry)
        payload.update(
            selected_version=entry.get("version") or entry.get("cnr_latest"),
            channel="default",
            mode="cache",
            skip_post_install=False,
        )
        endpoint = "update" if state in {"installed", "enabled"} else "install"
        status, body = _post(base, f"/api/manager/queue/{endpoint}", payload)
        ok = status < 400
        queued += ok
        label = endpoint.upper()[:5].ljust(5)
        print(f"  [{label if ok else 'FAIL '}] {pack_id:32} {why}"
              + ("" if ok else f"  ({status} {body.strip()[:60]})"))

    if not queued:
        print("\nNothing queued.")
        return 1

    print(f"\nStarting the queue ({queued} pack(s))...")
    _post(base, "/api/manager/queue/start")

    seen = False
    for _ in range(240):
        try:
            state = _get(base, "/api/manager/queue/status", timeout=30)
        except Exception:  # noqa: BLE001 — server churns during installs
            time.sleep(2)
            continue
        if state.get("total_count", 0) > 0:
            seen = True
        if seen and not state.get("is_processing"):
            print(f"  queue finished: {state}")
            break
        time.sleep(2)

    print(
        "\nInstalled on disk — but ComfyUI must RESTART before the nodes load.\n"
        "Manager refuses remote reboots, so ask whoever owns the pod to restart it.\n"
        "Then re-run with --verify on install_wan_nodes to confirm."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
