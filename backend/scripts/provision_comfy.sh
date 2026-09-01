#!/usr/bin/env bash
#
# Provision ComfyUI + Wan 2.2 Animate on a fresh GPU box.
#
# This is the client's install list, hardened: it fails loudly instead of
# half-installing, skips downloads that already exist (so re-running is cheap),
# and does NOT start the server — that is the container's job.
#
#   Disk needed: ~75 GB.   Time: 20-40 min on a fast pod.
#
# Usage:
#   bash provision_comfy.sh [install_dir]        # default /workspace

set -euo pipefail

ROOT="${1:-/workspace}"
COMFY="$ROOT/ComfyUI"

log()  { printf '\033[1;35m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# Download only if the file is missing and non-empty. Model files are tens of
# gigabytes; re-downloading them on every boot is the single biggest waste in
# a naive setup.
fetch() {
  local url="$1" dest="$2"
  if [[ -s "$dest" ]]; then
    log "exists, skipping: $(basename "$dest")"
    return 0
  fi
  log "downloading $(basename "$dest")"
  wget -q --show-progress -O "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

log "Installing system packages"
apt-get update -qq
apt-get install -y -qq git wget ffmpeg libgl1 libglib2.0-0

log "Cloning ComfyUI into $COMFY"
mkdir -p "$ROOT"
if [[ ! -d "$COMFY/.git" ]]; then
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "$COMFY"
fi
cd "$COMFY"

log "Installing PyTorch (CUDA 12.8) — pinned, must come before requirements"
pip install --no-cache-dir \
  torch==2.7.0 torchvision==0.22.0 torchaudio==2.7.0 \
  --index-url https://download.pytorch.org/whl/cu128

log "Installing ComfyUI requirements"
pip install --no-cache-dir -r requirements.txt

log "Installing sageattention (optional speed-up)"
pip install --no-cache-dir sageattention || \
  warn "sageattention failed to build — continuing without it (slower sampling)"

log "Installing custom nodes"
mkdir -p custom_nodes && cd custom_nodes
[[ -d ComfyUI-Manager ]]  || git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager
[[ -d Civicomfy ]]        || git clone --depth 1 https://github.com/MoonGoblinDev/Civicomfy
# Wan 2.2 Animate graphs need KJNodes + the video helper for frame I/O.
[[ -d ComfyUI-KJNodes ]]  || git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes
[[ -d ComfyUI-VideoHelperSuite ]] || \
  git clone --depth 1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite

for node in */; do
  [[ -f "$node/requirements.txt" ]] && \
    pip install --no-cache-dir -r "$node/requirements.txt" || true
done
cd "$COMFY"

log "Downloading models (~70 GB)"
HF="https://huggingface.co"

mkdir -p models/{diffusion_models,loras,vae,clip_vision,text_encoders,detection}

fetch "$HF/Kijai/WanVideo_comfy_fp8_scaled/resolve/main/Wan22Animate/Wan2_2-Animate-14B_fp8_e5m2_scaled_KJ.safetensors" \
      "models/diffusion_models/Wan2_2-Animate-14B_fp8_e5m2_scaled_KJ.safetensors"

fetch "$HF/Kijai/WanVideo_comfy/resolve/main/Lightx2v/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors" \
      "models/loras/lightx2v_T2V_14B_cfg_step_distill_v2_lora_rank256_bf16.safetensors"

fetch "$HF/Kijai/WanVideo_comfy/resolve/main/LoRAs/Wan22_relight/WanAnimate_relight_lora_fp16.safetensors" \
      "models/loras/WanAnimate_relight_lora_fp16.safetensors"

fetch "$HF/Kijai/WanVideo_comfy/resolve/main/Wan2_1_VAE_bf16.safetensors" \
      "models/vae/Wan2_1_VAE_bf16.safetensors"

fetch "$HF/laion/CLIP-ViT-H-14-laion2B-s32B-b79K/resolve/main/model.safetensors" \
      "models/clip_vision/CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors"

fetch "$HF/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp16.safetensors" \
      "models/text_encoders/umt5_xxl_fp16.safetensors"

fetch "$HF/JunkyByte/easy_ViTPose/resolve/main/onnx/wholebody/vitpose-l-wholebody.onnx" \
      "models/detection/vitpose-l-wholebody.onnx"

fetch "$HF/Wan-AI/Wan2.2-Animate-14B/resolve/main/process_checkpoint/det/yolov10m.onnx" \
      "models/detection/yolov10m.onnx"

log "Done. Start ComfyUI with:"
echo "  cd $COMFY && python main.py --listen 0.0.0.0 --port 8188"
