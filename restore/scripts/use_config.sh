#!/usr/bin/env bash
# Switch the live pipeline between the saved configurations.
#
#   bash restore/scripts/use_config.sh A     # verified, but has the beard bug
#   bash restore/scripts/use_config.sh B     # mask fixed, never rendered
#   bash restore/scripts/use_config.sh       # show which one is live now
#
# Each config folder is a complete set, so this is a straight copy in both
# directions -- there is no partial state to get stuck in.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIGS="$ROOT/restore/configs"

resolve() {
  case "$1" in
    A|a) echo "$CONFIGS/A-verified-but-has-beard-bug" ;;
    B|b) echo "$CONFIGS/B-mask-fixed-but-untested" ;;
    *)   echo "" ;;
  esac
}

# No argument: report which config the live files match, byte for byte.
if [ $# -eq 0 ]; then
  live=$(sha256sum "$ROOT/backend/workflows/wan_animate.json" | cut -d' ' -f1)
  for key in A B; do
    dir=$(resolve "$key")
    want=$(sha256sum "$dir/wan_animate.json" | cut -d' ' -f1)
    [ "$live" = "$want" ] && { echo "live config: $key  ($(basename "$dir"))"; exit 0; }
  done
  echo "live config: NEITHER -- backend/workflows/wan_animate.json has been edited"
  echo "  restore one with: bash restore/scripts/use_config.sh A"
  exit 0
fi

DIR=$(resolve "${1}")
[ -n "$DIR" ] || { echo "usage: use_config.sh [A|B]"; exit 1; }

cp "$DIR/wan_animate.json"       "$ROOT/backend/workflows/wan_animate.json"
cp "$DIR/reactor_boost.json"     "$ROOT/backend/workflows/reactor_boost.json"
cp "$DIR/reactor_image_swap.json" "$ROOT/backend/workflows/reactor_image_swap.json"
cp "$DIR/pirate.points.json"     "$ROOT/backend/templates/pirate.points.json"

echo "now live: $(basename "$DIR")"
echo "restart the backend so it re-reads the graphs, then check:"
echo "  curl -s http://127.0.0.1:8000/v1/health"
