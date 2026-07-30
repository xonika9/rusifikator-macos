#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
app_path=${1:-"$repo_root/dist/Rusifikator.app"}
app_path=${app_path:A}
info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/Rusifikator"
prompt="$app_path/Contents/Resources/SystemPrompt.txt"
plist_buddy=/usr/libexec/PlistBuddy
smoke_pids=()

bundle_processes() {
  ps -axww -o pid=,command= | awk -v executable="$executable" '$2 == executable { print $1 }'
}

contains_pid() {
  local target=$1
  shift
  local pid
  for pid in "$@"; do
    [[ "$pid" == "$target" ]] && return 0
  done
  return 1
}

is_smoke_process() {
  local target=$1
  local pid
  for pid in "${(@f)$(bundle_processes)}"; do
    [[ "$pid" == "$target" ]] && return 0
  done
  return 1
}

has_running_smoke_process() {
  local pid
  for pid in "${smoke_pids[@]}"; do
    is_smoke_process "$pid" && return 0
  done
  return 1
}

cleanup_smoke_processes() {
  local pid deadline
  for pid in "${smoke_pids[@]}"; do
    is_smoke_process "$pid" || continue
    kill -TERM "$pid" 2>/dev/null || true
  done

  deadline=$((SECONDS + 5))
  while (( SECONDS < deadline )); do
    has_running_smoke_process || return
    sleep 0.1
  done

  for pid in "${smoke_pids[@]}"; do
    is_smoke_process "$pid" && kill -KILL "$pid" 2>/dev/null || true
  done
}

trap cleanup_smoke_processes EXIT INT TERM

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

before_pids=("${(@f)$(bundle_processes)}")
open -gj -n "$app_path"

deadline=$((SECONDS + 10))
while (( SECONDS < deadline )); do
  for pid in "${(@f)$(bundle_processes)}"; do
    if ! contains_pid "$pid" "${before_pids[@]}"; then
      smoke_pids+=("$pid")
    fi
  done

  (( ${#smoke_pids[@]} > 0 )) && break
  sleep 0.1
done

(( ${#smoke_pids[@]} > 0 )) || {
  print -u2 "Application did not start within 10 seconds: $app_path"
  exit 1
}

sleep 1
for pid in "${smoke_pids[@]}"; do
  is_smoke_process "$pid" || {
    print -u2 "Application exited during smoke test: $app_path"
    exit 1
  }
done

print "Smoke test passed: $app_path"
