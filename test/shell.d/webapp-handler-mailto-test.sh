#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/omarchy-launch-webapp" <<'SH'
#!/bin/bash
printf '%s\n' "$@" >>"$OMARCHY_TEST_ARGV"
SH
chmod +x "$mock_bin"/*

export PATH="$mock_bin:$PATH"
export OMARCHY_TEST_ARGV="$test_tmp/argv"

launched_url() {
  : >"$OMARCHY_TEST_ARGV"
  bash "$ROOT/bin/omarchy-webapp-handler-hey" "$1" >/dev/null 2>&1
  head -1 "$OMARCHY_TEST_ARGV"
}

# A plain mailto link opens a compose window addressed to the recipient.
url=$(launched_url 'mailto:dev@example.com')
[[ $url == 'https://app.hey.com/messages/new?to=dev%40example.com' ]] ||
  fail "plain mailto composes to the recipient" "$url"
pass "plain mailto composes to the recipient"

# RFC 6068 header fields (subject, body, ...) are not part of the address and
# must not leak into the to= parameter.
url=$(launched_url 'mailto:dev@example.com?subject=Hello%20there&body=Hi')
[[ $url == 'https://app.hey.com/messages/new?to=dev%40example.com' ]] ||
  fail "mailto query headers are stripped from the recipient" "$url"
pass "mailto query headers are stripped from the recipient"

# The recipient is embedded in a query parameter, so reserved characters must
# be percent-encoded rather than interpreted as parameter separators.
url=$(launched_url 'mailto:dev+tag@example.com')
[[ $url == 'https://app.hey.com/messages/new?to=dev%2Btag%40example.com' ]] ||
  fail "recipient reserved characters are percent-encoded" "$url"
pass "recipient reserved characters are percent-encoded"
