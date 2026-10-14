# Releasing

`scripts/build-app.sh` builds the universal app and packages it in `dist/` as a
`.zip` and a `.dmg`, with `SHA256SUMS.txt`. The in-app updater downloads the `.zip`
and checks it against `SHA256SUMS.txt`, so attach all three to the GitHub release.

## Signing

By default the app is signed ad-hoc: it runs, but macOS asks people to allow it
once (System Settings › Privacy & Security › Open Anyway).

With an Apple Developer Program membership ($99 a year) the build can be signed
with a Developer ID and notarized by Apple, so it opens with no warning:

1. In Xcode › Settings › Accounts (or at developer.apple.com), create a
   **Developer ID Application** certificate; it is installed in your keychain.
   `security find-identity -v -p codesigning` shows its name.
2. Save notarization credentials once, with an app-specific password from
   appleid.apple.com:

   ```sh
   xcrun notarytool store-credentials blake2b-notary \
       --apple-id you@example.com --team-id TEAMID --password xxxx-xxxx-xxxx-xxxx
   ```

3. Build:

   ```sh
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   NOTARY_PROFILE=blake2b-notary scripts/build-app.sh
   ```

The script signs `b2bminer` and `datum_gateway`, then the app, with the hardened
runtime and a secure timestamp; submits the `.dmg` to Apple and waits; staples the
ticket to the `.dmg` and the app; checks the app with Gatekeeper (`spctl`); and
zips the stapled app. Ad-hoc builds use the hardened runtime too, so they behave
the same as notarized ones.

Once a release is signed with a Developer ID, the updater only installs updates
signed by the same team.

## The Mac App Store

Not possible. App Store rules forbid apps that mine cryptocurrency on the device
(App Review Guideline 3.1.5(b)), and apps may not run unrelated background work
such as mining (2.4.2). The App Store's sandbox also wouldn't allow the bundled
DATUM Gateway or full access to your node. Developer ID with notarization is
the supported way to distribute apps like this one outside the store.

## Checklist

1. Bump `Miner.version` in `Sources/MinerCore/Miner.swift`; update `CHANGELOG.md`.
2. `swift build && .build/debug/b2bminer selftest`, `scripts/test-e2e.sh`.
3. `scripts/build-app.sh` (with the signing variables, if you have them).
4. `gh release create vX.Y.Z dist/*.zip dist/*.dmg dist/SHA256SUMS.txt`.
