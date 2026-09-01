#!/usr/bin/env bash
# Stage 1 of the head-replacement pipeline: Qwen-Image-Edit 2509.
#
#   bash /workspace/install_qwen_edit.sh
#
# Why this model
# --------------
# The product needs a customer's whole head — face *and hair* — on the template
# performer's costume. Face swap (ReActor/inswapper) cannot do it: it repaints
# the inner face onto the template's head, so the hair, hairline and head shape
# stay the performer's. Three renders confirmed that.
#
# Wan 2.2 Animate *can* carry a full appearance, but it drives a reference
# image, and a reference of the customer in their own clothes produces exactly
# that — the superhero test came back in a plain shirt.
#
# So the reference still has to already show the customer wearing the costume.
# Qwen-Image-Edit 2509 takes two images (template frame + customer photo) and
# transfers the head between them while leaving the costume intact. One image,
# not 200 frames, so it can afford to be slow and good. Apache-2.0, which also
# sidesteps the inswapper_128 non-commercial problem if this ever ships paid.
#
# Wan then animates that still with the template's motion — and Wan is already
# installed, so stage 2 costs nothing new.
#
# Budget ~29 GB. With the 36 GB of Wan weights already present the volume must
# be at least 100 GB; on a 60 GB volume this will fail part-way through.

set -uo pipefail
M=/workspace/ComfyUI/models
export PIP_CACHE_DIR=/workspace/.cache/pip HF_HOME=/workspace/.cache/huggingface

echo "=== free space before ==="
df -h /workspace | tail -1

B=https://huggingface.co/Comfy-Org/Qwen-Image-Edit_ComfyUI/resolve/main/split_files

MODELS=(
  "diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors|$B/diffusion_models/qwen_image_edit_2509_fp8_e4m3fn.safetensors"
  "text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors|$B/text_encoders/qwen_2.5_vl_7b_fp8_scaled.safetensors"
  "vae/qwen_image_vae.safetensors|$B/vae/qwen_image_vae.safetensors"
)

FAILED=()
for entry in "${MODELS[@]}"; do
    dest="${entry%%|*}"; url="${entry#*|}"
    path="$M/$dest"
    mkdir -p "$(dirname "$path")"

    # A truncated file loads and then fails deep in the sampler, which reads as
    # a workflow bug rather than a bad download. Treat small files as absent.
    if [ -f "$path" ] && [ "$(stat -c%s "$path")" -gt 100000000 ]; then
        echo "    have $(basename "$dest") ($(du -h "$path" | cut -f1))"
        continue
    fi
    echo "    GET $(basename "$dest")"
    if curl -fL --retry 3 --retry-delay 5 -o "$path" "$url"; then
        echo "    OK  $(du -h "$path" | cut -f1)"
    else
        echo "    FAIL $dest"; rm -f "$path"; FAILED+=("$dest")
    fi
done

echo
echo "=== free space after ==="
df -h /workspace | tail -1
du -sh "$M"/{diffusion_models,text_encoders,vae} 2>/dev/null

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "!!! ${#FAILED[@]} FAILED — re-run to retry only those:"
    printf '    %s\n' "${FAILED[@]}"
else
    echo "All Qwen-Image-Edit models present."
fi
