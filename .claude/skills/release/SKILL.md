---
name: release
description: Use for this repository when the owner asks to prepare or publish a version of «Русификатор» — «подготовь релиз», «сделай релиз», «выпусти релиз», "prepare a release", "publish the release". Do not use for an ordinary changelog edit, commit, push, build, packaging run, or check that is not explicitly a release.
metadata:
  internal: "true"
---

# Release

Prepare or publish a version of «Русификатор» from the complete repository state. The latest public tag, the full diff to the release candidate, `CHANGELOG.md`, the application metadata, the release scripts and the update channel are the sources of truth; never infer release scope from the current conversation or the newest commits alone.

This is a private repository-local skill for Claude Code and Codex. Its canonical source is `.claude/skills/release`; `.agents/skills/release` exposes that source through a repository-relative symlink. It must never reach the application bundle or the published artifacts.

## Select the mode

- **Prepare** — the request is to prepare a release. Propose the version, wait for confirmation, update the release files, run the release gate. Stop before commit, push, tag and publication.
- **Publish** — the owner explicitly asks to make or ship the release. Everything preparation does, plus a release commit, a push to `main`, the GitHub Release, and verification that an installed previous version can see the update.

A request to commit, push, edit `CHANGELOG.md`, build, package or run checks is not release authority. «Сделай релиз» grants publication authority; it does not waive the version confirmation gate.

## Establish the candidate

Resolve the repository root from this skill's location, then read:

- the worktree, the current branch, the remotes and the latest `v*` tag;
- the complete commit range and diff from that tag to the candidate, including uncommitted and untracked files;
- `README.md`, `README.en.md`, `docs/RELEASING.md`, `CONTRIBUTING.md`, `AGENTS.md`, `DESIGN.md`, `CHANGELOG.md`;
- `Sources/Rusifikator/Resources/Rusifikator-Info.plist` — `CFBundleShortVersionString`, `CFBundleVersion`, `SUFeedURL`, `SUPublicEDKey`;
- `scripts/release-metadata.sh`, `scripts/release-checks.sh`, `scripts/build-release-artifacts.sh`, `scripts/verify-release-artifacts.sh`.

Preserve unrelated and owner-authored changes. When the candidate cannot be separated from unrelated work, when the branch cannot safely produce the intended `main` release, or when the remote conflicts with local history, stop and name the exact blocker instead of rewriting history, discarding files, merging or force-pushing.

Reconcile every user-visible change since the latest public tag with the release notes, reading the semantic diff rather than trusting commit subjects.

## Prevent documentation drift

`README.md` is the public front page and owns installation, usage, updating, the limits of a build without Developer ID and the privacy disclosures; `README.en.md` is its translation and must move with it. `docs/RELEASING.md` owns version numbering, the release scripts, storage of the update signing key, preparation of the next version and recovery from a failed release. `CONTRIBUTING.md` owns the contributor environment and checks. Trace every changed behaviour, command, address and claim in the candidate to its owning section. A changed public contract needs an accurate section or an evidence-backed determination that it has no documentation impact; the absence of a documentation file from the diff is not that evidence. Keep maintainer-only material out of `README.md`.

`AGENTS.md` owns the repository contracts and `DESIGN.md` the visual constraints. Correct them when the candidate changes what they describe.

Load the installed `humanizer-ru` skill for the final Russian prose and apply its documentation-level rules without changing facts, commands, identifiers, links or supported-behaviour claims. Resolve the skill from the live runtime rather than a personal absolute path.

## Choose and confirm the version

Both version fields move together: `CFBundleShortVersionString` is what the owner sees (`1.1`) and `CFBundleVersion` is the canonical SemVer version the update channel compares (`1.1.0`). The canonical version must strictly increase — a version that does not is invisible to installed copies.

Propose the version from the strongest change in the full candidate and cite the changes that determine the bump:

