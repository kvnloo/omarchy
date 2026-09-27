#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

require_command timeout

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/stubs"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home/.config/omarchy/plugins"

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
write_stub git-stall 'sleep 3600'

# Fast git: fetch succeeds instantly, rev-parse reports no changes.
write_stub git-fast '
if [[ " $* " == *" fetch "* ]]; then
  exit 0
fi
echo deadbeef
'

write_stub omarchy-shell 'exit 0'
write_stub omarchy-plugin-validate 'exit 0'

mkdir -p "$test_home/.config/omarchy/plugins/example-plugin/.git"

run_update() {
  local git_stub="$1"
  shift
  ln -sf "$stub_bin/$git_stub" "$stub_bin/git"
  HOME="$test_home" PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-plugin-update" "$@" 2>&1
}

# --- stalled fetch: bounded, loud, non-fatal to the rest of the run ---
start=$(date +%s)
set +e
out=$(OMARCHY_GIT_FETCH_TIMEOUT=2 run_update git-stall example-plugin --yes)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc == 1 )) || fail "plugin-update fails the plugin when fetch stalls" "$out"
grep -q "fetch timed out" <<<"$out" || fail "plugin-update reports the timeout" "$out"
(( elapsed < 15 )) || fail "plugin-update returns within the bound" "took ${elapsed}s"
pass "plugin-update aborts a stalled fetch within the timeout"

# --- fast remote: happy path unchanged ---
set +e
out=$(OMARCHY_GIT_FETCH_TIMEOUT=2 run_update git-fast example-plugin --yes)
rc=$?
set -e
(( rc == 0 )) || fail "plugin-update succeeds on a fast remote" "$out"
grep -q "up to date" <<<"$out" || fail "plugin-update reports up to date" "$out"
pass "plugin-update happy path unchanged on a fast remote"
