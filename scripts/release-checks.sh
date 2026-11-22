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
[[ "$canonical_version" =~ '^([0-9]{2})\.([1-9][0-9]?)\.([1-9][0-9]?)\.([1-9][0-9]*)$' ]] || {
  print -u2 "CFBundleVersion must be a YY.M.D.N version, got: $canonical_version"
  exit 1
}
release_date=$(printf '20%s-%02d-%02d' "${(@)match[1,3]}")
# BSD date normalises an impossible date instead of rejecting it.
[[ "$(date -j -f '%Y-%m-%d' "$release_date" '+%Y-%m-%d' 2>/dev/null)" == "$release_date" ]] || {
  print -u2 "CFBundleVersion does not carry a valid date: $canonical_version"
  exit 1
}
[[ "$canonical_version" == "$display_version" ]] || {
  print -u2 "CFBundleShortVersionString $display_version and CFBundleVersion $canonical_version disagree"
  exit 1
}
grep -qxF "## $canonical_version — $release_date" "$release_repo_root/CHANGELOG.md" || {
  print -u2 "CHANGELOG.md has no section '## $canonical_version — $release_date'"
  exit 1
}
print "$canonical_version is consistent"

step "no secrets in the working tree"
# git grep uses POSIX regular expressions, so no \b here: the pattern would be
# rejected and a rejected pattern finds nothing, which reads exactly like a
# clean tree. docs/research holds interface prototypes with obvious placeholder
# values and never ships.
set +e
# Only filenames may leave the scanner: matching lines can contain real keys.
secret_hits=$(git -C "$release_repo_root" grep -lIE \
  -e '-----BEGIN [A-Z ]*PRIVATE KEY' \
  -e '(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9]{16,}' \
  -e 'ghp_[A-Za-z0-9]{20,}' \
  -e 'github_pat_[A-Za-z0-9_]{20,}' \
  -- . ':(exclude)scripts/release-checks.sh' ':(exclude)docs/research' 2>/dev/null)
secret_status=$?
set -e
(( secret_status <= 1 )) || {
  print -u2 "The secret scan could not run (exit $secret_status)."
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

print "\nAll release checks passed for $canonical_version"
