# Changelog

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
