#!/bin/zsh

# Checks that local or downloaded release artifacts describe the intended version, are
# reachable only over HTTPS, carry a verifiable signature and contain no
# signing key material.

set -euo pipefail

source "${0:A:h}/release-metadata.sh"

fail() {
  print -u2 "$1"
  exit 1
}

(( $# <= 1 )) || fail "Usage: scripts/verify-release-artifacts.sh [artifact-directory]"
if (( $# == 1 )); then
  release_dir=${1:A}
  dmg_path="$release_dir/$dmg_name"
  appcast_path="$release_dir/appcast.xml"
  checksums_path="$release_dir/SHA256SUMS"
  release_notes_path="$release_dir/RELEASE_NOTES.md"
fi

[[ -f "$dmg_path" ]] || fail "Disk image is missing: $dmg_path"
[[ -f "$appcast_path" ]] || fail "Update metadata is missing: $appcast_path"
[[ -f "$checksums_path" ]] || fail "Checksums are missing: $checksums_path"
text_artifacts=("$appcast_path" "$checksums_path")
if [[ -f "$release_notes_path" ]]; then
  text_artifacts+=("$release_notes_path")
elif (( $# == 0 )); then
  # The published attachment set has three files; local preparation also needs notes.
  fail "Release notes are missing: $release_notes_path"
fi

appcast=$(<"$appcast_path")

[[ "$feed_url" == https://* ]] || fail "Update feed must be HTTPS: $feed_url"
[[ -n "$public_ed_key" ]] || fail "SUPublicEDKey is not set in the application"

[[ "$appcast" == *"<sparkle:version>$canonical_version</sparkle:version>"* ]] \
  || fail "Update metadata does not describe version $canonical_version"
[[ "$appcast" == *"<sparkle:shortVersionString>$display_version</sparkle:shortVersionString>"* ]] \
  || fail "Update metadata does not show version $display_version"
[[ "$appcast" == *"$download_url_prefix$dmg_name"* ]] \
  || fail "Update metadata does not point at $download_url_prefix$dmg_name"
[[ "$appcast" == *'sparkle:edSignature="'* ]] \
  || fail "Update metadata carries no EdDSA signature"

# Every download the application can be sent to has to be HTTPS.
insecure=$(grep -o 'url="http://[^"]*"' "$appcast_path" || true)
[[ -z "$insecure" ]] || fail "Update metadata contains a plain HTTP address: $insecure"

signature=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$appcast_path" | head -1)
[[ -n "$signature" ]] || fail "Could not read the EdDSA signature"

[[ -x "$sparkle_tools/sign_update" ]] || fail "Signature verifier is missing: sign_update. Run 'swift build' first."
"$sparkle_tools/sign_update" --verify "$dmg_path" "$signature" >/dev/null \
  || fail "The disk image does not match the published signature"

(
  cd "$release_dir"
  shasum -a 256 --check --status SHA256SUMS
) || fail "Checksums do not match the artifacts"

# A private EdDSA key is 128 base64 characters and must never leave the
# Keychain. The public key is expected and explicitly allowed.
for artifact in "${text_artifacts[@]}"; do
  if grep -Eq '[A-Za-z0-9+/]{100,}={0,2}' "$artifact"; then
    if [[ "$(grep -Eo '[A-Za-z0-9+/]{100,}={0,2}' "$artifact" | head -1)" != "$signature" ]]; then
      fail "Unexpected long secret-looking value in $artifact"
    fi
  fi
done

print "Release artifacts verified for $canonical_version"
