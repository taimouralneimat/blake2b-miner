# Changelog

## Unreleased

- **Restart Now is always in reach.** After you change a setting, the
  "Your changes apply when mining restarts" bar stays pinned at the bottom
  of the window on every page, instead of sitting at the end of a long page
  (⌘R works too).
- **A shorter Performance page:** CPU and GPU are one *Hardware* section,
  power and startup options are one section, and the notes are shorter.
  The automatic-updates switch is on the About page, where it already was.

- **The Rabid Pool trial has ended.** Its share difficulty (16,384) means
  about one share a day from a Mac: in two days of testing there was no
  accepted share, so its promise to carry small amounts couldn't be checked,
  and its website and statistics were unreachable on 2026-10-25. If you
  joined the test, Rabid stays in your pools with that note, and nothing is
  switched for you; the Pools page shows the pools that credit a Mac.

- **The responsive schedule says what it's doing and why.** Settings shows,
  for example, "Full power: Saturday isn't one of your days (Sun–Thu)" or
  "Full power: outside 9:00–midnight", and the log records the schedule and
  its current state when mining starts. Days are summarized as ranges
  ("Sun–Thu"), and midnight is written as "midnight", not "0:00".

## 1.10.0

**Pools: only the ones that pay a Mac, and only where your node builds the blocks.**

- **RIPTIDE removed (rule 4).** Tested with a Mac for two days: 11 accepted
  shares, 7 RIPTIDE blocks, and the Mac's part of each (about 180 sats,
  under the 546-sat dust limit) was neither paid nor recorded as owed. If
  you chose it, it stays chosen with a note explaining why.
- **B2Pool no longer suggested.** It's pool-hosted, so the pool's node
  builds the blocks; the app now only suggests pools where your own node
  builds them. If you mine with it, nothing changes.
- **Pools under evaluation.** The Pools page has a new section for pools being
  tested on a real Mac before they're built in, with what's being tested and
  a **Join the Test** button. First: Rabid Pool (about 2% of the network),
  which carries amounts under its 2,000-sat floor to the next block. Its
  owed, maturing and paid amounts appear in Earnings.
- Lazarus, now about 29% of the network and the only pool verified to credit
  a Mac, is marked *Large* with that explanation rather than *Not
  recommended* with no alternative.

**New:**

- **Keep the Mac responsive on a schedule.** Never, Always, or On a
  schedule: say 9:00–17:00 on the days you pick, responsive while you use
  the Mac and full power the rest of the time. Mining switches at the
  boundaries without stopping (CPU priority and GPU burst length change in
  place). From a terminal: `--responsive-hours 9:00-17:00 [--responsive-days mon-fri]`.
- **"A DATUM Gateway on another Mac"** replaces the pool-hosted mode: a
  second Mac mines through your first Mac's gateway, so your node builds its
  blocks too. The "who builds the blocks" badge follows the address: your
  network means you; a server elsewhere means that server's node.

**Fixes and polish:**

- **A payout address must pass its checksum before mining starts**, in the
  app and in `b2bminer`, instead of failing later in the gateway or the node.
- **Keep the Mac awake while mining is on for new installs** (mains power
  only; the display still turns off). Existing settings keep your choice.
- **A stuck pool session is restarted.** When a pool rejects the first 3
  shares of a session and accepts none, the app restarts your DATUM Gateway
  for a fresh session (at most every 5 minutes). Seen with RIPTIDE: every
  share got code 30 until the pool reconnected, then all were accepted. Code
  30 is no longer blamed only on an outdated Knots.
- **A cleaner experience:** the first screen has one path (Set Up…, then Run
  Checks); the default pool's size is information, not an orange warning;
  notes on retired pools no longer recommend other retired pools; shorter
  explanations in Performance.
- `b2bminer --pool <retired pool>` explains why it was retired and how to use
  it anyway; `b2bminer pools` lists pools under evaluation.

