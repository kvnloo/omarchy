#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Stub the launcher: capture the URL it would open instead of opening it.
mkdir -p "$tmpdir/stubbin"
printf '#!/bin/bash\nprintf "%%s\\n" "$1" > "%s/launched"\n' "$tmpdir" >"$tmpdir/stubbin/omarchy-launch-webapp"
chmod +x "$tmpdir/stubbin/omarchy-launch-webapp"

run_handler() {
  PATH="$tmpdir/stubbin:$PATH" "$ROOT/bin/omarchy-webapp-handler-zoom" "$@"
  cat "$tmpdir/launched"
}

url=$(run_handler "zoommtg://zoom.us/join?confno=123456789&pwd=abc123")
[[ $url == "https://app.zoom.us/wc/join/123456789?pwd=abc123" ]] ||
  fail "plain zoommtg link joins with confno and pwd" "$url"
pass "plain zoommtg link joins with confno and pwd"

url=$(run_handler "zoomus://zoom.us/join?confno=987654321")
[[ $url == "https://app.zoom.us/wc/join/987654321" ]] ||
  fail "zoomus link without pwd joins" "$url"
pass "zoomus link without pwd joins"

url=$(run_handler "zoommtg://zoom.us/join?confno=123%3f&x=1")
[[ $url == "https://app.zoom.us/wc/home" ]] ||
  fail "confno with encoded query delimiter is rejected" "$url"
pass "confno with encoded query delimiter is rejected"

url=$(run_handler "zoommtg://zoom.us/join?confno=123?evil=1")
[[ $url == "https://app.zoom.us/wc/home" ]] ||
  fail "confno with raw query delimiter is rejected" "$url"
pass "confno with raw query delimiter is rejected"

url=$(run_handler "zoommtg://zoom.us/join?confno=123#frag")
[[ $url == "https://app.zoom.us/wc/home" ]] ||
  fail "confno with fragment delimiter is rejected" "$url"
pass "confno with fragment delimiter is rejected"

url=$(run_handler "zoommtg://zoom.us/join?confno=..%2f..%2f..%2fsignin")
[[ $url == "https://app.zoom.us/wc/home" ]] ||
  fail "confno with path traversal is rejected" "$url"
pass "confno with path traversal is rejected"

url=$(run_handler "zoommtg://zoom.us/join?confno=123456789&pwd=a b")
[[ $url == "https://app.zoom.us/wc/join/123456789?pwd=a%20b" ]] ||
  fail "pwd with raw space is percent-encoded" "$url"
pass "pwd with raw space is percent-encoded"

url=$(run_handler "zoommtg://zoom.us/join?confno=123456789&pwd=a%26b")
[[ $url == "https://app.zoom.us/wc/join/123456789?pwd=a%26b" ]] ||
  fail "already-encoded pwd round-trips unchanged" "$url"
pass "already-encoded pwd round-trips unchanged"
