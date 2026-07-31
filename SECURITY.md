# Security Policy

## Reporting a vulnerability

Do not open a public issue for vulnerabilities, leaked credentials, or reports
that contain private data or real transcripts.

Use [GitHub private vulnerability reporting](https://github.com/xonika9/rusifikator-macos/security/advisories/new).
Include:

- the affected area — networking, Keychain storage, the update channel,
  packaging, or the single-instance claim;
- the application version (`CFBundleVersion`) and your macOS version;
- the smallest reproducible example;
- realistic impact and the preconditions it needs;
- a suggested fix, if you have one.

Strip API keys, transcripts and unrelated personal data from the report before
sending it. The project aims to acknowledge a report within seven days; a fix
or disclosure timeline depends on severity, reproducibility, and whether
Sparkle or macOS itself is involved.

## Supported versions

Security fixes target the latest published release. Older versions may get
guidance, but are not maintained as separate branches. Because a published
version is immutable, a fix always ships as a new version.

## Scope

In scope: this application's networking and redirect handling, Keychain usage
and origin binding, request isolation, local history storage, log and error
content, the update channel and its signature verification, the packaging
scripts, and the single-instance claim.

Out of scope, though still worth telling us about:

- vulnerabilities in Sparkle, macOS, or a third-party API provider — report
  those to their maintainers as well;
- the API provider's own retention and processing of transcripts, which is
  outside this application's control;
- the absence of an Apple Developer ID certificate and notarization. This is a
  documented, deliberate limitation described in the README, not a defect. No
  macOS protection is disabled by it.

## What the project promises

- API keys live only in the Keychain, bound to the provider's HTTPS origin.
- Requests carry only the fixed system prompt and the current editor text.
- Keys, source transcripts and generated results never reach logs,
  diagnostics or user-facing error details.
- Update metadata and artifacts are fetched over HTTPS and verified by an
  EdDSA signature before installation.
- The private signing key exists only in the maintainer's Keychain — never in
  the repository, the artifacts, the logs, or the shipped application.

A report showing that one of these does not hold is exactly the report this
project wants.
