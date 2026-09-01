"""Make the client's converted Wan Animate graph runnable on *this* pod.

    python scripts/prepare_wan_workflow.py \
        --url https://<pod>-8188.proxy.runpod.net \
        --in workflows/wan_animate_replace.json \
        --out workflows/wan22_animate.json

Two jobs.

**Re-point the model names.** The client authored his graph against a pod whose
weights came from Comfy-Org's repackaged repos; the download list he sent pulls
Kijai's builds, which have entirely different filenames. Every loader in the
graph therefore names a file this pod does not have. The mapping is explicit
below rather than fuzzy-matched, because silently loading the wrong 18 GB model
is worse than failing.

**Add the FY_ markers.** `app/workflow.py` binds by node title, so the graph has
to declare which node takes the customer's photo, which takes the scenario
prompt, and which produces the output. Titles are set here rather than by hand
so a new revision from the client is one command away from being usable.
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.request
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

UA = {"User-Agent": "Mozilla/5.0"}

# widget name -> {what the graph asks for: what this pod actually has}
#
# The lightx2v entry is NOT a pure rename: the graph wants an I2V rank64 LoRA
# and the pod has the T2V rank256 one from the client's own download list. Both
# are step-distillation LoRAs for the same base, so it runs — but if motion
# quality looks off, this line is the first thing to suspect.
REMAP = {
    "unet_name": {
        "wan2.2_animate_14B_bf16.safetensors": "Wan2_2-Animate-14B_fp8_e5m2_scaled_KJ.safetensors",
    },
    "clip_name": {
        "umt5_xxl_fp8_e4m3fn_scaled.safetensors": "umt5_xxl_fp16.safetensors",
        "clip_vision_h.safetensors": "CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors",
    },
    "vae_name": {
        "wan_2.1_vae.safetensors": "Wan2_1_VAE_bf16.safetensors",
    },
    "lora_name": {
        "lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors":
            "lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors",
        "wan2.2_animate_14B_relight_lora_bf16.safetensors":
            "WanAnimate_relight_lora_fp16.safetensors",
    },
}

# node id -> marker title. Derived from the client's own node titles and wiring,
# and asserted against class_type below so a re-export that renumbers nodes
# fails loudly instead of marking the wrong node.
MARKERS = {
    "311": ("FY_INPUT_IMAGE", "LoadImage"),        # the customer's photo
    "417": ("FY_TEMPLATE_VIDEO", "VHS_LoadVideo"),  # the scenario template clip
    "227": ("FY_POSITIVE", "CLIPTextEncode"),
    "228": ("FY_NEGATIVE", "CLIPTextEncode"),
    "324": ("FY_SAMPLER", "KSampler"),
    "370": ("FY_LATENT", "WanAnimateToVideo"),      # width / height / length
    "393": ("FY_OUTPUT", "SaveVideo"),
}


def pod_models(base: str, folder: str) -> list[str]:
    req = urllib.request.Request(f"{base}/api/models/{folder}", headers=UA)
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            return json.load(response)
    except Exception:  # noqa: BLE001 — absent folder is a valid answer
        return []


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", required=True)
    parser.add_argument("--in", dest="source", required=True)
    parser.add_argument("--out", dest="target", required=True)
    args = parser.parse_args()
    base = args.url.rstrip("/")

    graph = json.loads(Path(args.source).read_text(encoding="utf-8"))

    available = {
        folder: set(pod_models(base, folder))
        for folder in ("diffusion_models", "loras", "vae", "clip_vision", "text_encoders")
    }
    everything = set().union(*available.values())

    print("Re-pointing model names")
    unresolved: list[str] = []
    for node_id, node in graph.items():
        for key, value in list(node["inputs"].items()):
            if key not in REMAP or not isinstance(value, str):
                continue
            replacement = REMAP[key].get(value)
            if replacement:
                node["inputs"][key] = replacement
                mark = "OK " if replacement in everything else "!! "
                print(f"  {mark}{node_id:>4} {key:10} {value}\n        -> {replacement}")
                if replacement not in everything:
                    unresolved.append(f"{node_id}.{key} -> {replacement}")
            elif value not in everything:
                print(f"  ?? {node_id:>4} {key:10} {value}  (no mapping, not on pod)")
                unresolved.append(f"{node_id}.{key} = {value}")

    print("\nApplying FY_ markers")
    for node_id, (title, expected) in MARKERS.items():
        node = graph.get(node_id)
        if node is None:
            print(f"  !! node {node_id} missing — cannot set {title}")
            unresolved.append(f"missing node {node_id} for {title}")
            continue
        if node["class_type"] != expected:
            print(f"  !! node {node_id} is {node['class_type']}, expected {expected}")
            unresolved.append(f"node {node_id} type mismatch for {title}")
            continue
        node["_meta"]["title"] = title
        print(f"  OK  {node_id:>4} {expected:18} -> {title}")

    Path(args.target).write_text(json.dumps(graph, indent=2), encoding="utf-8")
    print(f"\nWrote {args.target} ({len(graph)} nodes)")

    if unresolved:
        print(f"\n{len(unresolved)} unresolved:")
        for item in unresolved:
            print(f"  - {item}")
        return 1
    print("\nEvery model resolves and every marker is placed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
