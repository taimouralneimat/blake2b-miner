#!/bin/sh
# End-to-end test on a throwaway regtest chain with BLAKE2b active.
# Never touches your real node or wallet.
#
#   1. solo mode: b2bminer mines blocks from a regtest Knots node's templates
#   2. DATUM mode: `b2bminer datum` starts its own CONVOY DATUM Gateway next to
#      the node and mines through it, as the app does
#
# Requirements: Bitcoin Knots 29.4.1+ binaries (bitcoind, bitcoin-cli).
#   KNOTS_BIN=/path/to/knots/bin        (default: found on PATH or in common places)
#   DATUM_GATEWAY=/path/to/datum_gateway (default: build/datum/datum_gateway from
#                                         scripts/build-datum-gateway.sh)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MINER="$ROOT/.build/release/b2bminer"
TMP=$(mktemp -d)
# Everything the miner writes (found blocks, gateway config) stays in the
# test's own directory, never in the user's real app data.
export B2B_DATA_DIR="$TMP/appdata"
RPCPORT=28600
STRATUM_PORT=28601

find_knots() {
    for d in "${KNOTS_BIN:-}" "$(dirname "$(command -v bitcoind 2>/dev/null || echo /x/x)")" \
             "$HOME/Applications/BitcoinKnots/bin" /Applications/Bitcoin-Qt.app/Contents/MacOS /opt/homebrew/bin /usr/local/bin; do
        if [ -n "$d" ] && [ -x "$d/bitcoind" ] && [ -x "$d/bitcoin-cli" ]; then echo "$d"; return; fi
    done
    echo "Bitcoin Knots bitcoind/bitcoin-cli not found; set KNOTS_BIN" >&2
    exit 1
}
BIN=$(find_knots)
CLI="$BIN/bitcoin-cli -regtest -datadir=$TMP -rpcport=$RPCPORT"
PIDS=""

cleanup() {
    for p in $PIDS; do kill "$p" 2>/dev/null || true; done
    $CLI stop >/dev/null 2>&1 || true
    sleep 1
    rm -rf "$TMP"
}
trap cleanup EXIT

stop_pid() {
    kill -TERM "$1" 2>/dev/null || true
    for _ in $(seq 40); do kill -0 "$1" 2>/dev/null || return 0; sleep 0.25; done
    echo "FAIL: process $1 did not exit on SIGTERM"
    exit 1
}

[ -x "$MINER" ] || (cd "$ROOT" && swift build -c release --product b2bminer)

echo "== starting regtest Knots node ($BIN)"
"$BIN/bitcoind" -regtest -datadir="$TMP" -daemon -listen=0 -rpcport=$RPCPORT -fallbackfee=0.0001 \
    -testactivationheight=blake2b@5 >/dev/null
for _ in $(seq 100); do [ -f "$TMP/regtest/.cookie" ] && break; sleep 0.1; done
$CLI -rpcwait createwallet test >/dev/null
ADDR=$($CLI getnewaddress "" legacy)
$CLI generatetoaddress 110 "$ADDR" >/dev/null
for _ in 1 2 3; do $CLI sendtoaddress "$($CLI getnewaddress)" 1.5 >/dev/null; done

echo "== 1/2 solo mode"
START=$($CLI getblockcount)
"$MINER" solo --address "$ADDR" --port $RPCPORT --datadir "$TMP" --threads 2 --no-battery-pause > "$TMP/solo.log" 2>&1 &
PID=$!; PIDS="$PIDS $PID"
sleep 8
stop_pid $PID
END=$($CLI getblockcount)
ACC=$(grep -c "accepted$" "$TMP/solo.log" || true)
REJ=$(grep -c "rejected" "$TMP/solo.log" || true)
NTX=$($CLI getblock "$($CLI getblockhash $((START + 1)))" | sed -n 's/.*"nTx": \([0-9]*\).*/\1/p')
if [ "$END" -le "$START" ] || [ "$ACC" -lt 1 ] || [ "$REJ" -ne 0 ] || [ "$NTX" -ne 4 ]; then
    cat "$TMP/solo.log"
    echo "FAIL: solo mode (height $START -> $END, accepted $ACC, rejected $REJ, first block nTx $NTX)"
    exit 1
fi
echo "   ok: $((END - START)) blocks mined and accepted, first one with $((NTX - 1)) mempool transactions"

GATEWAY=${DATUM_GATEWAY:-$ROOT/build/datum/datum_gateway}
if [ ! -x "$GATEWAY" ]; then
    echo "== 2/2 DATUM mode skipped (run scripts/build-datum-gateway.sh, or set DATUM_GATEWAY)"
    echo "All end-to-end tests passed."
    exit 0
fi

