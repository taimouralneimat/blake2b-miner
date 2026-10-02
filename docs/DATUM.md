# Mining through a DATUM Gateway

The [CONVOY DATUM Gateway](https://github.com/CONVOYMining/datum_gateway)
connects mining hardware to your own Bitcoin Knots node. It builds block
templates from your node with `getblocktemplate`, can pool through a DATUM
server, and serves work to miners over Stratum v1 (port 23334 by default).
BLAKE2b Miner's **Pool or DATUM Gateway** mode is a Stratum client for that
work.

## Setup

1. Install and configure the gateway following its README, pointed at your
   Knots node (`bitcoind.rpcurl`, cookie or user/password).
2. Make sure the Stratum port is reachable from the Mac running the miner.
   It's `127.0.0.1:23334` when both run on the same Mac.
3. In BLAKE2b Miner, **Settings › Mining › Pool or DATUM Gateway**, pick *My own DATUM Gateway / custom*:
   - Server: `127.0.0.1:23334` (or the gateway's address)
   - Username: your payout address for pooled mining, or a worker name
   - Password: anything (`x`)

The menu then shows accepted and rejected shares and the share difficulty set
by the gateway.

### Share difficulty

The gateway's `stratum.vardiff_min` (default 1024) is the minimum share
difficulty. At difficulty *D* a share takes about *D* × 2³² hashes on average,
so at 150 MH/s:

| vardiff_min | Average time per share |
| --- | --- |
| 1024 | ~8 hours |
| 64 | ~30 minutes |
| 1 | ~30 seconds |

Shares only affect pooled payouts and the gateway's statistics. Every share is
checked against the real network target, so a share that is also a block is
always submitted, whatever the share difficulty.

### Solo mining through the gateway

With `"datum": {"pool_host": ""}` (and `"pooled_mining_only": false`), the
gateway mines solo and pays 100% of any block to `mining.pool_address`.

## Protocol details

Work is the gateway's "Sia-style" BLAKE2b Stratum, which carries the last
stage of the header-v2 proof of work:

```
mining.subscribe        -> [subscriptions, extranonce1 (4 bytes), extranonce2_size (8)]
mining.set_difficulty   [difficulty]
mining.notify           [job_id, prevhash, coinb1, coinb2, merkle_branch, version, nbits, ntime, clean_jobs]
  prevhash  32-byte hidden previous-block value, raw hex
            (tagged SHA-256 of the previous block hash, first 6 bytes zeroed)
  coinb1    39 bytes: 3 zero bytes, the 32-byte header commitment (h2), 4 zero bytes
  coinb2    empty;  merkle_branch: []
  nbits     compact share target
  ntime     8 bytes, raw hex: time_offset (4) | nonce3 (4)

root  = BLAKE2b-256(0x00 || coinb1 || extranonce1 || extranonce2 || coinb2)
input = prevhash || nonce (8) || ntime (8) || root          (80 bytes)
hash  = BLAKE2b-256(input), compared as a big-endian number to the target

mining.submit           [username, job_id, extranonce2, ntime, nonce]   (all raw hex)
```

This matches `datum_blake2b_*` in the gateway's `src/datum_pow.c` and
`client_mining_submit` in `src/datum_stratum.c`. `scripts/test-e2e.sh` checks it
end to end against a real gateway on a regtest chain.
