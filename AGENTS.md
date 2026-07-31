# Repository instructions

This is a native macOS 26 menu-bar application built as a Swift Package.

- Never create branches — always commit and work directly on `main`.

## Sources of truth

- `README.md` owns product behavior, setup, usage, updating, release
  maintenance, and privacy disclosures.
- `DESIGN.md` owns visual and interaction constraints.
- `CHANGELOG.md` owns the user-visible history of released versions.
- `Sources/Rusifikator/Resources/Rusifikator-Info.plist` owns the canonical
  version, the update feed address, and the update signing public key.

## Required contracts

- Keep cleanup requests isolated: each request contains only the fixed system
  prompt and the current editor text. Never add local history to API requests.
- Accept only HTTPS providers. Keep API keys in Keychain and bound to the
  provider origin; reject cross-origin and HTTPS-downgrade redirects.
- Never include API keys, source transcripts, or generated results in logs,
  diagnostics, or user-facing error details.
- Keep `Sources/Rusifikator/Resources/SystemPrompt.txt` byte-identical to
  `Tests/Fixtures/ExpectedSystemPrompt.txt`. Update both when changing the
  system prompt.
- The application bundle is assembled manually by `scripts/package-app.sh`.
  When adding or changing bundled resources, update both `Package.swift` and
  the packaging script.
- Only one instance may run per user session. The claim is an advisory file
  lock keyed by bundle identifier, taken in `Sources/Rusifikator/main.swift`
  before the delegate exists. Never identify instances by process name and
  never terminate another process.
- Keep updates on Sparkle. Serve the feed over HTTPS, keep `SUPublicEDKey` in
  the bundle, and keep the private EdDSA key in the Keychain only — never in
  the repository, the artifacts, the logs or the shipped application.
- `CFBundleShortVersionString` is what the owner sees (`1.0`);
  `CFBundleVersion` is the canonical SemVer version the update channel compares
  (`1.0.0`). It must increase with every release.
- A published version is immutable. Never reuse, move or overwrite a released
  tag, release or artifact; correct it with a new version.

## Releases

`.claude/skills/release` is the canonical release skill; `.agents/skills/release`
is a repository-relative symlink to it, so Claude Code and Codex read one
source. It is a private repository skill and must never be bundled into the
application.

Release scripts, all local and offline:

```sh
scripts/release-checks.sh            # every mandatory check
scripts/build-release-artifacts.sh   # dmg, appcast.xml, checksums, notes
scripts/verify-release-artifacts.sh  # verify what was built
```

Publication is a separate, explicitly authorised step.

## Validation

Run the baseline checks after code changes:

```sh
swift build
swift test
```

After changing the system prompt:

```sh
scripts/test-system-prompt.sh
```

After changing packaging, resources, or application metadata:

```sh
scripts/package-app.sh
scripts/smoke-test-app.sh dist/Rusifikator.app
```

The packaging script replaces the ignored `dist/Rusifikator.app` artifact.
There is no automated UI test suite; visually inspect affected flows for UI
changes.
