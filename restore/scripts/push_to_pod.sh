#!/usr/bin/env bash
# Push the local configuration onto a fresh pod. Run from the project root:
#
#   bash backend/restore/push_to_pod.sh root@1.2.3.4 -p 12345
#
# Everything after the host is passed through to ssh/scp, so use the exact
# port and key flags RunPod gives you for the new pod.
#
# This copies only *our* files -- graphs, template clips, points, tools. Models
# are not pushed; they are downloaded on the pod (see RESTORE.txt, step 5).
set -euo pipefail

HOST="${1:?usage: push_to_pod.sh user@host [ssh flags...]}"; shift
SSH_FLAGS=("$@")
COMFY=/workspace/ComfyUI
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# scp wants -P for the port where ssh wants -p; translate rather than make the
# caller remember which is which.
SCP_FLAGS=(); for f in "${SSH_FLAGS[@]}"; do
  [ "$f" = "-p" ] && SCP_FLAGS+=("-P") || SCP_FLAGS+=("$f")
done

echo "==> checking the pod"
ssh "${SSH_FLAGS[@]}" "$HOST" "test -d $COMFY" \
  || { echo "no $COMFY on that pod -- do RESTORE.txt steps 1-5 first"; exit 1; }

echo "==> workflows"
ssh "${SSH_FLAGS[@]}" "$HOST" "mkdir -p /workspace/fy"
scp -q "${SCP_FLAGS[@]}" "$ROOT"/backend/workflows/*.json "$HOST:/workspace/fy/"

echo "==> template clips + points (into ComfyUI input, where VHS_LoadVideo reads)"
scp -q "${SCP_FLAGS[@]}" "$ROOT"/backend/templates/*.mp4 "$HOST:$COMFY/input/"
scp -q "${SCP_FLAGS[@]}" "$ROOT"/backend/templates/*.points.json "$HOST:/workspace/fy/" 2>/dev/null || true

echo "==> tools"
scp -q "${SCP_FLAGS[@]}" "$ROOT"/backend/tools/*.py "$HOST:/workspace/fy/"

echo
echo "Pushed. Remaining, on your machine:"
echo "  1. open the tunnel:  ssh -N -L 8188:127.0.0.1:8188 $HOST ${SSH_FLAGS[*]}"
echo "  2. point backend/.env COMFY_URL at http://127.0.0.1:8188"
echo "  3. verify:           curl -s http://127.0.0.1:8000/v1/health"