echo "== 2/2 DATUM mode: b2bminer runs its own gateway ($GATEWAY)"
POOL_ADDR=$($CLI getnewaddress "" legacy)
START=$($CLI getblockcount)
B2B_DATUM_GATEWAY="$GATEWAY" "$MINER" datum --pool none --address "$POOL_ADDR" --port $RPCPORT \
    --datadir "$TMP" --stratum-port $STRATUM_PORT --no-battery-pause > "$TMP/datum.log" 2>&1 &
MPID=$!; PIDS="$PIDS $MPID"
# At the gateway's minimum share difficulty a share needs ~2^32 hashes (~30 s at 150 MH/s).
# Allow up to 10 minutes for slower Macs or a busy CPU.
for _ in $(seq 600); do
    [ "$($CLI getblockcount)" -ge $((START + 2)) ] && break
    sleep 1
done
sleep 3  # let the gateway's replies to the last shares arrive

echo "   restarting the node while mining (the gateway must notice and recover)"
$CLI stop >/dev/null
for _ in $(seq 60); do $CLI getblockcount >/dev/null 2>&1 || break; sleep 1; done
# The gateway asks for a new template about every 40 s; wait until it notices.
for _ in $(seq 120); do grep -q "Can't get block templates" "$TMP/datum.log" && break; sleep 1; done
grep -q "Can't get block templates" "$TMP/datum.log" || {
    cat "$TMP/datum.log"; echo "FAIL: the outage was never reported"; exit 1; }
[ "$(grep -c "Can't get block templates" "$TMP/datum.log")" -eq 1 ] || {
    echo "FAIL: the outage was reported more than once"; exit 1; }
sleep 5
"$BIN/bitcoind" -regtest -datadir="$TMP" -daemon -listen=0 -rpcport=$RPCPORT -fallbackfee=0.0001 \
    -testactivationheight=blake2b@5 >/dev/null
for _ in $(seq 120); do grep -q "Getting block templates from your node again" "$TMP/datum.log" && break; sleep 1; done
grep -q "Getting block templates from your node again" "$TMP/datum.log" || {
    cat "$TMP/datum.log"; echo "FAIL: the gateway did not recover after the node restarted"; exit 1; }
RESTART_HEIGHT=$($CLI -rpcwait getblockcount)
for _ in $(seq 300); do [ "$($CLI getblockcount)" -gt "$RESTART_HEIGHT" ] && break; sleep 1; done
[ "$($CLI getblockcount)" -gt "$RESTART_HEIGHT" ] || { echo "FAIL: no block mined after the node restart"; exit 1; }
echo "   ok: the gateway recovered and mining continued after the node restart"
SAVED=$(ls "$B2B_DATA_DIR/datum/submitted-blocks" 2>/dev/null | wc -l | tr -d ' ')
[ "$SAVED" -ge 1 ] || { echo "FAIL: the gateway saved no submitted blocks"; exit 1; }
echo "   ok: $SAVED block submission(s) saved to disk by the gateway"
stop_pid $MPID
FOUND=$(grep -o "BLOCK FOUND - [0-9a-f]\{64\}" "$TMP/datum.log" | sort -u | wc -l | tr -d ' ')
RECORDED=$(grep '"chain":"regtest"' "$B2B_DATA_DIR/found-blocks.jsonl" | grep -vc blockHex || true)
if [ "$FOUND" -lt 1 ] || [ "$RECORDED" -ne "$FOUND" ]; then
    echo "FAIL: the gateway found $FOUND block(s) but $RECORDED were recorded"
    exit 1
fi
echo "   ok: all $FOUND block(s) found through the gateway are recorded with their chain"
pgrep -f "$TMP/appdata/datum" >/dev/null && { echo "FAIL: gateway still running after the miner stopped"; exit 1; }
END=$($CLI getblockcount)
ACC=$(grep -c "Share accepted" "$TMP/datum.log" || true)
# A share found just as the chain moves on is rejected as stale; that's normal
# mining (on regtest two threads can solve the same height). Anything else fails.
REJ=$(grep "Share rejected" "$TMP/datum.log" | grep -vc "stale" || true)
PAID=$($CLI getblock "$($CLI getblockhash $END)" 2 | grep -c "$POOL_ADDR" || true)
if [ "$END" -le "$START" ] || [ "$ACC" -lt 1 ] || [ "$REJ" -ne 0 ] || [ "$PAID" -lt 1 ]; then
    cat "$TMP/datum.log"
    echo "FAIL: DATUM mode (height $START -> $END, shares accepted $ACC, rejected $REJ, paid $PAID)"
    exit 1
fi
echo "   ok: $((END - START)) blocks built by the node, mined through the app-managed gateway; $ACC shares accepted, none rejected as invalid; coinbase pays the payout address"
echo "All end-to-end tests passed."