## 1.9.2

- **Omega Pool removed: it doesn't pay miners as small as a Mac.** By
  design, its server leaves any miner whose part of a block would be under
  546 sats out of that block's payout, which keeps every payout above the
  dust limit, and amounts aren't carried over (RATUM's `MIN_PAYOUT`,
  `prime/src/ledger/split.rs`). A Mac at about 1 GH/s gets
  about 55 sats a block there, so it is never paid: measured, 17 accepted
  shares and 0 sats. 1.8.3 wrongly said smaller amounts were "owed and paid
  later", and 1.9.0 made Omega the default for new installs. Sorry.
  - If you chose Omega, it stays chosen (as a custom pool) with a warning in
    Mining settings, so your mining doesn't change without you. Switch to
    Lazarus or RIPTIDE in Mining settings.
  - Its account section in Earnings now says plainly that your part is under
    the minimum and isn't carried over.
  - New installs start with Lazarus again: it credits small amounts and
    carries them until its 500,000-sat minimum (measured: about 900 sats a
    day at 1 GH/s).
- **A fourth rule for built-in pools: it must credit a small miner's work**,
  not drop it. Pools are re-checked every 4 weeks (next: 2026-11-07); a pool
  that fails is removed from the built-in list but stays chosen for anyone
  using it, with a warning. Suggest a pool to evaluate via GitHub issues.

## 1.9.1

- **Fixed: a Mac that had gone to sleep mined at about half speed.** "Keep
  the Mac awake while mining" stopped the Mac from falling asleep, but if it
  was already asleep (or slept while the app was closed), macOS woke it only
  for short maintenance windows and sent it back to sleep: measured, one
  night at about 450 MH/s instead of 1.04 GH/s. The app now also holds the
  system awake the way `caffeinate -s` does, on mains power. The display can
  still turn off, and Sleep in the Apple menu still works.
- `b2bminer` mining commands keep the Mac awake too (on mains power); add
  `--allow-sleep` to let it sleep.

## 1.9.0

- **Faster GPU: about +2% (762 → 778 MH/s on an M4 Pro).** The 64-bit adds and
  the rotate by 24 now let Metal's compiler pick the instructions, which it
  does better than the hand-split 32-bit halves; rotations by 16 and 63 keep
  the halves, which measured faster for them. Chosen from all 16 combinations,
  each checked against the reference. With 12 CPU threads the total rises from
  about 985 MH/s to 1.01 GH/s.
- **Payout addresses are checked with their checksum** (bech32, bech32m and
  base58check), so a mistyped character is caught as you type instead of
  "Looks valid". DATUM mining also asks the node to validate the address
  before starting the gateway.
- **New installs start with Omega Pool**, under 20% of the network and paying
  from 546 sats; removing a custom pool falls back to it. Existing settings
  don't change.
- Fixed: when a pool changed the share difficulty mid-job, the CPU threads and
  the GPU searched the job's nonces again from the start (wasted work, and
  possible duplicate shares). They now carry on where they were.
- Fixed: log lines and status updates from the miner could reach the app out
  of order.
- Fixed: a wallet whose name contains "/" couldn't be read for Earnings.
- Diagnostics accepts a watch-only payout address, like Earnings does.
- B2Pool is recognized however its server address is written
  (`stratum+tcp://…`, upper case), for pool statistics and the Pools page.
- The gateway's folder, which holds its configuration and can hold the RPC
  password, is made private (0700) even when it already existed; a custom
  pool's website only opens as an http(s) link.

## 1.8.6

- Earnings: pools you aren't mining with no longer refresh on their own.
  Each shows when it was last checked and has a **Check Now** button; the
  built-in pools are asked about your address once (again only if your
  address changes). Refresh covers your wallet and the pool you mine with.
- **Pools above 20% of the network are "Not recommended".** BLAKE2b Miner
  is here for decentralization: the Pools page says so, and Mining settings
  warns when the chosen pool is that large, with a link to compare pools.

