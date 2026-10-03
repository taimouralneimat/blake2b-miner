# DATUM in BLAKE2b Miner

[DATUM](https://github.com/CONVOYMining/datum_gateway) is how miners pool
**without giving up block building**. A DATUM Gateway next to your own Bitcoin
Knots node builds every block template from your node's mempool and policy. It
talks to a DATUM pool over an encrypted, authenticated protocol, and the pool
only coordinates who gets paid, straight from the coinbase. Miners connect to
the gateway over Stratum.

```
BLAKE2b Miner ──Stratum──▶ your DATUM Gateway ──DATUM──▶ DATUM pool
                                 │
                        your Knots node (builds the blocks)
```

## The built-in gateway

BLAKE2b Miner ships the CONVOY DATUM Gateway inside the app
(`Contents/MacOS/datum_gateway`, built by `scripts/build-datum-gateway.sh`). In
*My own DATUM Gateway* mode the app:

- writes the gateway configuration to
  `~/Library/Application Support/BLAKE2bMiner/datum/gateway.json`: your node's
  RPC address and cookie (or user/password), your payout address, and the
  chosen pool's host, port and public key;
- starts the gateway, restarts it if it exits, and stops it when mining stops
  or the app quits;
- mines through it on `127.0.0.1:23334` with your payout address as the Stratum
  username. The gateway passes that address to the pool for your payouts;
- shows the pool connection state, and forwards the gateway's warnings and
  errors to the app's log.

With *None* as the pool, the gateway mines solo: blocks pay 100% to your
payout address, and the gateway's minimum share difficulty is 1, so the
miner's share counter shows activity about every 30 seconds.

### Built-in pools

| Pool | Server | Public key (first 16 hex digits) |
| --- | --- | --- |
| DXPool | `xbt.datum.dxpool.com:28915` | `13dceb1f532408e8…` |
| Xor Pool | `datum.xorpool.com:28915` | `b83aedbba54ba2aa…` |
| CONVOY | `datum-beta1.mine.convoy.xyz:28915` | `dbb11fa0c2b5403e…` |
| Tyger Pool | `tygerpool.com:28915` | `8918e6a6437f9238…` |

The full keys are in `Sources/MinerCore/Pools.swift`, copied from each
pool's published setup instructions. Each pool was checked by completing the
DATUM handshake with the bundled gateway from a mainnet node, and receiving
work built from that node's template. Pools are refused on test chains.

### Node settings for pooled DATUM

Add to `bitcoin.conf` and restart Knots:

```
blockmaxweight=785000
```

This leaves room in each block for the pool's payout outputs. **Settings ›
Diagnostics › Run All Checks** checks it.

## Using a gateway you run yourself

If you already run a DATUM Gateway, for example on another machine for your
ASICs, choose *Pool-hosted gateway* in Settings › General, pick *Custom server*, and enter the
gateway's Stratum address (e.g. `192.168.1.10:23334`) with your payout
address as the username.

### Share difficulty

A gateway's `stratum.vardiff_min` sets the minimum share difficulty, and a
DATUM pool can raise it (all four built-in pools use 16,384). At difficulty *D* a share takes about *D* × 2³² hashes on average,
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
