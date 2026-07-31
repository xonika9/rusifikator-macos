#!/bin/zsh

# The complete set of checks a release must pass. Every step is required: a
# failure here blocks preparation and publication.

set -euo pipefail

source "${0:A:h}/release-metadata.sh"

step() {
  print "\n=== $1 ==="
}

step "swift build"
(cd "$release_repo_root" && swift build)

step "swift test"
(cd "$release_repo_root" && swift test)

step "system prompt"
"$release_repo_root/scripts/test-system-prompt.sh"

step "version consistency"
[[ -n "$display_version" ]] || {
  print -u2 "CFBundleShortVersionString is empty"
  exit 1
}
[[ "$canonical_version" == <->.<->.<-> ]] || {
  print -u2 "CFBundleVersion must be a SemVer version, got: $canonical_version"
  exit 1
}
[[ "$canonical_version" == "$display_version"* ]] || {
  print -u2 "Version $display_version and canonical $canonical_version disagree"
  exit 1
}
grep -q "^## $canonical_version " "$release_repo_root/CHANGELOG.md" || {
  print -u2 "CHANGELOG.md has no released section for $canonical_version"
  exit 1
}
print "$display_version ($canonical_version) is consistent"

step "no secrets in the working tree"
# git grep uses POSIX regular expressions, so no \b here: the pattern would be
# rejected and a rejected pattern finds nothing, which reads exactly like a
# clean tree. docs/research holds interface prototypes with obvious placeholder
# values and never ships.
set +e
secret_hits=$(git -C "$release_repo_root" grep -nIE \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY' \
  -e '(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9]{16,}' \
  -e 'ghp_[A-Za-z0-9]{20,}' \
  -e 'github_pat_[A-Za-z0-9_]{20,}' \
  -- . ':(exclude)scripts/release-checks.sh' ':(exclude)docs/research' 2>&1)
secret_status=$?
set -e
(( secret_status <= 1 )) || {
  print -u2 "The secret scan could not run: $secret_hits"
  exit 1
}
[[ -z "$secret_hits" ]] || {
  print -u2 "The working tree contains something that looks like a secret:"
  print -u2 "$secret_hits"
  exit 1
}
print "no key or token patterns found"

step "package"
"$release_repo_root/scripts/package-app.sh"

step "smoke test"
"$release_repo_root/scripts/smoke-test-app.sh" "$app_path"

step "release artifacts"
"$release_repo_root/scripts/build-release-artifacts.sh"

print "\nAll release checks passed for $display_version ($canonical_version)"
