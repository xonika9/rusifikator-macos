# Repository instructions

This is a native macOS 26 menu-bar application built as a Swift Package.

## Sources of truth

- `README.md` owns product behavior, setup, usage, and privacy disclosures.
- `DESIGN.md` owns visual and interaction constraints.

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
