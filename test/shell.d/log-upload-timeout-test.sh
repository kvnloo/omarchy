#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
curl_args="$test_tmp/curl-args.txt"
mkdir -p "$stub_bin"

# Simulates a blackholed upload endpoint against real curl semantics:
# with --max-time curl gives up and exits 28; without it, it hangs.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_CURL_ARGS"
if [[ " $* " == *" --max-time "* ]]; then
  exit 28
fi
sleep 300
SH
chmod +x "$stub_bin/curl"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/omarchy-cmd-present"

cat >"$stub_bin/journalctl" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/journalctl"

run_upload_log() {
  TEST_CURL_ARGS="$curl_args" \
    PATH="$stub_bin:/usr/bin:/bin" \
    HOME="$test_tmp/home" \
    timeout 15 "$ROOT/bin/omarchy-upload-log" this-boot
}

run_debug() {
  cat >"$stub_bin/gum" <<'SH'
#!/bin/bash
echo "Upload log"
SH
  chmod +x "$stub_bin/gum"
  cat >"$stub_bin/ping" <<'SH'
#!/bin/bash
exit 0
SH
  chmod +x "$stub_bin/ping"
  cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
exit 1
SH
  chmod +x "$stub_bin/pacman"
  cat >"$stub_bin/expac" <<'SH'
#!/bin/bash
exit 1
SH
  chmod +x "$stub_bin/expac"
  mkdir -p "$test_tmp/home"
  TEST_CURL_ARGS="$curl_args" \
    PATH="$stub_bin:/usr/bin:/bin" \
    HOME="$test_tmp/home" \
    timeout 20 "$ROOT/bin/omarchy-debug" --no-sudo
}

# --- omarchy-upload-log ---
: >"$curl_args"
set +e
out=$(run_upload_log 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "upload-log exits 1 when the upload endpoint hangs" "exit=$status out=$out"
[[ $out == *"Failed to upload"* ]] || fail "upload-log reports the failed upload" "out=$out"
grep -q -- "--max-time" "$curl_args" || fail "upload-log bounds the upload curl with --max-time" "$(cat "$curl_args")"
pass "upload-log fails loudly instead of hanging on a blackholed endpoint"

# --- omarchy-debug ---
: >"$curl_args"
set +e
out=$(run_debug 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || fail "debug exits 1 when the upload endpoint hangs" "exit=$status out=$out"
[[ $out == *"Failed to upload"* ]] || fail "debug reports the failed upload" "out=$out"
grep -q -- "--max-time" "$curl_args" || fail "debug bounds the upload curl with --max-time" "$(cat "$curl_args")"
pass "debug fails loudly instead of hanging on a blackholed endpoint"
