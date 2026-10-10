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

| Pool | Server | Min. share difficulty | Public key (first 16 hex digits) | Live status |
| --- | --- | --- | --- | --- |
| Lazarus | `datum.lazarus-xbt.xyz:28915` | 1,024 | `29120606bbbfdeb0…` | `https://pool.lazarus-xbt.xyz/api/pool` |
| Omega Pool | `omegapool.tech:28915` | 1,024 | `e0af9254ca56f936…` | `https://omegapool.tech/stats.json` |
| RIPTIDE | `riptide.maveth.ca:29120` | 2,048 | `b95abf4a11050c51…` | `https://tides.maveth.ca/api/stats` |

The full keys are in `Sources/MinerCore/Pools.swift`, from each pool's
published setup instructions or status API. Each was checked on 2026-10-10:

- **Blocks:** it found blocks in the previous 1,008 (about 7 days), by its
  tag in the coinbase.
- **Difficulty:** it completed the encrypted DATUM handshake with the
  bundled gateway from a mainnet node, sent work built from that node's
  template, and set the minimum share difficulty shown.
- **Status:** it publishes live pool status.

Pools that didn't meet the rules were removed. A saved choice of one is kept
as a custom pool, with a note:

| Pool | Why it's no longer built in |
| --- | --- |
| DXPool | Rejected a valid share, built no block through DATUM in the week, difficulty 16,384, 25% fee shown for small miners |
| CONVOY | Difficulty 16,384 |
| Xor Pool, Tyger Pool | No blocks in the week |
| AlphaPool (never built in) | Difficulty 16,384, and `blockmaxweight=740000` |

Any other DATUM pool can be added in the app (**Mining › DATUM pool › Add a
pool…**) or with `b2bminer datum --pool-host <host[:port]> --pool-key <hex>`.
The public key is required: the bundled gateway won't connect to a pool
without one. Pools are refused on test chains.

### The pool's verdict on your shares

Your gateway checks each share first and forwards it to the pool, which
checks it again. The app's log shows both: "Share accepted by your gateway,
sent to Lazarus", then "Lazarus accepted your share", or "Lazarus rejected
your share: <reason> (code N)". The **Shares** count shows only shares the
pool accepted. (The gateway logs the pool's verdicts at debug level, so the
app runs it at that level and reads just those lines.)

### Node settings for pooled DATUM

Add to `bitcoin.conf` and restart Knots:

```
blockmaxweight=785000
```

This leaves room in each block for the pool's payout outputs. **Dashboard ›
Diagnostics › Run All Checks** checks it.

## Using a gateway you run yourself

If you already run a DATUM Gateway, for example on another machine for your
ASICs, choose *Pool-hosted gateway* on the dashboard's Mining page, pick *Custom server*, and enter the
gateway's Stratum address (e.g. `192.168.1.10:23334`) with your payout
address as the username.

### Share difficulty

A gateway's `stratum.vardiff_min` sets the minimum share difficulty, and a
DATUM pool can raise it (all four built-in pools use 16,384). At difficulty *D* a share takes about *D* × 2³² hashes on average,
so on a 12-core M4 Pro:

| Share difficulty | CPU only (~300 MH/s) | CPU + GPU (~1 GH/s) |
| --- | --- | --- |
| 16,384 (the built-in pools) | ~2.6 days | ~20 hours |
| 1024 | ~4 hours | ~1.2 hours |
| 64 | ~15 minutes | ~5 minutes |
| 1 | ~15 seconds | ~4 seconds |

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
