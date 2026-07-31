#!/bin/zsh

# Checks that the local release artifacts describe the intended version, are
# reachable only over HTTPS, carry a verifiable signature and contain no
# signing key material.

set -euo pipefail

source "${0:A:h}/release-metadata.sh"

fail() {
  print -u2 "$1"
  exit 1
}

[[ -f "$dmg_path" ]] || fail "Disk image is missing: $dmg_path"
[[ -f "$appcast_path" ]] || fail "Update metadata is missing: $appcast_path"
[[ -f "$checksums_path" ]] || fail "Checksums are missing: $checksums_path"
[[ -f "$release_notes_path" ]] || fail "Release notes are missing: $release_notes_path"

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

if [[ -x "$sparkle_tools/sign_update" ]]; then
  "$sparkle_tools/sign_update" --verify "$dmg_path" "$signature" >/dev/null \
    || fail "The disk image does not match the published signature"
fi

(
  cd "$release_dir"
  shasum -a 256 --check --status SHA256SUMS
) || fail "Checksums do not match the artifacts"

# A private EdDSA key is 128 base64 characters and must never leave the
# Keychain. The public key is expected and explicitly allowed.
for artifact in "$appcast_path" "$checksums_path" "$release_notes_path"; do
  if grep -Eq '[A-Za-z0-9+/]{100,}={0,2}' "$artifact"; then
    if [[ "$(grep -Eo '[A-Za-z0-9+/]{100,}={0,2}' "$artifact" | head -1)" != "$signature" ]]; then
      fail "Unexpected long secret-looking value in $artifact"
    fi
  fi
done

print "Release artifacts verified for $display_version ($canonical_version)"
