#!/usr/bin/env bash
# Run this ON A HEALTHY POD to capture everything needed to rebuild it.
#
#   bash capture_pod_state.sh > pod_state.txt
#
# Then copy pod_state.txt down to backend/restore/. It records the exact custom
# node commits, package versions and model files that a working render depends
# on -- the things RESTORE.txt can only describe from memory.
#
# Nothing here writes or deletes; it is safe to run on a live pod mid-project.
set -u
COMFY="${COMFY:-/workspace/ComfyUI}"

echo "=== captured $(date -u +%FT%TZ) ==="
echo "=== gpu ==="
nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null

echo; echo "=== container memory limit (the 62GB ceiling that OOM-kills renders) ==="
cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null
echo "oom kills so far:"; grep -E '^oom' /sys/fs/cgroup/memory.events 2>/dev/null

echo; echo "=== disk ==="
df -h /workspace / 2>/dev/null

echo; echo "=== python ==="
python --version 2>&1
python -c "import torch;print('torch',torch.__version__,'cuda',torch.version.cuda,'avail',torch.cuda.is_available())" 2>&1

echo; echo "=== comfyui commit ==="
git -C "$COMFY" log -1 --format='%H %ci %s' 2>/dev/null

echo; echo "=== custom nodes: folder | remote | commit ==="
for d in "$COMFY"/custom_nodes/*/; do
  [ -d "$d/.git" ] || { echo "$(basename "$d") | (no git) |"; continue; }
  printf '%s | %s | %s\n' "$(basename "$d")" \
    "$(git -C "$d" config --get remote.origin.url 2>/dev/null)" \
    "$(git -C "$d" rev-parse HEAD 2>/dev/null)"
done

echo; echo "=== which pack provides each node class (authoritative) ==="
cd "$COMFY" && python - <<'PY' 2>/dev/null
import sys, os
sys.argv = ["main.py"]
try:
    import nodes
    nodes.init_extra_nodes()
except Exception as exc:
    print("could not import nodes:", exc); raise SystemExit
for name, cls in sorted(nodes.NODE_CLASS_MAPPINGS.items()):
    mod = sys.modules.get(cls.__module__)
    path = getattr(mod, "__file__", "?") or "?"
    marker = "custom_nodes" + os.sep
    pack = path.split(marker)[1].split(os.sep)[0] if marker in path else "CORE"
    print(f"{name} | {pack}")
PY

echo; echo "=== models on disk ==="
find "$COMFY/models" -type f \( -name '*.safetensors' -o -name '*.pth' -o -name '*.pt' \
     -o -name '*.onnx' -o -name '*.ckpt' -o -name '*.bin' \) \
     -printf '%10s  %p\n' 2>/dev/null | sort -k2

echo; echo "=== pip freeze ==="
pip freeze 2>/dev/null

echo; echo "=== how comfyui was launched ==="
ps -eo args | grep -E "[m]ain\.py" || echo "(not running)"