## 1.8.5

- **Earnings: every pool, not just the current one.** The page shows the
  pool you mine with first (refreshed every 5 minutes), then every other
  pool that knows your address, with what it last reported: a pool you left
  can still owe you (Lazarus carries amounts under its 500,000-sat minimum).
  Those are asked again when you open the page, at most every 6 hours, or
  with Refresh. The app finds them by asking the built-in pools about your
  address, and remembers each pool you mine with. A total shows what the
  pools owe you.
- Omega Pool: what it owes you from earlier blocks, and why it isn't paying
  you yet when it says (for example, under its 546-sat minimum).
- Payouts in your wallet were already counted from every pool; the pools'
  sections now come right after the totals.

## 1.8.4

- **Fixed: Omega Pool rejected shares with "reason unknown (code 43)".**
  Omega runs the RATUM pool server, which refuses a share whose work doesn't
  include the pool's payout outputs once it sent them more than 10 s before.
  The DATUM Gateway waits at most 5 s for those outputs; when they come
  later (as right after connecting) it sends the work without them and only
  replaces it at its next work update, every 40 s. Pooled work is now
  refreshed every 10 s. RATUM's codes 40-44 are explained in words.
- Fixed: 1.8.3 labelled a share at the pool's own difficulty (1,024) as
  "below the pool's share difficulty" when the pool announced 1,023.98, and
  counted it as solo.

## 1.8.3

- **Fixed: the pool's accepted shares were undercounted.** When the pool
  dropped the connection, the app restarts your DATUM Gateway, and each
  restart set the count of the pool's verdicts back to zero while shares
  sent kept counting (so "17 sent, 6 accepted" when the pool had accepted
  all 17). The counts now cover the whole mining session.
- **Fixed: shares counted as sent to the pool when they weren't.** A
  "connection reset" now marks the pool as disconnected, so shares mined
  then are counted as solo; a share below the pool's difficulty is never
  counted as sent; and shares the pool dropped when it declined to resume a
  session are counted as lost instead of "waiting for its answer" forever.
- **Amounts in sats.** Below 0.01 BTC (every pool payout at Mac hashrates)
  amounts read "1,108 sats" instead of "0.00001108 BTC", in the app and
  `b2bminer`; the Earnings chart is in sats.
- **Payout terms on the Pools page:** Lazarus pays from 500,000 sats and
  carries smaller amounts over, Omega Pool from 546 sats; RIPTIDE and B2Pool
  pay in the coinbase with no published minimum. Also in `b2bminer pools`.
- **Lazarus's share count explained:** "in the payout window (about the
  last 5 h)". The window holds the pool's most recent work; older shares
  have left it after earning their part.
- **Earnings: 6,481 confirmations for every payout.** Knots 29.4.2 doesn't
  relay a spend of any mined coins younger than 6,480 blocks, whatever
  height they were mined at (as consensus, the rule covers blocks 973,440 to
  979,919).

## 1.8.2

- **Pool statistics checked field by field against each pool's live API.**
  Lazarus: shows what you're owed below its 0.005 BTC payout minimum (it
  carries small amounts forward), and "No recent shares" instead of "Not
  seen recently" (one share an hour is normal for a Mac). RIPTIDE: its
  lifetime total is "Earned in total", not "Paid", and the Pools page uses
  its reported hashrate share (1.2%) instead of an estimate from blocks
  found, which its luck had inflated. B2Pool: adds your share of the window
  and what a pool block would pay you now. The menu no longer says "sees
  0.00 H/s" or "0.00% of the window".
- **Earnings: the 45-day maturity is enforced.** A payout counts as
  spendable only after 6,481 confirmations (101 before block 973,440), even
  if the wallet says otherwise; maturing payouts show "N of 6,481
  confirmations" and the date they become spendable.
