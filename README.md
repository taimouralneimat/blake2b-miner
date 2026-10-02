# BLAKE2b Miner

A fast CPU miner for macOS for the **Bitcoin Knots BLAKE2b chain** (header v2
proof of work, live since block 961,640). It runs as a small menu-bar app,
and also ships a command-line tool.

- **Solo mining with your own Bitcoin Knots node.** The miner gets block
  templates from your node, and any block you find pays the full reward to
  your address.
- **Pools, one click.** Built-in presets for pools that run public DATUM
  gateways ([DXPool](https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/),
  [Xor Pool](https://xorpool.com) US/EU/Asia over TLS), or connect to your own
  [DATUM Gateway](https://github.com/CONVOYMining/datum_gateway).
- **Runs on any Mac with macOS 13 Ventura or later**: one universal app for
  Apple Silicon and Intel. No Python, Xcode or other dependencies.
- **Fast native engine**: about 150–180 MH/s on a 12-core M4 Mac mini, roughly
  14× faster than looping over the node's built-in `generatetoaddress`.
- **Verifiable**: built-in self-test against the official Knots test vectors
  and against real blocks from your node.

> **Be realistic.** A CPU is a tiny fraction of the network's hashrate. At
> 150 MH/s and difficulty 4.6 G, the expected time to solo-mine one block is
> thousands of years. Think of it as a lottery ticket that also supports the
> network's decentralization, not as income.

## Install

1. Download `BLAKE2bMiner-<version>-macOS.dmg` (or `.zip`) from
   [Releases](../../releases) and drag **BLAKE2b Miner** to Applications.
2. Open it. The release builds aren't notarized by Apple, so the first time
   macOS will say it can't verify the developer:
   - macOS 15 and later: click **Done**, then open **System Settings ›
     Privacy & Security**, scroll down and click **Open Anyway**.
   - macOS 13–14: right-click the app, choose **Open**, then **Open**.

   Or run this in Terminal once:
   `xattr -dr com.apple.quarantine "/Applications/BLAKE2b Miner.app"`
3. A cube icon appears in the menu bar. Click it, then **Settings…**

## Set up solo mining

You need [Bitcoin Knots](https://bitcoinknots.org) 29.4.1 or later, fully
synced on the BLAKE2b chain, with its RPC server enabled:

- **Bitcoin Knots app (Bitcoin-Qt):** Settings › Options › check **Enable
  RPC server**, then restart Knots. Or add `server=1` to `bitcoin.conf`.
- **bitcoind:** add `server=1` to `bitcoin.conf`.

Then, in BLAKE2b Miner:

1. **Settings › Mining:** choose *Solo with my Knots node*, and paste a payout
   address from your own wallet (in Knots: Receive › Create new receiving
   address).
2. **Settings › Verify › Test Node Connection** should show green checks:
   connected, BLAKE2b templates, valid address, and an address that belongs
   to your wallet.
3. Click **Start Mining** in the menu.

The miner signs in to the node with its cookie file from the default data
directory (`~/Library/Application Support/Bitcoin`). If your node uses another
data directory or `rpcuser`/`rpcpassword`, set them in **Settings › Node**.

## Mine with a pool

In **Settings › Mining** choose *Pool or DATUM Gateway*, pick a pool, and
enter your payout address as the username (optionally `address.workername`).
**Test Server** checks the connection and authorization, and that the pool
sends work this miner understands, all without mining.

| Pool | Server | Notes |
| --- | --- | --- |
| [DXPool](https://www.dxpool.net/help/en/tutorial/dxpool-datum-gateway-mining/) | `xbt.public-gateway-01.dxpool.com:23334` | Public DATUM gateway, pays from the coinbase |
| [Xor Pool](https://xorpool.com) | `stratum+ssl://datum.xorpool.com:23337` (also `eu.` and `hk.`) | TLS; 2% fee on pool-built blocks |

These pools set the share difficulty for ASICs (16,384 at the time of
writing), so a Mac at 150 MH/s finds a share about **once every 5 days**. Pool
payouts follow shares, so expect tiny, rare payouts. Other BLAKE2b pools
(Tyger, Omega, Blockvase, AlphaPool's DATUM pool, and Lazarus at 0% fee) work
through your own DATUM Gateway: point the gateway at the pool, and the miner at
the gateway.

## Mine through your own DATUM Gateway

Run the [CONVOY DATUM Gateway](https://github.com/CONVOYMining/datum_gateway)
next to your Knots node (see its README). Then in **Settings › Mining** choose
*Pool or DATUM Gateway*, pick *My own DATUM Gateway / custom*, and set:

- **Server:** the gateway's Stratum address, e.g. `127.0.0.1:23334`
- **Username:** your payout address (for pooled mining), or any worker name

The gateway decides where block rewards go (pooled or `mining.pool_address`).
Its default minimum share difficulty (`stratum.vardiff_min`, 1024) is set for
ASICs; at CPU speed that means a share every few hours. A lower `vardiff_min`
gives more frequent shares. See [docs/DATUM.md](docs/DATUM.md) for details.

## Settings worth knowing

| Setting | What it does |
| --- | --- |
| Threads | How many CPU cores to use (default: all). |
| Keep the Mac responsive | Runs the hashing at lower priority; slightly less hashrate. |
| Pause while on battery power | On by default for MacBooks. |
| Prevent the Mac from sleeping | Keeps mining while the Mac is idle. |
| Open at login / Start mining when the app opens | Unattended operation. |

Logs are in `~/Library/Logs/BLAKE2bMiner/`. Every solved block is saved with
its full data in `~/Library/Application Support/BLAKE2bMiner/found-blocks.jsonl`,
so it can be resubmitted by hand if needed.

## Command-line tool

The app bundle contains `b2bminer`, for terminals, servers and scripts:

```sh
B="/Applications/BLAKE2b Miner.app/Contents/MacOS/b2bminer"
"$B" solo --address <your address>                 # solo mine with your local node
"$B" stratum --url 127.0.0.1:23334 --user <name>   # mine to a DATUM Gateway or pool
"$B" pools                                         # list built-in pool presets
"$B" probe --url <host:port> --user <address>      # test a pool without mining
"$B" selftest --node                               # verify hashing (and against your node)
"$B" bench                                         # measure this Mac's hashrate
"$B" --help
```

## How it works

The BLAKE2b proof of work ([Knots PR #359](https://github.com/bitcoinknots/bitcoin/pull/359),
`CBlockHeader::GetHash()` in `src/primitives/block.cpp`) hashes a 164-byte
header in layers: tagged SHA-256 commitments, then a first BLAKE2b, then a final
BLAKE2b over an 80-byte input. Only the final BLAKE2b depends on the nonces.
The miner computes everything else once per block template. Each CPU thread
then sweeps its own range of `nonce2`/`nNonce` values, running three
interleaved BLAKE2b compressions at a time. The round-0 work that doesn't
depend on the nonce is precomputed, and a quick check on the first output word
rejects almost every nonce before any full comparison.

In solo mode, before mining a template, the miner asks the node to validate
the complete block (`getblocktemplate` proposal mode, which checks everything
except proof of work). Before submitting a solution, it re-checks the hash with
an independent reference implementation.

| Source | Contents |
| --- | --- |
| `Sources/CEngine` | Hashing engine (C), portable BLAKE2b, generated 3-lane kernel |
| `Sources/MinerCore` | Header v2 hashing, node RPC, solo block building, Stratum/DATUM client, self-test |
| `Sources/BLAKE2bMinerApp` | SwiftUI menu-bar app |
| `Sources/b2bminer` | Command-line tool |
| `scripts/` | App packaging, kernel generator, end-to-end tests |

## Build from source

Requires macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`);
the full Xcode is not needed.

```sh
swift build -c release                     # app + CLI for this Mac
.build/release/b2bminer selftest
scripts/build-app.sh                       # universal .app, .zip and .dmg in dist/
```

### Tests

```sh
.build/release/b2bminer selftest --node    # vectors, engine, and your node's recent blocks
scripts/test-e2e.sh                        # mines real blocks on a throwaway regtest chain
DATUM_GATEWAY=/path/to/datum_gateway scripts/test-e2e.sh   # ...and through a real DATUM Gateway
```

`test-e2e.sh` starts a private regtest Knots node with BLAKE2b active, mines
blocks in solo mode, and checks that every block is accepted and includes
mempool transactions. With `DATUM_GATEWAY` set, it also runs a real CONVOY
DATUM Gateway in front of the node and mines through it over Stratum.

## License

MIT. See [LICENSE](LICENSE). The header-v2 test vectors come from Bitcoin Knots
(MIT).
