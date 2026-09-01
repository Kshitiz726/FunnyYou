"""Install the face-swap stack onto a running ComfyUI pod.

    python scripts/provision_faceswap.py --url https://<pod>-8188.proxy.runpod.net

Why this exists
---------------
Z-Image (and every other plain text-to-image model) has no way to take a face
as input, so img2img trades identity against prompt adherence with no good
setting in between: keep the face and the scenario barely applies, apply the
scenario and it is a stranger. A face-swap pass sidesteps that entirely —
generate the scene with whatever face the model likes, then paste the user's
face onto it as a post-step. Identity fidelity stops being a sampler parameter.

Pods are ephemeral: RunPod hands you a fresh container with an empty
`custom_nodes/` every time. This script is the reproducible way back to a
working pod, rather than a sequence of clicks in the Manager UI.

Licence note
------------
ReActor's default swap model, `inswapper_128`, is InsightFace's and is licensed
for **non-commercial research only**. That is fine while building. Shipping
this commercially needs a licence from insightface.ai, a licensed hosted API,
or a permissively-licensed swap model.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

UA = {"User-Agent": "Mozilla/5.0"}

PACK_ID = "comfyui-reactor"

# ReActor downloads these itself on first run in most builds, but a pod with no
# outbound cache does it slowly and silently. Fetching them up front means the
# first user-facing swap is not a two-minute stall.
MODELS = [
    {
        "name": "inswapper_128.onnx",
        "url": "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/inswapper_128.onnx",
        "directory": "insightface",
    },
    {
        "name": "GFPGANv1.4.pth",
        "url": "https://huggingface.co/datasets/Gourieff/ReActor/resolve/main/models/facerestore_models/GFPGANv1.4.pth",
        "directory": "facerestore_models",
    },
]

SWAP_NODES = ("ReActorFaceSwap", "ReActorFaceSwapOpt", "ReActorLoadFaceModel")


def _request(url: str, *, data: bytes | None = None, timeout: int = 180):
    headers = dict(UA)
    if data is not None:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=data, headers=headers)
    return urllib.request.urlopen(req, timeout=timeout)


def _get_json(base: str, path: str, timeout: int = 180):
    with _request(base + path, timeout=timeout) as response:
        return json.load(response)


def _post(base: str, path: str, payload: dict | None = None, timeout: int = 300):
    # An empty body makes `queue/start` answer 200 and do nothing; `{}` with a
    # JSON content type makes it answer 201 and actually run.
    body = json.dumps(payload if payload is not None else {}).encode()
    try:
        with _request(base + path, data=body, timeout=timeout) as response:
            return response.status, response.read().decode(errors="replace")[:500]
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode(errors="replace")[:500]


def _registry_entry(base: str, pack_id: str) -> dict | None:
    """The Manager wants the pack object it published, not a hand-built one.

    A subset payload is accepted with a 200 and then silently queues nothing,
    so this reads the entry back rather than guessing at the schema.
    """
    data = _get_json(base, "/api/customnode/getlist?mode=cache", timeout=180)
    packs = data.get("node_packs") or data
    if isinstance(packs, dict):
        packs = list(packs.values())
    for pack in packs:
        if pack.get("id") == pack_id:
            return pack
    return None


def install_node(base: str) -> bool:
    print("\n[1/4] installing ComfyUI-ReActor")
    entry = _registry_entry(base, PACK_ID)
    if not entry:
        print(f"      {PACK_ID} is not in this pod's registry")
        return False
    if entry.get("state") == "installed":
        print("      already installed")
        return True

    payload = dict(entry)
    payload.update(
        selected_version=entry.get("version") or entry.get("cnr_latest"),
        channel="default",
        mode="cache",
        skip_post_install=False,
    )

    status, body = _post(base, "/api/manager/queue/install", payload)
    print(f"      queue/install -> {status} {body.strip()[:160]}")
    if status >= 400:
        return False

    status, body = _post(base, "/api/manager/queue/start")
    print(f"      queue/start   -> {status} {body.strip()[:160]}")

    # The Manager installs asynchronously; without waiting, the reboot below
    # would land mid-pip-install and leave a half-written node directory.
    queued = False
    for _ in range(180):
        try:
            state = _get_json(base, "/api/manager/queue/status", timeout=30)
        except Exception:  # noqa: BLE001 — the server restarts under us
            time.sleep(2)
            continue
        if state.get("total_count", 0) > 0:
            queued = True
        if queued and not state.get("is_processing"):
            print(f"      done: {state}")
            return state.get("done_count", 0) > 0
        time.sleep(2)
    print("      TIMED OUT waiting for the install queue")
    return False


def fetch_models(base: str) -> None:
    print("\n[2/4] fetching swap + restore models")
    for model in MODELS:
        status, body = _post(base, "/api/manager/queue/install_model", model)
        print(f"      {model['name']:<22} -> {status} {body.strip()[:100]}")
    _post(base, "/api/manager/queue/start")


def reboot(base: str) -> None:
    print("\n[3/4] rebooting ComfyUI so the new node loads")
    try:
        _post(base, "/api/manager/reboot", timeout=15)
    except Exception:  # noqa: BLE001 — the connection dies mid-reboot, expected
        pass

    for attempt in range(150):
        try:
            with _request(base + "/system_stats", timeout=10):
                print(f"      back up after ~{attempt * 2}s")
                return
        except Exception:  # noqa: BLE001
            time.sleep(2)
    print("      TIMED OUT waiting for ComfyUI to come back")


def verify(base: str) -> bool:
    print("\n[4/4] verifying the swap nodes are registered")
    info = _get_json(base, "/object_info", timeout=180)
    found = [n for n in SWAP_NODES if n in info]
    missing = [n for n in SWAP_NODES if n not in info]
    print(f"      present: {found or 'NONE'}")
    if missing:
        print(f"      missing: {missing}")
    return bool(found)


# ComfyUI-Manager refuses `pip` installs and reboots from a non-local origin —
# both are remote code execution over a public URL, so it is right to. Those
# two steps have to be run on the pod itself.
MANUAL_STEPS = r"""
Run these in the pod's own shell (RunPod console -> Terminal):

    cd /workspace/runpod-slim/ComfyUI
    .venv-cu128/bin/python -m pip install setuptools insightface onnxruntime-gpu
    .venv-cu128/bin/python custom_nodes/comfyui-reactor/install.py

If insightface fails to build (no compiler on a slim image):

    apt-get update && apt-get install -y build-essential python3-dev
    .venv-cu128/bin/python -m pip install --no-build-isolation insightface

Then restart ComfyUI from the RunPod UI, and re-run this script with --verify.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument(
        "--verify",
        action="store_true",
        help="skip installing; just check whether the swap nodes are loaded",
    )
    args = parser.parse_args()
    base = args.url.rstrip("/")

    print(f"Provisioning face swap on {base}")

    if args.verify:
        return 0 if verify(base) else 1

    if not install_node(base):
        print("\nThe node pack did not install cleanly.")
        print(MANUAL_STEPS)
        return 1

    fetch_models(base)

    if verify(base):
        print("\nFACE SWAP READY")
        return 0

    print(
        "\nThe repository is cloned but the swap nodes are not registered — "
        "ComfyUI has not restarted, and its Python deps are incomplete."
    )
    print(MANUAL_STEPS)
    return 1


if __name__ == "__main__":
    sys.exit(main())
