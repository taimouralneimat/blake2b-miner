#!/bin/sh
# Renders every screen of the app (light and dark) to PNGs for UI review.
# Usage: scripts/ui-snapshots.sh [output-dir]   (default: build/ui-snapshots)
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
OUT=${1:-$ROOT/build/ui-snapshots}
cd "$ROOT"
swift build -c release --product UISnapshots 2>&1 | grep -E "error|warning: " || true
rm -rf "$OUT"
.build/release/UISnapshots "$OUT"
