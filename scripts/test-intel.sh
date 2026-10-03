#!/bin/sh
# Runs the Intel (x86_64) build under Rosetta on an Apple Silicon Mac.
#
# It tests the per-architecture build outputs (the exact code that
# build-app.sh merges into the app), never the copies inside the app bundle:
# running Intel code from the bundle makes macOS warn that the app "includes a
# component that will not work with a future release of macOS". The build
# outputs also keep their linker signature, which Rosetta translates reliably.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
[ "$(uname -m)" = arm64 ] || { echo "This test is for Apple Silicon Macs (Intel Macs run the Intel code natively)."; exit 0; }
/usr/bin/pgrep -q oahd || { echo "Rosetta is not installed (softwareupdate --install-rosetta)."; exit 1; }

swift build -c release --triple x86_64-apple-macosx13.0 --product b2bminer 2>&1 | grep -E "error|warning: " || true
MINER=.build/x86_64-apple-macosx/release/b2bminer
GATEWAY=build/datum/x86_64/gateway/datum_gateway

echo "== Intel b2bminer self-test (Rosetta)"
"$MINER" selftest
if [ -x "$GATEWAY" ]; then
    echo "== Intel datum_gateway (Rosetta)"
    "$GATEWAY" --version | grep -i datum_gateway
fi
