# Changelog

## 1.3.3

- **Fixed: blocks found through a DATUM pool with anti-block-withholding
  (ABW), such as DXPool, were not recorded.** The gateway announces those as
  "revealed a verified block key for candidate …" rather than "BLOCK FOUND";
  both are now recognized.
- **Fixed: if a pool failed to act on one of your blocks**, the gateway's
  "CRITICAL ABW FAILURE" error appeared 8 times. It now becomes a single
  clear alert.
- If a found block can't be checked because the node is unreachable, the
  record now says that (instead of "not in your node's chain").
- Internal: the gateway's output handling is a standalone parser, covered by
  a new self-test check. Long functions in the node check and the gateway
  supervision were split up, solo template parsing is separate from block
  building, and the `blockmaxweight` limit is defined once.

## 1.3.2

- **Fixed: a DATUM pool could keep dropping the connection for minutes.**
  After a disconnect the gateway tried to resume its old pool session, the
  pool declined and reset the connection, and this could repeat every ~13
  seconds, so shares couldn't reach the pool. The app now detects repeated
  resets and restarts its gateway for a fresh session (at most once every
  5 minutes). If the pool still won't hold the connection, the menu and
  dashboard say so and suggest trying another DATUM pool.

## 1.3.1

- **Fixed: error flood when the node is unreachable.** While Bitcoin Knots
  was restarting or down, the DATUM Gateway logged "Could not fetch new
  template" every second. Now it's one plain message, and one more when the
  gateway is getting templates again. If it lasts more than 30 seconds, the
  menu and dashboard show "Waiting" instead of looking like normal mining.
- **Fixed: blocks found through the DATUM Gateway were not recorded.** The
  app now asks your node whether each one made it into the chain, and
  records it (with its chain) in *Blocks found* and `found-blocks.jsonl`.
  The gateway also saves every block it submits under
  `~/Library/Application Support/BLAKE2bMiner/datum/submitted-blocks`, so a
  block found while the node is unreachable can still be resubmitted.
- The end-to-end test restarts the node mid-mining and checks that mining
  recovers and every found block is recorded.

## 1.3.0

- **Dashboard window** with a sidebar (Overview, Mining, Performance, Node,
  Diagnostics, Log, About) replaces the separate Settings and Log windows
  and their tab bar. It can be resized and made **full screen**; while it's
  open the app appears in the Dock and the app switcher.
- **Overview page:** live hashrate, a one-hour hashrate chart, stat cards,
  pool connection, blocks found and recent activity.
- **Menu:** the bottom section is now native-style menu rows (Open Dashboard
  ⌘D, Settings… ⌘,, Quit ⌘Q) with a calmer header.
- Opening the app again while it runs (Finder, Spotlight) opens the
  dashboard; `--dashboard` opens it at launch.
- **Fixed:** blocks mined by the end-to-end test on a throwaway test chain
  were recorded in the user's real found-blocks file and shown as "blocks
  found". Tests now keep all their data separate, found blocks record their
  chain, and only main-chain blocks are counted. (Affected 1.0.0–1.2.0 for
  anyone who ran the tests on their machine.)
- Share difficulties display as whole numbers (16,384, not 16,383.75).

## 1.2.0

- **Redesigned menu:** a large hashrate, two tiles with what matters for
  your mode (next share for pools, expected block for solo), a status pill,
  and the "who builds the blocks" badge. When mining is waiting, one clear
  message with **Show Log** and **Run Checks**. A welcome with **Set Up…**
  on first use, which also opens Settings automatically the first time.
- **Settings reorganized** into General, Performance, Node, Diagnostics and
  About, in a fixed-size window that fits small screens (it used to grow
  taller than a laptop display).
- The payout address is checked as you type. Pool fees and websites have
  their own rows, and the gateway's advanced options are folded away.
- **Diagnostics:** one **Run All Checks** button, with results shown as icons.
- About shows the app icon, with links to the website, issue tracker and
  licenses.
- Clearer message when Bitcoin Knots can't be reached.
- For developers: `scripts/ui-snapshots.sh` renders every screen in light
  and dark mode; the UI lives in a `MinerUI` library.

## 1.1.2

- Fixed: starting to mine while the self-test was running could leave the
  miner stuck without hashing. It now waits for the test to finish.
- Fixed: `scripts/build-app.sh` could package a stale binary when a build
  failed.
- Solo mode checks the node's chain tip twice a second instead of five
  times. Each DATUM Gateway restart no longer leaks a pipe, and node RPC
  sessions are released.
- `b2bminer` rejects unknown options (a typo like `--adress` used to be
  ignored).
- No force-unwraps left in the code; the test vectors are parsed into typed
  models; the Log window keeps a stable identity for each line.
- README: troubleshooting, uninstall, the Keychain, and running DATUM mode
  from a source build.

## 1.1.1

- **Security:** the node RPC password is stored in the macOS Keychain
  (migrated automatically from earlier versions). The gateway configuration
  is private from the moment it's written. Stale gateway cleanup only stops
  a process verified to be our gateway (PID file, not a pattern match).
  `b2bminer` reads the RPC password from `B2B_RPC_PASSWORD`.
- **Reliability:** a solved block's submission is retried if the node is
  briefly unreachable. Invalid node or gateway addresses and ports show an
  error instead of crashing. Stratum accepts `[IPv6]:port`. The record of
  pending share submissions is bounded.
- **Native only:** the app always runs natively on Apple Silicon, warns if
  it's ever translated by Rosetta, and `scripts/test-intel.sh` tests the
  Intel build without triggering the macOS "will not work with a future
  release" warning.
- **Node check:** `b2bminer check`. It warns when RPC goes to a remote
  computer, and reads `blockmaxweight` written with spaces or a comment.
- Internal cleanup: a generic mining control loop, the DATUM gateway as a
  work source, shared constants, settings that survive version changes,
  smaller files. CI builds both architectures and runs the self-test.

## 1.1.0

- Your own DATUM Gateway, bundled and managed by the app, is the default:
  your node builds the blocks. Built-in DATUM pools: DXPool, Xor Pool,
  CONVOY, Tyger Pool.
- Every mode is labeled by who builds the blocks.

## 1.0.0

- First release: native BLAKE2b engine, solo mining with a Knots node,
  Stratum client with pool-hosted gateway presets, built-in self-test.
