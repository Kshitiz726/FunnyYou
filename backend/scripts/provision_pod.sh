#!/usr/bin/env bash
# Provision a RunPod GPU pod for the Wan 2.2 Animate character-swap pipeline.
#
#   bash /workspace/provision.sh
#
# Everything lands on /workspace, which is the network volume — so this survives
# the pod being terminated and can be re-attached to a different GPU later. That
# is the whole point: the previous pod lost its GPU and its 62 GB was welded to
# a datacenter with no capacity.
#
# Idempotent. Re-running skips anything already present, so a failed download
# can be retried by just running it again.

set -uo pipefail   # deliberately NOT -e: one bad download must not abort the rest

ROOT=/workspace
COMFY=$ROOT/ComfyUI
LOG=$ROOT/provision.log

exec > >(tee -a "$LOG") 2>&1
echo "=== provision start $(date -u +%FT%TZ) ==="

# Keep pip and HuggingFace caches off the 20 GB container disk. Without this a
# torch reinstall alone can fill it and the failure looks like a network error.
export PIP_CACHE_DIR=$ROOT/.cache/pip
export HF_HOME=$ROOT/.cache/huggingface
mkdir -p "$PIP_CACHE_DIR" "$HF_HOME"

# ---------------------------------------------------------------- ComfyUI ----
if [ ! -d "$COMFY/.git" ]; then
    echo "--- cloning ComfyUI"
    git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
    pip install --no-cache-dir -r "$COMFY/requirements.txt"
else
    echo "--- ComfyUI already present, skipping"
fi

# ------------------------------------------------------------ custom nodes ----
# Exactly the packs the client's graph needs, determined by diffing its node
# types against a live /object_info. ComfyUI-Manager is included so the client
# can install things himself without a shell.
declare -A NODES=(
  [ComfyUI-Manager]=https://github.com/Comfy-Org/ComfyUI-Manager.git
  [ComfyUI-VideoHelperSuite]=https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git
  [ComfyUI-segment-anything-2]=https://github.com/kijai/ComfyUI-segment-anything-2.git
  [comfyui_controlnet_aux]=https://github.com/Fannovel16/comfyui_controlnet_aux.git
  [ComfyUI-WanVideoWrapper]=https://github.com/kijai/ComfyUI-WanVideoWrapper.git
  [ComfyUI-KJNodes]=https://github.com/kijai/ComfyUI-KJNodes.git
)

mkdir -p "$COMFY/custom_nodes"
for name in "${!NODES[@]}"; do
    dir="$COMFY/custom_nodes/$name"
    if [ -d "$dir/.git" ]; then
        echo "--- node $name already present"
        continue
    fi
    echo "--- cloning $name"
    git clone --depth 1 "${NODES[$name]}" "$dir" || { echo "FAIL clone $name"; continue; }
    if [ -f "$dir/requirements.txt" ]; then
        # Non-fatal: several packs list optional extras that do not resolve on
        # every CUDA/python combination, and the nodes still load without them.
        pip install --no-cache-dir -r "$dir/requirements.txt" || echo "WARN deps $name"
    fi
done

# ------------------------------------------------------------------ models ----
# "dest|url" — dest is relative to ComfyUI/models. Names must match exactly what
# workflows/wan22_animate.json references, or the graph fails validation with an
# unhelpful "value not in list".
MODELS=(
  "unet/Wan2_2-Animate-14B_fp8_e5m2_scaled_KJ.safetensors|https://huggingface.co/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_e5m2_scaled_KJ.safetensors"
  "text_encoders/umt5_xxl_fp16.safetensors|https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors"
  "vae/Wan2_1_VAE_bf16.safetensors|https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors"
  "clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors|https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
  "loras/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors|https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors"
  "loras/WanAnimate_relight_lora_fp16.safetensors|https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors"
  "sam2/sam2_hiera_base_plus.safetensors|https://huggingface.co/Kijai/sam2-safetensors/resolve/main/sam2_hiera_base_plus.safetensors"
)

echo "--- downloading models"
FAILED=()
for entry in "${MODELS[@]}"; do
    dest="${entry%%|*}"; url="${entry#*|}"
    path="$COMFY/models/$dest"
    mkdir -p "$(dirname "$path")"

    # A partial file from an interrupted run is worse than a missing one: it
    # loads and then explodes mid-sampler. Treat anything under 1 MB as absent.
    if [ -f "$path" ] && [ "$(stat -c%s "$path")" -gt 1000000 ]; then
        echo "    have $(basename "$dest") ($(du -h "$path" | cut -f1))"
        continue
    fi

    echo "    GET $(basename "$dest")"
    if curl -fL --retry 3 --retry-delay 5 -o "$path" "$url"; then
        echo "    OK  $(du -h "$path" | cut -f1)"
    else
        echo "    FAIL $dest"
        rm -f "$path"
        FAILED+=("$dest")
    fi
done

# The DWPose pair that comfyui_controlnet_aux would otherwise fetch lazily on
# first use — a silent 200 MB stall in the middle of a paid render.
DW=$COMFY/custom_nodes/comfyui_controlnet_aux/ckpts
mkdir -p "$DW/yzd-v/DWPose" "$DW/hr16/DWPose-TorchScript-BatchSize5"
[ -s "$DW/yzd-v/DWPose/yolox_l.onnx" ] || \
  curl -fL --retry 3 -o "$DW/yzd-v/DWPose/yolox_l.onnx" \
    https://huggingface.co/yzd-v/DWPose/resolve/main/yolox_l.onnx || echo "WARN yolox"
[ -s "$DW/hr16/DWPose-TorchScript-BatchSize5/dw-ll_ucoco_384_bs5.torchscript.pt" ] || \
  curl -fL --retry 3 -o "$DW/hr16/DWPose-TorchScript-BatchSize5/dw-ll_ucoco_384_bs5.torchscript.pt" \
    https://huggingface.co/hr16/DWPose-TorchScript-BatchSize5/resolve/main/dw-ll_ucoco_384_bs5.torchscript.pt || echo "WARN dwpose"

mkdir -p "$ROOT/templates" "$COMFY/input" "$COMFY/output"

# ------------------------------------------------------------------ report ----
echo
echo "=== inventory ==="
du -sh "$COMFY/models"/*/ 2>/dev/null | sort -h
df -h "$ROOT" | tail -1
echo
if [ ${#FAILED[@]} -gt 0 ]; then
    echo "!!! ${#FAILED[@]} DOWNLOAD(S) FAILED:"
    printf '    %s\n' "${FAILED[@]}"
    echo "    Re-run this script to retry only those."
else
    echo "All models present."
fi
echo "=== provision done $(date -u +%FT%TZ) ==="
