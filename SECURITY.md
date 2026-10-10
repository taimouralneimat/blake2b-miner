# Security

## What BLAKE2b Miner protects

- **Payouts.** In solo mode the coinbase pays the address you set, and your
  node validates every block before any hashing. With DATUM, each built-in
  pool's public key is pinned (`Sources/MinerCore/Pools.swift`), so the
  bundled gateway only talks to the real pool. A server that impersonates
  the pool can't complete the encrypted handshake.
- **Node credentials.** The cookie file is read from your Knots data
  directory and never stored. An RPC password you enter goes into the macOS
  Keychain, not the preferences file. The gateway configuration that has to
  contain it (`~/Library/Application Support/BLAKE2bMiner/datum/gateway.json`)
  is created readable by your user only (mode 0600, in a 0700 directory).
- **Network exposure.** The bundled gateway listens on 127.0.0.1 only, unless
  you turn on *Let other miners on my network use this gateway*. Its web
  dashboard is disabled.
- **Custom pools.** A DATUM pool you add needs its public key too: the
  bundled gateway refuses to connect without one, so a pool's identity is
  always checked, never trusted on first use.
- **Updates.** The app only downloads releases of this repository from
  `github.com/taimouralneimat/blake2b-miner/releases` over HTTPS. A download
  must match the SHA-256 in the same release's `SHA256SUMS.txt`, and must be
  BLAKE2b Miner (same bundle identifier) at the version offered, before it
  replaces the app; the old app is restored if the swap fails. The checksum
  guards against corrupt or tampered downloads, not against someone who
  controls the GitHub account itself. Turn off *Check for updates
  automatically* to never contact GitHub.
- **Native code.** The app runs natively on Apple Silicon and Intel, and
  refuses to run under Rosetta on Apple Silicon (`LSRequiresNativeExecution`).

## Things to keep in mind

- Node RPC is plain HTTP. Keep the node on the same Mac, or reach a remote
  node only over a network you trust or an SSH tunnel. **Diagnostics** warns about remote nodes.
- `b2bminer --rpcpassword` is visible to other users in `ps`. Use the
  `B2B_RPC_PASSWORD` environment variable instead.
- Release builds are ad-hoc signed, not notarized. Check downloads against
  `SHA256SUMS.txt` on the release page, or build from source.

## Reporting a vulnerability

Please open a [GitHub security advisory](https://github.com/taimouralneimat/blake2b-miner/security/advisories/new)
rather than a public issue.