- **Fixed: no notification for your first payout.** New payouts are now
  found by transaction, so the first one notifies too, and changing your
  address doesn't trigger a false one.
- **Fixed: some waits stayed on "Starting…".** Waiting for another miner on
  this Mac, for the self-test, or with both CPU and GPU off now shows its
  reason right away, and the 5-minute alert works for these too.
- Pools page: **Use This Pool** keeps your address when switching from a
  pool-hosted gateway, and offers **Restart Now** while mining.
- Earnings: each payout's status sits on its own line.
- `scripts/test-e2e.sh`: the node-outage stage waits for the node to exit
  and allows more time, so it no longer fails on a busy Mac.

## 1.8.1

- **Fixed: Lazarus share count.** The pool account showed accepted
  difficulty as the number of shares (1,024 for one share at difficulty
  1,024). It now shows the share count; a tiny window share reads "under
  0.0001%" instead of "0.0000%".

## 1.8.0

- **Earnings page.** Payouts to your address, read from your own node's
  wallet: each payout and whether it's maturing, spendable or orphaned, the
  totals, and a chart of what you've earned. It works with any pool and
  solo, without trusting a pool's numbers. It also shows the pool's view of
  your address. From a terminal: `b2bminer earnings --address <addr>`.
- **Pools page.** Each built-in pool's live share of the network's hashrate,
  its miners, fee and share difficulty. Pools above a fifth of the network
  are marked Large and the smallest is marked, to help spread the hashrate;
  **Use This Pool** switches. From a terminal: `b2bminer pools --sizes`.
- **Notifications** for the pool's first accepted share, 5 rejected shares in
  a row, mining waiting for work for 5 minutes, an outdated Knots, and a new
  payout (besides blocks found).
- **Ready for Developer ID signing and notarization.** Builds now always use
  the hardened runtime; `scripts/build-app.sh` signs, notarizes, staples and
  checks with Gatekeeper when given a Developer ID (see docs/RELEASING.md).
  Once releases are signed that way, the updater only installs updates from
  the same developer.
- The GPU asks macOS to treat its work as latency-critical, so its short
  batches aren't delayed while the app is in the background.

## 1.7.0

- **Your account at the pool, on the dashboard.** For each built-in pool the
  app reads the pool's public statistics for your payout address every 5
  minutes while mining: whether it sees you online, the hashrate it measures,
  your shares, your share of the payout window, what a pool block would pay
  you now, the daily estimate, and unpaid, maturing and paid amounts (each
  where the pool reports it). Supported: Lazarus, Omega Pool, RIPTIDE and
  B2Pool. The menu shows a one-line summary. From a terminal: `b2bminer
  account --pool lazarus --address <addr>`.
- **Warns when Bitcoin Knots is too old.** From block 973,440 newly mined
  coins must wait 45 days, a rule added in Knots 29.4.2. An older node builds
  blocks the network rejects, and pools refuse shares built on them (Lazarus
  answers with code 30). Diagnostics now fails on Knots older than 29.4.2, and
  mining shows a warning. The pool-rejection message for code 30 now explains
  this instead of "reason unknown".
- **Opens at login again after updates.** Each release is signed anew, and
  macOS could then quietly stop opening the app at login. The app now
  registers its login item again after an update.
- "<pool> accepted your share" lines are green in the log.

## 1.6.0

- **Fixed: mining against a standard Stratum pool found no shares.** The app
  read the share target from the job's `nbits` field, which only DATUM
  gateways use for it. A standard pool server sends the network's target
  there and sets the share difficulty with `mining.set_difficulty`, so the
  app was mining at full block difficulty. The share target now comes from
  the pool's difficulty. Verified against B2Pool: 7 of 7 shares accepted in
  90 seconds at difficulty 1.
