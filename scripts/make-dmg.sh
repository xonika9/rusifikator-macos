#!/bin/zsh

# Builds the installable disk image from the already packaged application.

set -euo pipefail

source "${0:A:h}/release-metadata.sh"

[[ -d "$app_path" ]] || {
  print -u2 "Application bundle is missing. Run scripts/package-app.sh first."
  exit 1
}

staging_root=$(mktemp -d "${TMPDIR:-/tmp}/rusifikator-dmg.XXXXXX")
cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

# ditto keeps symlinks and code signatures inside the bundle intact.
ditto "$app_path" "$staging_root/Rusifikator.app"
ln -s /Applications "$staging_root/Applications"

install -d "$release_dir"
rm -f "$dmg_path"
hdiutil create \
  -volname "Русификатор $display_version" \
  -srcfolder "$staging_root" \
  -fs HFS+ \
  -format UDZO \
  -quiet \
  "$dmg_path"

hdiutil verify -quiet "$dmg_path"

print "Built $dmg_path"
