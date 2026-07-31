# Release checks

Run from the repository root:

```bash
scripts/release-checks.sh
git diff --check
```

`scripts/release-checks.sh` is the whole mandatory gate. It builds, runs the test suite, compares the bundled system prompt with its fixture, verifies that the displayed and canonical versions agree and that `CHANGELOG.md` has a released section for the canonical version, scans the worktree for key and token patterns, packages the application, smoke-tests the packaged bundle including the single-instance guard, and finally builds and verifies the release artifacts.

Everything it does is local and offline. Nothing in the gate publishes, uploads or reaches the network.

Building the update metadata reads the private EdDSA key from the Keychain, and macOS may put an authorisation dialog on screen and wait. The gate then appears to hang with no output. Answer the dialog with «Всегда разрешать» once; until it is answered, the gate is neither passing nor failing.

## Reading the result

The smoke test launches the packaged application and starts a second copy. It fails when a second instance stays alive, which is what protects the guarantee that only one menu bar icon can exist.

Artifact verification fails when the update feed is not HTTPS, when `appcast.xml` does not describe the canonical version, when the download address does not match the release tag, when the EdDSA signature is missing or does not match the disk image, or when the checksums disagree.

## Documentation prose

Resolve the installed `humanizer-ru` skill and its bundled scanner from the live runtime, apply the skill to the final Russian documentation at documentation-level intensity, and run the scanner against the complete `README.md` even when the candidate did not change it, then confirm that `README.en.md` still states the same facts. Treat findings as evidence to review, never as permission to damage a fact, command, identifier, link or supported-behaviour claim. If scanner dependencies are missing, install them only in an ephemeral environment.

## When something is unavailable

Record the exact commands and their outcomes. If an executable, dependency, credential, network route or GitHub permission is missing, mark the gate `BLOCKED` and name the missing prerequisite. Never silently skip a check.
