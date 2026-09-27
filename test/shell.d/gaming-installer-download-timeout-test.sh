#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
curl_args="$test_tmp/curl-args.txt"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

# Simulates a server that completes the handshake then stalls mid-response,
# with real curl semantics: --retry never fires on a hung connection, so only
# --max-time bounds the attempt (curl exits 28). Without it the download
# hangs until the outer timeout kills it (exit 124).
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CURL_ARGS"
if [[ " $* " == *" --max-time "* ]]; then
  exit 28
fi
sleep 300
SH
chmod +x "$stub_bin/curl"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

write_stub omarchy-pkg-add 'exit 0'
write_stub omarchy-install-gaming-gpu-lib32 'exit 0'
write_stub setsid 'exit 0'
write_stub update-desktop-database 'exit 0'

run_installer() {
  HOME="$test_home" OMARCHY_PATH="$ROOT" TEST_CURL_ARGS="$curl_args" \
    PATH="$stub_bin:/usr/bin:/bin" \
    timeout 20 "$ROOT/bin/$1"
}

# A stalled Battle.net download must fail fast, not hang the installer.
: >"$curl_args"
set +e
run_installer omarchy-install-gaming-battlenet >"$test_tmp/battlenet.out" 2>&1
status=$?
set -e
[[ $status -ne 124 ]] || fail "battlenet installer does not hang on a stalled download" "exit=124"
grep -q -- "--max-time" "$curl_args" || fail "battlenet installer bounds the download with --max-time" "$(cat "$curl_args")"
pass "battlenet installer fails fast instead of hanging on a stalled download"

# A stalled GeForce NOW download must fail fast, not hang the installer.
: >"$curl_args"
set +e
run_installer omarchy-install-gaming-geforce-now >"$test_tmp/geforce.out" 2>&1
status=$?
set -e
[[ $status -ne 124 ]] || fail "geforce-now installer does not hang on a stalled download" "exit=124"
grep -q -- "--max-time" "$curl_args" || fail "geforce-now installer bounds the download with --max-time" "$(cat "$curl_args")"
pass "geforce-now installer fails fast instead of hanging on a stalled download"
