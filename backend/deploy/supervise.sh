#!/usr/bin/env bash
# Keep ComfyUI and the Funny You API up, without anybody watching.
#
# The API already restarts ComfyUI when a render dies against it, and the GPU
# lock means two jobs can no longer stack their weights and get the container
# OOM-killed. This is the layer under both: whatever the reason a process is
# gone -- a crash, an out-of-memory kill, a pod reboot -- something notices
# within half a minute and starts it again.
#
# Deliberately a polling loop over a process supervisor. There is no systemd
# in these containers, the two services are the only things being watched, and
# a loop that anyone can read and kill is worth more here than a daemon that
# needs its own explanation.
#
#   nohup bash /workspace/funnyyou-api/backend/deploy/supervise.sh \
#       >> /workspace/supervise.log 2>&1 &
set -uo pipefail

API_DIR="${API_DIR:-/workspace/funnyyou-api/backend}"
API_PORT="${API_PORT:-8888}"
COMFY_PORT="${COMFY_PORT:-8188}"
API_LOG="${API_LOG:-/workspace/api.log}"
RESTART_COMFY="${RESTART_COMFY:-$API_DIR/deploy/comfy_restart.sh}"
INTERVAL="${INTERVAL:-30}"

say() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

listening() {
    ss -ltn 2>/dev/null | grep -qE "[^0-9]${1}[^0-9]"
}

start_api() {
    say "starting the API on 0.0.0.0:${API_PORT}"
    cd "$API_DIR" || return 1
    nohup python -m uvicorn app.main:app \
        --host 0.0.0.0 --port "$API_PORT" \
        >>"$API_LOG" 2>&1 &
}

start_comfy() {
    say "starting ComfyUI"
    bash "$RESTART_COMFY"
}

say "supervisor up: watching ComfyUI :${COMFY_PORT} and the API :${API_PORT}"

while true; do
    # ComfyUI first. The API reports itself unready without it, and starting
    # them the other way round makes the first health check a lie.
    if ! curl -sf -m 5 -o /dev/null "http://127.0.0.1:${COMFY_PORT}/system_stats"; then
        say "ComfyUI is not answering"
        start_comfy
    fi

    # The API is checked on the port rather than on /v1/health, because it
    # answers 503 whenever ComfyUI is down. That is the API working correctly
    # and reporting a true fact; restarting it would fix nothing.
    if ! listening "$API_PORT"; then
        say "the API is not listening"
        start_api
        sleep 10
    fi

    sleep "$INTERVAL"
done
