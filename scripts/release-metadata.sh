#!/bin/zsh

# Shared release facts. Sourced by the other release scripts so the canonical
# version, the update channel and the tool paths are defined in one place.

set -euo pipefail

release_repo_root=${0:A:h:h}
plist_buddy=/usr/libexec/PlistBuddy
info_plist_path="$release_repo_root/Sources/Rusifikator/Resources/Rusifikator-Info.plist"

# Version the owner sees, for example 1.0.
display_version=$("$plist_buddy" -c "Print :CFBundleShortVersionString" "$info_plist_path")
# Version SemVer tooling and the update channel compare, for example 1.0.0.
canonical_version=$("$plist_buddy" -c "Print :CFBundleVersion" "$info_plist_path")
release_tag="v$canonical_version"

feed_url=$("$plist_buddy" -c "Print :SUFeedURL" "$info_plist_path")
public_ed_key=$("$plist_buddy" -c "Print :SUPublicEDKey" "$info_plist_path")

release_repository="xonika9/rusifikator-macos"
release_project_url="https://github.com/$release_repository"
download_url_prefix="$release_project_url/releases/download/$release_tag/"

app_path="$release_repo_root/dist/Rusifikator.app"
release_dir="$release_repo_root/dist/release"
dmg_name="Rusifikator-$canonical_version.dmg"
dmg_path="$release_dir/$dmg_name"
appcast_path="$release_dir/appcast.xml"
checksums_path="$release_dir/SHA256SUMS"
release_notes_path="$release_dir/RELEASE_NOTES.md"
sparkle_notes_path="$release_dir/Rusifikator-$canonical_version.md"

sparkle_tools="$release_repo_root/.build/artifacts/sparkle/Sparkle/bin"

require_sparkle_tools() {
  [[ -x "$sparkle_tools/generate_appcast" ]] || {
    print -u2 "Sparkle tools are missing. Run 'swift build' first."
    exit 1
  }
}
