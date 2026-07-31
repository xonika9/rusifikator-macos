#!/bin/zsh

# Builds every artifact a release needs, from the packaged application to the
# signed update metadata. Nothing here talks to the network or publishes
# anything: the result is a local dist/release directory.

set -euo pipefail

source "${0:A:h}/release-metadata.sh"
require_sparkle_tools

changelog_path="$release_repo_root/CHANGELOG.md"

[[ -f "$changelog_path" ]] || {
  print -u2 "CHANGELOG.md is missing"
  exit 1
}

notes=$(awk -v version="$canonical_version" '
  $0 ~ "^## " version " " { collecting = 1; next }
  collecting && /^## / { exit }
  collecting { print }
' "$changelog_path")

[[ -n "${notes//[[:space:]]/}" ]] || {
  print -u2 "CHANGELOG.md has no section for $canonical_version"
  exit 1
}

rm -rf "$release_dir"
install -d "$release_dir"

"$release_repo_root/scripts/make-dmg.sh"

print -r -- "$notes" > "$release_notes_path"
# Sparkle picks up release notes from a file named after the archive.
{
  print -r -- "## Русификатор $display_version"
  print -r -- "$notes"
} > "$sparkle_notes_path"

"$sparkle_tools/generate_appcast" \
  --download-url-prefix "$download_url_prefix" \
  --link "$release_project_url" \
  --full-release-notes-url "$release_project_url/blob/main/CHANGELOG.md" \
  --embed-release-notes \
  "$release_dir"

[[ -f "$appcast_path" ]] || {
  print -u2 "generate_appcast produced no appcast.xml"
  exit 1
}

# The markdown file has done its job; only the artifacts that are published
# stay in the directory.
rm -f "$sparkle_notes_path"
rm -rf "$release_dir/old_updates"

(
  cd "$release_dir"
  shasum -a 256 "$dmg_name" appcast.xml > "SHA256SUMS"
)

"$release_repo_root/scripts/verify-release-artifacts.sh"

print "Release artifacts for $display_version ($canonical_version) are in $release_dir"
