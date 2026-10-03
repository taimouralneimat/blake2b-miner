# Changelog

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
