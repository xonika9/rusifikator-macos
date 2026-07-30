#!/bin/zsh

set -euo pipefail

repo_root=${0:A:h:h}
expected_path="$repo_root/Tests/Fixtures/ExpectedSystemPrompt.txt"
resource_path="$repo_root/Sources/Rusifikator/Resources/SystemPrompt.txt"

if [[ ! -f "$resource_path" ]]; then
  print -u2 "SystemPrompt.txt is missing: $resource_path"
  exit 1
fi

if ! cmp -s "$expected_path" "$resource_path"; then
  print -u2 "SystemPrompt.txt differs from the fixed system prompt"
  diff -u "$expected_path" "$resource_path" >&2 || true
  exit 1
fi

print "SystemPrompt.txt matches the fixed system prompt"
