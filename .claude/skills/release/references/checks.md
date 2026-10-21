# Release checks

Run from the repository root:

```bash
scripts/release-checks.sh
git diff --check
```

`scripts/release-checks.sh` is the whole mandatory gate. It builds, runs the test suite, compares the bundled system prompt with its fixture, verifies that the displayed and canonical versions agree and that `CHANGELOG.md` has a released section for the canonical version, scans the worktree for key and token patterns, packages the application, smoke-tests the packaged bundle including the single-instance guard, and finally builds and verifies the release artifacts.

The gate builds and checks local artifacts; it never publishes or uploads them. SwiftPM may need the network to fetch dependencies and binary artifacts, especially on the first build. Installing missing scanner dependencies may also require the network.

Building the update metadata reads the private EdDSA key from the Keychain, and macOS may put an authorisation dialog on screen and wait. The gate then appears to hang with no output. Answer the dialog with «Всегда разрешать» once; until it is answered, the gate is neither passing nor failing.

## Reading the result

The smoke test launches the packaged application and starts a second copy. It fails when a second instance stays alive, which is what protects the guarantee that only one menu bar icon can exist.

Artifact verification fails when the update feed is not HTTPS, when `appcast.xml` does not describe the canonical version, when the download address does not match the release tag, when the EdDSA signature is missing or does not match the disk image, when `sign_update` is unavailable, or when the checksums disagree.

By default, `scripts/verify-release-artifacts.sh` checks local `dist/release`, including the release notes. For publication verification, download the published disk image, `appcast.xml` and `SHA256SUMS` into a separate temporary directory, then run `scripts/verify-release-artifacts.sh <download-directory>`. This mode checks that three-file attachment set; it does not require a separate release-notes file. It never substitutes the local build for downloaded files.

## Documentation prose

Resolve the installed `humanizer-ru` skill and its bundled scanner from the live runtime, apply the skill to the final Russian documentation at documentation-level intensity, and run the scanner against the Russian documentation changed for this release, then confirm that `README.en.md` still states the same facts. Treat findings as evidence to review, never as permission to damage a fact, command, identifier, link or supported-behaviour claim. If scanner dependencies are missing, install them only in an ephemeral environment.

## When something is unavailable

Record the exact commands and their outcomes. If an executable, dependency, credential, network route or GitHub permission is missing, mark the gate `BLOCKED` and name the missing prerequisite. Never silently skip a check.
