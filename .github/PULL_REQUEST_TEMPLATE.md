## What changes

<!-- One or two sentences on the behavior that changes, from the user's side. -->

## Why

<!-- The problem this solves. Link an issue if there is one. -->

## How it was verified

<!-- Name what you actually ran and what it said. An honest gap is fine. -->

- [ ] `swift build`
- [ ] `swift test`
- [ ] `scripts/test-system-prompt.sh` (if the system prompt changed)
- [ ] `scripts/package-app.sh` and `scripts/smoke-test-app.sh` (if packaging, resources or metadata changed)
- [ ] Affected interface flows inspected visually (if the interface changed)

## Contracts

- [ ] Requests still carry only the fixed system prompt and the current editor text.
- [ ] HTTPS-only providers, Keychain storage and origin binding are unchanged.
- [ ] No API key, transcript or generated result reaches logs, diagnostics or error text.
- [ ] User-visible changes are recorded in the `Unreleased` section of `CHANGELOG.md`.
