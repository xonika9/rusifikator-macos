# Contributing

Thanks for looking. This is a small, deliberately narrow utility: it turns a
Russian voice transcript into clean prose and does nothing else. The most
useful contributions are bug reports with a reproduction, compatibility
findings, and focused fixes.

## Environment

- macOS 26 or newer, Apple Silicon;
- Xcode 26 with Swift 6.2 or newer.

The project is a Swift Package with no Xcode project file. Open `Package.swift`
through File → Open in Xcode, or work from the command line.

## Checks

Run these after any code change:

```sh
swift build
swift test
```

After changing the system prompt:

```sh
scripts/test-system-prompt.sh
```

After changing packaging, bundled resources or application metadata:

```sh
scripts/package-app.sh
scripts/smoke-test-app.sh dist/Rusifikator.app
```

`scripts/package-app.sh` replaces the ignored `dist/Rusifikator.app` artifact.
The smoke test launches that copy, and only one instance may own a user
session, so quit the installed application first — the script names the process
that is in the way.

There is no automated UI test suite. Inspect affected flows visually when you
change the interface.

## Contracts that must not regress

These are load-bearing. A change that weakens one of them will not be merged
without a very good reason stated in the pull request.

- **Request isolation.** A cleanup request contains only the fixed system
  prompt and the current editor text. Local history is never added to a
  request.
- **Transport and credentials.** HTTPS-only providers. API keys live in the
  Keychain, bound to the provider origin; cross-origin and HTTPS-downgrade
  redirects are rejected.
- **No leaks.** API keys, source transcripts and generated results never reach
  logs, diagnostics or user-facing error text.
- **System prompt fixture.** `Sources/Rusifikator/Resources/SystemPrompt.txt`
  stays byte-identical to `Tests/Fixtures/ExpectedSystemPrompt.txt`. Change both
  together.
- **Single instance.** The claim is an advisory file lock keyed by the bundle
  identifier, taken in `Sources/Rusifikator/main.swift` before the delegate
  exists. Instances are never identified by process name, and another process
  is never terminated.
- **Updates.** Updating stays on Sparkle, the feed stays HTTPS, `SUPublicEDKey`
  stays in the bundle, and the private key stays in the Keychain only.
- **Packaging.** The bundle is assembled by `scripts/package-app.sh`. When you
  add or change a bundled resource, update both `Package.swift` and that
  script.

`AGENTS.md` holds the full set; `DESIGN.md` owns the visual and interaction
constraints.

## Pull requests

- Work from `main` and keep the change focused; unrelated cleanup makes review
  harder and gets asked out.
- Match the surrounding code: naming, comment density, and the existing
  idioms.
- Add or extend tests for behavior you change. The suite is fast; there is no
  excuse for skipping it.
- Describe what you verified and what you did not. An honest gap is fine; a
  claim that does not hold is not.
- User-visible changes belong in the `Unreleased` section of `CHANGELOG.md`.

Releases are cut by the maintainer; see [docs/RELEASING.md](docs/RELEASING.md).

## Security

Do not report vulnerabilities, leaked credentials or anything containing
private data through a public issue or pull request. Follow
[SECURITY.md](SECURITY.md) instead.
