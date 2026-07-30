#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
app_path=${1:-"$repo_root/dist/Rusifikator.app"}
info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/Rusifikator"
prompt="$app_path/Contents/Resources/SystemPrompt.txt"
plist_buddy=/usr/libexec/PlistBuddy

[[ -d "$app_path" ]] || {
  print -u2 "Application bundle is missing: $app_path"
  exit 1
}
[[ -x "$executable" ]] || {
  print -u2 "Application executable is not executable: $executable"
  exit 1
}

plutil -lint "$info_plist"
[[ "$("$plist_buddy" -c "Print :CFBundleIdentifier" "$info_plist")" == "dev.gotacat.Rusifikator" ]]
[[ "$("$plist_buddy" -c "Print :CFBundleDisplayName" "$info_plist")" == "Русификатор" ]]
[[ "$("$plist_buddy" -c "Print :LSUIElement" "$info_plist")" == "true" ]]
[[ "$("$plist_buddy" -c "Print :LSMinimumSystemVersion" "$info_plist")" == "26.0" ]]
cmp "$repo_root/Tests/Fixtures/ExpectedSystemPrompt.txt" "$prompt"
codesign --verify --deep --strict --verbose=2 "$app_path"

print "Smoke test passed: $app_path"
