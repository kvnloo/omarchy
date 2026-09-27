#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/stubs"
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

# A remote that accepts the connection then never sends data: every git
# network op hangs. This is what the timeout bounds.
write_stub git 'sleep 3600'

# theme-update discovers themes through this; point it at two fake checkouts.
mkdir -p "$test_home/themes/alpha" "$test_home/themes/beta"
write_stub omarchy-theme-extras "printf '%s\n' \"$test_home/themes/alpha\" \"$test_home/themes/beta\""

export HOME="$test_home"
export PATH="$stub_bin:$ROOT/bin:$PATH"

# --- theme-install: bounded clone ---
start=$(date +%s)
set +e
out=$(OMARCHY_GIT_CLONE_TIMEOUT=2 "$ROOT/bin/omarchy-theme-install" \
  "https://github.com/example/omarchy-example-theme.git" 2>&1)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc != 0 )) || fail "theme-install fails when the clone stalls"
grep -q "Timed out" <<<"$out" || fail "theme-install reports the timeout" "$out"
(( elapsed < 15 )) || fail "theme-install returns within the bound" "took ${elapsed}s"
pass "theme-install aborts a stalled clone within the timeout"

# --- plugin-add: bounded clone ---
start=$(date +%s)
set +e
out=$(OMARCHY_GIT_CLONE_TIMEOUT=2 "$ROOT/bin/omarchy-plugin-add" \
  "https://github.com/example/omarchy-example-plugin.git" --yes 2>&1)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc != 0 )) || fail "plugin-add fails when the clone stalls"
grep -qi "timed out" <<<"$out" || fail "plugin-add reports the timeout" "$out"
(( elapsed < 15 )) || fail "plugin-add returns within the bound" "took ${elapsed}s"
pass "plugin-add aborts a stalled clone within the timeout"

# --- theme-update: bounded pull, continues past failures ---
start=$(date +%s)
set +e
out=$(OMARCHY_GIT_PULL_TIMEOUT=2 "$ROOT/bin/omarchy-theme-update" 2>&1)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc == 0 )) || fail "theme-update survives a stalled pull" "rc=$rc out=$out"
grep -q "Updating: alpha" <<<"$out" || fail "theme-update attempts the first theme"
grep -q "Updating: beta" <<<"$out" || fail "theme-update continues to the second theme"
grep -q "Warning" <<<"$out" || fail "theme-update warns on the failed pull"
(( elapsed < 20 )) || fail "theme-update returns within the bound" "took ${elapsed}s"
pass "theme-update bounds stalled pulls and continues"

# --- happy path still works when git is fast ---
write_stub git 'exit 0'
write_stub omarchy-theme-set 'exit 0'
set +e
out=$("$ROOT/bin/omarchy-theme-install" "https://github.com/example/omarchy-example-theme.git" 2>&1)
rc=$?
set -e
(( rc == 0 )) || fail "theme-install succeeds when the clone is fast" "rc=$rc out=$out"
pass "theme-install happy path unchanged"
