#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
curl_args="$test_tmp/curl-args.txt"
mkdir -p "$stub_bin"

# Simulates a server that completes the handshake then stalls mid-response,
# against real curl semantics: --connect-timeout does not fire, --retry never
# triggers on a hung connection; only --max-time bounds the attempt (exit 28).
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CURL_ARGS"
case "${TEST_CURL_MODE:-hang}" in
  hang)
    if [[ " $* " == *" --max-time "* ]]; then
      exit 28
    fi
    sleep 300
    ;;
  ok)
    exit 0
    ;;
esac
SH
chmod +x "$stub_bin/curl"

run_check() {
  TEST_CURL_ARGS="$curl_args" TEST_CURL_MODE="${1:-hang}" \
    PATH="$stub_bin:/usr/bin:/bin" \
    timeout 15 "$ROOT/bin/omarchy-pkg-aur-accessible"
}

# A stalled AUR must fail closed and fast, not hang the update.
: >"$curl_args"
set +e
out=$(run_check hang 2>&1)
status=$?
set -e
[[ $status -ne 0 ]] || fail "aur-accessible fails when the AUR stalls" "exit=$status"
[[ $status -ne 124 ]] || fail "aur-accessible does not hang on a stalled AUR" "exit=124"
grep -q -- "--max-time" "$curl_args" || fail "aur-accessible bounds the probe with --max-time" "$(cat "$curl_args")"
pass "aur-accessible fails closed instead of hanging on a stalled AUR"

# A healthy AUR still reports accessible.
: >"$curl_args"
set +e
run_check ok >/dev/null 2>&1
status=$?
set -e
[[ $status -eq 0 ]] || fail "aur-accessible succeeds when the AUR answers" "exit=$status"
pass "aur-accessible succeeds when the AUR answers"
