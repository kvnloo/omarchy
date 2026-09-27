#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

# A remote that accepts the connection then never sends data: the pull hangs.
# This is what the timeout bounds.
write_stub git-stall '
case " $* " in
  *" pull "*) sleep 3600 ;;
  *"@{upstream}"*) echo "origin/main" ;;
esac
exit 0
'

# Fast git: every local and network op succeeds instantly.
write_stub git-fast '
case " $* " in
  *"@{upstream}"*) echo "origin/main" ;;
esac
exit 0
'

run_update_dev() {
  local git_stub="$1"
  shift
  ln -sf "$stub_bin/$git_stub" "$stub_bin/git"
  OMARCHY_PATH="$test_tmp/dev" PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-update-dev" 2>&1
}

# --- stalled pull: bounded and loud ---
start=$(date +%s)
set +e
out=$(OMARCHY_GIT_PULL_TIMEOUT=2 run_update_dev git-stall)
rc=$?
set -e
elapsed=$(( $(date +%s) - start ))
(( rc == 1 )) || fail "update-dev fails when the pull stalls" "$out"
grep -q "Could not pull the Omarchy dev checkout" <<<"$out" || \
  fail "update-dev reports the failed pull" "$out"
(( elapsed < 15 )) || fail "update-dev returns within the bound" "took ${elapsed}s"
pass "update-dev aborts a stalled pull within the timeout"

# --- fast remote: happy path unchanged ---
set +e
out=$(OMARCHY_GIT_PULL_TIMEOUT=2 run_update_dev git-fast)
rc=$?
set -e
(( rc == 0 )) || fail "update-dev succeeds on a fast remote" "$out"
pass "update-dev happy path unchanged on a fast remote"
