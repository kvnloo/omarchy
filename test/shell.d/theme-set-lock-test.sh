#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# omarchy-theme-set serialized theme changes with exec 9>/flock 9 but has no
# set -e: when the lock could not be taken (bad XDG_RUNTIME_DIR, full or
# read-only runtime fs), flock failed on a bad fd and the critical section ran
# unlocked, corrupting ~/.local/state/omarchy/current while exiting 0. The fix
# fails closed instead of switching unlocked.

FIXED="${THEME_SET_UNDER_TEST:-$ROOT/bin/omarchy-theme-set}"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export TMPDIR="$test_tmp"

# The acquisition snippet is exercised verbatim from the shipped file, followed
# by a marker standing in for the staging critical section: the defect is that
# execution CONTINUES into it (unlocked) after a failed lock.
lock_snippet="$test_tmp/lock-snippet.sh"
{
  echo '#!/bin/bash'
  echo 'THEME_SET_LOCK="${XDG_RUNTIME_DIR:-/tmp}/omarchy-theme-set.lock"'
  grep -E '^(exec 9>|flock 9)' "$FIXED"
  echo 'echo CRITICAL-SECTION-REACHED'
} >"$lock_snippet"
chmod +x "$lock_snippet"

# 1. An unusable runtime dir must abort BEFORE the critical section, not run it
# unlocked and report success.
missing_run="$test_tmp/no-such-dir/run"
out=""
rc=0
out=$(XDG_RUNTIME_DIR="$missing_run" bash "$lock_snippet" 2>/dev/null) || rc=$?
[[ $rc -ne 0 ]] || fail "lock acquisition with bad XDG_RUNTIME_DIR exited 0" "rc=$rc"
[[ $out != *CRITICAL-SECTION-REACHED* ]] \
  || fail "critical section ran unlocked after failed lock" "$out"
pass "failed lock acquisition fails closed before the critical section"

# 2. A healthy runtime dir acquires a real, exclusive lock.
good_run="$test_tmp/run"
mkdir -p "$good_run"
lockfile="$good_run/omarchy-theme-set.lock"
(
  XDG_RUNTIME_DIR="$good_run" bash -c 'source "$0" && sleep 30' "$lock_snippet"
) >/dev/null 2>&1 &
holder=$!
sleep 0.5
if flock -n "$lockfile" true 2>/dev/null; then
  kill "$holder" 2>/dev/null
  fail "lock not exclusive while held" "second process took the lock"
fi
pass "acquired lock is mutually exclusive while held"

# 3. The lock releases when the holder exits.
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null || true
if flock -n "$lockfile" true 2>/dev/null; then
  pass "lock releases cleanly after the holder exits"
else
  fail "lock still held after holder exit" ""
fi
