#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
cd "$repo_root"

swift build -c release
bin_path=$(swift build -c release --show-bin-path)
executable_path="$bin_path/Rusifikator"
sparkle_framework_path="$bin_path/Sparkle.framework"
info_plist_path="$repo_root/Sources/Rusifikator/Resources/Rusifikator-Info.plist"
app_path="$repo_root/dist/Rusifikator.app"
staging_root=$(mktemp -d "${TMPDIR:-/tmp}/rusifikator-package.XXXXXX")
staging_app="$staging_root/Rusifikator.app"

cleanup() {
  rm -rf "$staging_root"
}
trap cleanup EXIT

[[ -x "$executable_path" ]] || {
  print -u2 "Release executable is missing: $executable_path"
  exit 1
}
[[ -d "$sparkle_framework_path" ]] || {
  print -u2 "Sparkle.framework is missing: $sparkle_framework_path"
  exit 1
}
install -d "$staging_app/Contents/MacOS" "$staging_app/Contents/Resources" \
  "$staging_app/Contents/Frameworks"
# ditto keeps the framework's symlinks and sealed resources intact; a copy that
# follows symlinks breaks its code signature.
ditto "$sparkle_framework_path" "$staging_app/Contents/Frameworks/Sparkle.framework"
install -m 755 "$executable_path" "$staging_app/Contents/MacOS/Rusifikator"
install -m 644 "$info_plist_path" "$staging_app/Contents/Info.plist"
install -m 644 \
  "$repo_root/Sources/Rusifikator/Resources/SystemPrompt.txt" \
  "$staging_app/Contents/Resources/SystemPrompt.txt"
install -m 644 \
  "$repo_root/Sources/Rusifikator/Resources/Rusifikator.icns" \
  "$staging_app/Contents/Resources/Rusifikator.icns"

plutil -lint "$staging_app/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$staging_app"
codesign --verify --deep --strict --verbose=2 "$staging_app"

install -d "$repo_root/dist"
rm -rf "$app_path"
mv "$staging_app" "$app_path"

print "Packaged $app_path"
