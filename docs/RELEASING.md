# Releasing

This document is for the maintainer. It covers how a version is cut, how the
update channel is kept working, where the signing key lives, and how to recover
from a release that went wrong.

## Version numbers

Two fields move together in
`Sources/Rusifikator/Resources/Rusifikator-Info.plist`:

- `CFBundleShortVersionString` — what the owner sees, for example `1.1`;
- `CFBundleVersion` — the canonical SemVer version the update channel compares,
  for example `1.1.0`.

`CFBundleVersion` must strictly increase from release to release. A version that
does not increase is invisible to installed copies.

## Scripts

All of them are local and offline. Nothing in this set publishes or uploads.

```sh
scripts/release-checks.sh            # the whole mandatory gate
scripts/build-release-artifacts.sh   # dmg, appcast.xml, checksums, notes
scripts/verify-release-artifacts.sh  # verify what was built
```

`scripts/release-checks.sh` builds, runs the test suite, compares the bundled
system prompt with its fixture, checks that both version fields agree and that
`CHANGELOG.md` has a section for the canonical version, scans the worktree for
key and token patterns, packages the application, smoke-tests the bundle
including the single-instance guard, and finally builds and verifies the
release artifacts.

Two things routinely surprise a first run:

- The smoke test launches the packaged copy, and only one instance may own a
  user session. Quit the installed Rusifikator first; the script names the
  process that is in the way.
- Building the update metadata reads the private EdDSA key from the Keychain,
  and macOS may put an authorization dialog on screen and wait. The gate then
  looks like it hangs with no output. Answer it once with «Всегда разрешать».

## Cutting a version

1. Record the changes in the `Unreleased` section of `CHANGELOG.md`.
2. Agree on the version according to SemVer.
3. Set it in both `Info.plist` fields.
4. Move `Unreleased` into a dated section for that version.
5. Run `scripts/release-checks.sh`.
6. Publish a release tagged `v<canonical version>` with `Rusifikator-<version>.dmg`,
   `appcast.xml` and `SHA256SUMS` attached.

`appcast.xml` must be attached to **every** release. The feed address resolves
to the newest release, so a release published without it breaks updating for
every installed copy.

The repository-local `release` skill (`.claude/skills/release`, mirrored for
Codex through `.agents/skills`) drives this whole cycle, including the version
confirmation gate. It is private tooling and never ships inside the
application.

## The update signing key

The private EdDSA key lives in the current user's login Keychain, in an entry
named `ed25519` created by Sparkle's `generate_keys`. It must never appear in
the repository, the artifacts, the logs or the shipped application. Only the
public half ships, as `SUPublicEDKey` in `Info.plist`.

Back it up by hand and store it outside the repository:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x ~/Desktop/rusifikator-eddsa.key
```

Delete that file once it is somewhere safe. The public half can be printed at
any time:

```sh
.build/artifacts/sparkle/Sparkle/bin/generate_keys -p
```

Losing the private key cannot be repaired through an update: it would take a
new version carrying a new `SUPublicEDKey`, installed by hand by everyone.

## When a release fails

A published version is immutable. Tags, releases and artifacts are never reused,
moved or overwritten; a mistake is corrected by the next version.

- **Artifacts broke, nothing is published yet.** Delete `dist/release`, fix the
  cause, run `scripts/release-checks.sh` again.
- **Published, and the application is unusable.** Ship the next patch version
  the normal way. Its `appcast.xml` becomes current immediately, because the
  feed always points at the newest release.
- **Published without `appcast.xml`.** Updating is broken for every installed
  copy. Attach the missing file to that same release — the one case where an
  existing release is amended, and it does not change the published image.
- **The signing key is lost.** See above: a new version with a new public key,
  installed manually.

## If a Developer ID appears

Three changes, none of which breaks installed copies:

1. in `scripts/package-app.sh`, replace `--sign -` with a "Developer ID
   Application" certificate and `--options runtime`;
2. add notarization (`notarytool`) and `stapler` for the finished `.dmg` to the
   release process;
3. leave the EdDSA signature alone — Sparkle checks both, and the key and the
   certificate must not change at the same time.

After that the manual unblocking steps can be dropped from the README.
