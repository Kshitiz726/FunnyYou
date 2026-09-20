#!/usr/bin/env bash
# Put ComfyUI back. Safe to run when it is already up, already down, or wedged.
#
# This is what COMFY_RESTART_CMD points at. The API runs it after a render
# fails against a server that has stopped answering, then waits for health and
# tries the render once more. It is also how supervise.sh starts ComfyUI in
# the first place, so there is only one description of "how ComfyUI is run".
#
# Never uses `pkill -f`. A pattern like "ComfyUI/main.py" also matches the ssh
# command line that is running this script, so pkill takes down its own shell
# and the restart looks like a connection drop. Kill by what owns the port.
set -uo pipefail

PORT="${COMFY_PORT:-8188}"
COMFY_DIR="${COMFY_DIR:-/workspace/ComfyUI}"
LOG="${COMFY_LOG:-/workspace/comfy.log}"

say() { echo "[comfy-restart] $*"; }

# --- stop whatever holds the port ----------------------------------------
holder() {
    ss -ltnp 2>/dev/null \
        | grep -E "[^0-9]${PORT}[^0-9]" \
        | sed -n 's/.*pid=\([0-9]*\).*/\1/p' \
        | head -1
}

pid="$(holder)"
if [ -n "$pid" ]; then
    say "stopping pid $pid on port $PORT"
    kill "$pid" 2>/dev/null
    for _ in $(seq 1 20); do
        [ -z "$(holder)" ] && break
        sleep 1
    done
    pid="$(holder)"
    if [ -n "$pid" ]; then
        say "pid $pid ignored SIGTERM, forcing"
        kill -9 "$pid" 2>/dev/null
        sleep 2
    fi
fi

# --- start it again -------------------------------------------------------
if [ ! -d "$COMFY_DIR" ]; then
    say "no ComfyUI at $COMFY_DIR, nothing to start"
    exit 1
fi

say "starting ComfyUI on 127.0.0.1:$PORT"
cd "$COMFY_DIR" || exit 1
nohup python main.py \
    --listen 127.0.0.1 \
    --port "$PORT" \
    --disable-auto-launch \
    >>"$LOG" 2>&1 &

# Return only once it is answering, so the caller can retry immediately
# instead of guessing how long a cold start takes.
for _ in $(seq 1 90); do
    if curl -sf -m 3 -o /dev/null "http://127.0.0.1:${PORT}/system_stats"; then
        say "up"
        exit 0
    fi
    sleep 2
done

say "did not come up within 180s"
exit 1
