#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

# Simulates a blackholed key endpoint against real curl semantics:
# without --max-time curl hangs; with it, curl gives up and exits 28.
write_stub curl-stall '
max_time=0
prev=""
for arg in "$@"; do
  [[ $prev == "--max-time" ]] && max_time=$arg
  prev=$arg
done
if (( max_time > 0 )); then
  sleep "$max_time"
  exit 28
fi
sleep 3600
'

write_stub curl-fast 'echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAItest user@test"'

write_stub omarchy-pkg-add 'exit 0'
write_stub systemctl 'exit 0'
write_stub sudo 'exec "$@"'
write_stub ssh-keygen 'exit 0'
write_stub sshd 'printf "passwordauthentication no\nkbdinteractiveauthentication no\n"'
write_stub hostname 'echo testhost'
write_stub gum 'exit 1'

run_setup() {
  local curl_stub="$1"
  shift
  ln -sf "$stub_bin/$curl_stub" "$stub_bin/curl"
  HOME="$test_home" USER=testuser PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-setup-security-sshd" "$@" 2>&1
}

# --- stalled fetch: bounded and loud ---
start=$(date +%s)
set +e
out=$(OMARCHY_GITHUB_KEYS_TIMEOUT=3 run_setup curl-stall --gh-keys someuser)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc == 1 )) || fail "setup fails when the key fetch stalls" "$out"
grep -q "Could not fetch any SSH keys" <<<"$out" || fail "setup reports the fetch failure" "$out"
(( elapsed < 20 )) || fail "setup returns within the bound" "took ${elapsed}s"
pass "setup aborts a stalled GitHub key fetch within the timeout"

# --- fast remote: happy path unchanged ---
set +e
out=$(OMARCHY_GITHUB_KEYS_TIMEOUT=3 run_setup curl-fast --gh-keys someuser)
rc=$?
set -e
(( rc == 0 )) || fail "setup succeeds on a fast remote" "$out"
grep -q "The SSH server is running" <<<"$out" || fail "setup completes" "$out"
grep -q "ssh-ed25519" "$test_home/.ssh/authorized_keys" || \
  fail "key lands in authorized_keys" "$(cat "$test_home/.ssh/authorized_keys" 2>/dev/null)"
pass "setup happy path unchanged on a fast remote"
