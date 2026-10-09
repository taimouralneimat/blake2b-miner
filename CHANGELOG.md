# Changelog

## 1.5.1

Review round on the 1.4 and 1.5 changes.

- **Fixed: running the self-test (Diagnostics) while mining with the GPU only
  stopped the GPU.** The self-test now gets the hashing engine to itself only
  when nothing is mining. Mining that starts during a self-test waits for it,
  and stopping mining no longer stops a running self-test.
- **GPU errors are handled.** If the GPU reports an error, the miner backs off
  and retries instead of retrying in a tight loop, logs the problem once, and
  logs when the GPU recovers. A GPU that doesn't report timestamps no longer
  stops the load setting from working.
- The GPU engine's result buffers are allocated once when it starts (with a
  clear error if that fails), and a failed batch no longer loses a buffer.
- If CPU threads can't start, GPU mining still runs (and the other way round);
  stopping mining while it is starting up always stops everything that has
  started.
- Two copies of the app opened at the same moment no longer both quit: only
  the newer one does.
- Settings copied from a Mac with a GPU no longer leave a Mac without one
  unable to mine.
- The assembly kernel no longer uses the frame-pointer and link registers, so
  crash reports and profilers can always walk the stack. Hashrate is
  unchanged.
- `b2bminer`: `--gpu-load` without `--gpu` is an error instead of being
  ignored.
- Cleaned up the GPU engine (a clearer feeder loop, constants in one place)
  and the kernel generators.
- The dashboard chart no longer cuts off its last time label.
- README: a Performance section with measured CPU, GPU and combined
  hashrates and the best settings, new screenshots, and updated share-time
  estimates (also in docs/DATUM.md).

## 1.5.0

- **GPU mining.** The Mac's GPU can now mine too, with a Metal kernel: about
  760 MH/s on an M4 Pro, and about 1 GH/s together with the CPU (three times
  CPU-only). Settings › Performance has separate CPU and GPU sections:
  - **CPU:** on or off, and how many threads.
  - **GPU:** on or off, and how much of its time to use (10–100%). Below
    100%, the GPU works at full speed for that share of each quarter second
    and rests the rest of the time, so hashrate scales with the setting.
  - **Keep the Mac responsive** now applies to both: CPU mining at low
    priority, and the GPU's work in short bursts so animations and video stay
    smooth.
- The GPU and CPU threads search separate nonce ranges, and every GPU hit is
  re-checked on the CPU with the full hash before it is used. The self-test
  checks the GPU kernel against the reference hash, and the end-to-end test
  mines blocks with the GPU alone.
- The dashboard and menu show the CPU and GPU hashrates separately while the
  GPU mines. `b2bminer` has `--gpu`, `--no-cpu` and `--gpu-load`, and `bench`
  can measure the CPU, the GPU or both.
- Corrected the description of "Keep the Mac responsive": low-priority CPU
  mining runs mostly on the efficiency cores, which can halve the CPU
  hashrate. Before, it said "a small cost".

## 1.4.0

- **About twice the hashrate on Apple Silicon.** A new hand-written ARM64
  assembly kernel hashes two nonces in a NEON vector, using the SHA3
  extension's `XAR` instruction for BLAKE2b's xor-and-rotate, and a third in
  the integer units at the same time, with every value kept in a register.
  On a 12-core M4 Pro: about 320 MH/s, up from about 155 MH/s (35 MH/s per
  thread, up from 19). Every Apple Silicon Mac has the SHA3 extension; Intel
  Macs keep the portable C kernel.
- The self-test now checks all three lanes of both kernels against the
  reference BLAKE2b, and the log and `b2bminer bench` show which kernel is in
  use.

## 1.3.6

- **Fixed: two copies of the app could mine at the same time and fight.**
  Opening the app from a second location (for example a build folder found
  by Spotlight) started a second copy. Both started a DATUM Gateway on the
  same port and kept stopping each other's ("bind failed ... Address already
  in use", "PANIC"), and a settings change in one (such as the thread count)
  was undone by the other. Now:
  - A second copy of the app shows the running copy's dashboard and quits.
  - Only one miner (the app or `b2bminer`) mines per Mac at a time. Another
    one waits ("... is already mining on this Mac") and starts by itself
    when the first one stops.
- When the gateway's port is taken by another program, the app says so in
  plain words and suggests a fix, instead of showing the gateway's "PANIC"
  output.

## 1.3.5

- **A cleaner log.** For every new network block the gateway printed three
  lines; the log now shows one: "New network block 975723".
- The periodic hashrate line in the log, in the app and the CLI, now includes
  your share count in DATUM mode too, not only for pool-hosted gateways, with
  solo shares (mined while no pool is connected) counted separately.
- **Safer storage of solved blocks.** If a solved block can't be saved to
  disk (for example, the disk is full), the app now logs the block with its
  full hex instead of losing it silently or crashing.
- **Safer Keychain handling.** The RPC password is updated in place instead
  of deleted and re-added, and a Keychain that can't be read at launch (for
  example, while locked) is no longer overwritten with an empty password.
- Overview: the session card combines the running time, threads and
  priority, which evens out the grid. The chart's last time label is no
  longer cut off at the right edge, and small hash counts no longer show as
  "0.00".
- The log footer counts only blocks found on the real chain (like the
  Overview), with correct singular and plural.
- A pool fee of "See website" is now the link itself instead of appearing
  next to a separate "Website" link.
- CLI: `--port` and `--stratum-port` must be valid port numbers. `check
  --pool` rejects unknown pools and accepts `none` (it used to accept any
  pool name without complaint). `bench` rejects zero threads or seconds.

## 1.3.4

- **Fixed: shares that never reached the pool were counted as pool shares.**
  While a DATUM pool isn't connected (for example right after starting, or
  while it reconnects), your gateway mines solo at difficulty 1, so a share
  can arrive within seconds. The app counted those as accepted shares. Now
  *Shares* counts only shares sent to the pool; solo ones show separately
  ("+N solo"), and every share in the log states its difficulty and whether
  it was solo work. (Solo work is still useful: a block found then pays you
  in full.)
- Stratum connections give up after 15 seconds instead of hanging, and use
  TCP keepalive to notice dead connections.
- Messages that arrive while mining is paused (on battery) no longer pile
  up without limit.
- The "Changes apply when mining restarts" banner now compares against the
  settings mining actually started with. Before, it compared against the
  settings when the page was opened, so it could disappear even though
  changes were still pending.
- Pool usernames in the form `address.workername` no longer show a format
  warning.

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