- `MAJOR` — an incompatible change to how the application is installed, updated, configured or authorised, including a new update feed address or signing key;
- `MINOR` — a new user-visible capability or an intentional change to existing behaviour;
- `PATCH` — a backward-compatible correction that does not intend to change behaviour;
- a mixed candidate takes the highest applicable bump.

Confirm the version through the runtime's structured question tool as described in [version-confirmation.md](references/version-confirmation.md), even when the request already names a version. Before confirmation, change no version field, move nothing out of `Unreleased`, and create no release commit, tag or external release. A version that already has a public tag or release is immutable: propose the next one instead.

## Prepare the release files

After confirmation:

- set the confirmed version in both `Info.plist` fields;
- move the populated `Unreleased` content into `## X.Y.Z — YYYY-MM-DD`;
- leave an empty `Unreleased` template with `Главное`, `Установка и обновление`, `Совместимость` and `Несовместимые изменения`;
- write the notes from the owner's point of view, covering the whole candidate, and state `Нет.` explicitly when there are no incompatible changes;
- apply the identified documentation corrections.

Never introduce private paths, credentials, tokens, API keys, transcripts or fabricated evidence, and never include changes outside the confirmed candidate.

## Release gate

Run the complete command set in [checks.md](references/checks.md). A failed command blocks preparation and publication until it is fixed or the owner explicitly changes scope. A partial gate is never presented as a successful release.

Preparation is complete when both version fields hold the confirmed version, `CHANGELOG.md` carries that version with its date and a reset `Unreleased`, the notes cover the tag-to-candidate diff, the documentation matches the candidate, every check passes, and `dist/release` holds a disk image, a signed `appcast.xml`, checksums and release notes for that version.

## Publish

Publication needs every preparation condition plus explicit publication authority.

Commit the coherent release candidate without absorbing unrelated changes, push it to `main` without force, then create the release for `v<canonical version>` from that commit with `scripts/build-release-artifacts.sh` output attached: the disk image, `appcast.xml` and `SHA256SUMS`. The repository has no release automation, so this skill creates the tag and the GitHub Release itself; if automation is ever added, let it own them and do not create them in parallel.

Name the release `Русификатор <displayed version>` — `Русификатор 1.2` for `1.2 (1.2.0)`. The release list is a public shelf read top to bottom, so the title carries the product name and the version the owner sees, never the canonical version, the tag or a bare number. `scripts/build-release-artifacts.sh` already writes that heading into the release notes and `scripts/make-dmg.sh` into the volume name; read the title from them and from the previous releases instead of inventing one. Verify the published list afterwards: a title that breaks the row of its neighbours is a defect, and it is corrected in place — the title is metadata, not a released artifact.

`appcast.xml` must be attached to every release. The update feed resolves to the newest release, so a release published without it breaks updating for every installed copy.

## Safety

Never force-push, delete or move a published tag, overwrite an existing release, absorb unrelated changes, publish while a required check fails, commit keys or tokens, hide the limits of a build without Developer ID, or buy a certificate or touch the Apple account.

The private EdDSA key stays in the Keychain. It never appears in the repository, the artifacts, the logs or the report.

When the branch, the remote, the signing key, the checks or the publication route make a safe continuation impossible, stop and name the concrete blocker. A partially completed cycle is `BLOCKED`, never a release.

## Done

Publication is complete only when all of the following hold, each read from the real artifact rather than from a report:

- the GitHub Release for `v<canonical version>` exists and its tag points at the release commit;
- its title reads `Русификатор <displayed version>` and stands in one row with the previous releases;
- the disk image downloads and its checksum matches `SHA256SUMS`;
- `appcast.xml` is reachable at the feed address in `SUFeedURL` and names the released version;
- `scripts/verify-release-artifacts.sh` passes against the published version;
- an installed previous version reports the new version through «Проверить обновления»;
- every required check passed.

The final report states the version, the commit, the tag, the release link, the published artifacts, the check results, the state of the update channel, and the remaining limits — including that the build has no Developer ID and no notarisation.