- **New built-in pools, chosen by three rules:** the pool found blocks in the
  last 7 days (checked on the chain), accepts low-difficulty shares, and
  publishes live status.
  - DATUM: **Lazarus** (difficulty 1,024, 0% fee through your own gateway),
    **Omega Pool** (1,024, 0.5%) and **RIPTIDE** (2,048, 0% coinbase fee). At
    about 1 GH/s that's roughly a share every 75 minutes, against one a day
    at 16,384.
  - Pool-hosted: **B2Pool**, six regions, share difficulty from 1.
  - Removed: DXPool (it rejected a valid share, built no block through DATUM
    in the week, required difficulty 16,384 and showed a 25% fee for small
    miners), CONVOY (difficulty 16,384), and Xor Pool and Tyger Pool (no
    blocks in the week). A saved choice of a removed pool is kept as a custom
    pool with a note, so nothing changes without you.
- **Add any DATUM pool yourself:** Mining › DATUM pool › Add a pool…, with
  its server and public key. `b2bminer datum` takes `--pool-host` and
  `--pool-key`.
- **The pool's own verdict on every share.** In DATUM mode your gateway
  accepts a share, then forwards it to the pool. The app now shows both
  steps: "Share accepted by your gateway, sent to Lazarus", then "Lazarus
  accepted your share", or "rejected your share: <reason> (code N)".
  **Shares** counts only shares the pool accepted, and the dashboard warns if
  the pool rejects your shares and accepts none. Before, a share your gateway
  accepted was counted as "accepted by the pool", even when the pool
  rejected it.
- **Check for updates.** At launch and once a day, the app asks GitHub for
  the latest release and offers **Install Update**. The app downloads it,
  verifies it against the release's SHA256SUMS.txt and checks it's this app
  at the version offered, then swaps it in place and reopens. You can also
  check from the About page, and turn the automatic checks off. In the CLI:
  `b2bminer version --check`.
- The self-test also checks the pool-difficulty share targets and the
  parsing of the pool's verdicts.

## 1.5.3

- **A new logo and app icon:** a Mac display with an orange block (a
  blockchain block) on its screen, struck by a hammer. The menu-bar icon
  matches: a small display with a block, solid while mining and outlined
  when stopped (before: a cube). The logo is generated by
  `scripts/gen_logo.py`, and the app icon is rendered from it.
- CI checks that every generated file is up to date: the C, assembly and
  Metal kernels and the logo (before: only the C kernel).
- Code cleanup with no change in behavior: `MinerConfig` has its own file,
  miner start-up is split into steps, and the self-test owns the GPU
  reference check. The README is updated to match.

## 1.5.2

Ten rounds of measurement on a 12-core M4 Pro (CPU and GPU otherwise idle).

- **Faster GPU in responsive mode on 60 Hz displays.** The GPU's short bursts
  are now half a frame of the fastest connected display (4–8 ms) instead of
  always 4 ms: about +10% GPU hashrate with *Keep the Mac responsive* on a
  60 Hz display (641 → 704 MH/s). 120 Hz displays keep 4 ms bursts.
- **Corrected the advice: use all CPU threads with the GPU.** Since 1.5.1 the
  GPU keeps its full speed next to 12 CPU threads, and 12 threads + GPU is the
  fastest setup (about 1.03 GH/s). The README and the app no longer suggest
  leaving CPU cores free.
- The end-to-end test always runs this Mac's native build. After an app
  build, `.build/release` points at the Intel build, so the test could run it
  under Rosetta.
- Measured and kept unchanged, because nothing was faster:
  - GPU threadgroup size (32–1024) and nonces per GPU thread (4–64): flat.
  - Bit-field-insert, 64-bit and 16-bit-swizzle rotations: same speed or up
    to 10% slower.
  - Moving nonce-independent work out of the GPU loop: the compiler already
    does it.
  - The assembly hybrid is also the fastest kernel on the efficiency cores.
  - *Keep the Mac responsive* (low priority) is the only CPU mode that leaves
    other apps at full speed. Lowering relative priority instead keeps them
    at about 70%.

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
