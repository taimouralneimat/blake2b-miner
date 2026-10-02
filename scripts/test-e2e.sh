#!/bin/sh
# End-to-end test on a throwaway regtest chain with BLAKE2b active.
# Never touches your real node or wallet.
#
#   1. solo mode: b2bminer mines blocks from a regtest Knots node's templates
#   2. DATUM mode (if DATUM_GATEWAY is set): a real CONVOY DATUM Gateway sits
#      between the node and b2bminer's Stratum client
#
# Requirements: Bitcoin Knots 29.4.1+ binaries (bitcoind, bitcoin-cli).
#   KNOTS_BIN=/path/to/knots/bin        (default: found on PATH or in common places)
#   DATUM_GATEWAY=/path/to/datum_gateway (optional; enables the DATUM test)
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MINER="$ROOT/.build/release/b2bminer"
TMP=$(mktemp -d)
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

if [ -z "${DATUM_GATEWAY:-}" ]; then
    echo "== 2/2 DATUM mode skipped (set DATUM_GATEWAY=/path/to/datum_gateway)"
    echo "All end-to-end tests passed."
    exit 0
fi

echo "== 2/2 DATUM mode via $(basename "$DATUM_GATEWAY")"
POOL_ADDR=$($CLI getnewaddress "" legacy)
cat > "$TMP/datum.json" <<EOF
{
  "bitcoind": { "rpccookiefile": "$TMP/regtest/.cookie", "rpcurl": "http://127.0.0.1:$RPCPORT", "work_update_seconds": 5 },
  "stratum": { "listen_addr": "127.0.0.1", "listen_port": $STRATUM_PORT, "vardiff_min": 1, "idle_timeout_no_shares": 0 },
  "mining": { "pool_address": "$POOL_ADDR", "coinbase_tag_primary": "e2e test" },
  "api": { "listen_port": 0 },
  "logger": { "log_to_console": true, "log_level_console": 2 },
  "datum": { "pool_host": "", "pooled_mining_only": false }
}
EOF
"$DATUM_GATEWAY" -c "$TMP/datum.json" > "$TMP/datum.log" 2>&1 &
PID=$!; PIDS="$PIDS $PID"
for _ in $(seq 50); do nc -z 127.0.0.1 $STRATUM_PORT 2>/dev/null && break; sleep 0.2; done
START=$($CLI getblockcount)
"$MINER" stratum --url 127.0.0.1:$STRATUM_PORT --user "$POOL_ADDR" --no-battery-pause > "$TMP/stratum.log" 2>&1 &
MPID=$!; PIDS="$PIDS $MPID"
# At DATUM's minimum share difficulty a share needs ~2^32 hashes (~30 s at 150 MH/s).
# Allow up to 10 minutes for slower Macs or a busy CPU.
for _ in $(seq 600); do
    [ "$($CLI getblockcount)" -ge $((START + 2)) ] && break
    sleep 1
done
stop_pid $MPID
END=$($CLI getblockcount)
ACC=$(grep -c "Share accepted" "$TMP/stratum.log" || true)
REJ=$(grep -c "Share rejected" "$TMP/stratum.log" || true)
PAID=$($CLI getblock "$($CLI getblockhash $END)" 2 | grep -c "$POOL_ADDR" || true)
if [ "$END" -le "$START" ] || [ "$ACC" -lt 1 ] || [ "$REJ" -ne 0 ] || [ "$PAID" -lt 1 ]; then
    echo "--- miner log"; cat "$TMP/stratum.log"
    echo "--- gateway log"; tail -40 "$TMP/datum.log"
    echo "FAIL: DATUM mode (height $START -> $END, shares accepted $ACC, rejected $REJ, paid $PAID)"
    exit 1
fi
echo "   ok: $((END - START)) blocks found through DATUM, $ACC shares accepted, 0 rejected, coinbase pays the gateway's address"
echo "All end-to-end tests passed."
