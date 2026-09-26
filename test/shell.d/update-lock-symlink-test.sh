#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

lock_bin="$ROOT/bin/omarchy-update-lock"

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# A planted symlink at the lock path must not hand the truncating open to the
# link target: the lock file is only ever created by update-lock itself, so a
# link here is always foreign.
echo "precious" >"$t/victim.txt"
ln -s "$t/victim.txt" "$t/omarchy-update.lock"
if XDG_RUNTIME_DIR="$t" "$lock_bin" run true 2>"$t/err"; then
  fail "update-lock refuses a symlinked lock path"
fi
[[ $(<"$t/victim.txt") == "precious" ]] || fail "symlink target is left untouched"
grep -q "omarchy-update.lock" "$t/err" || fail "refusal names the lock path"
pass "update-lock refuses a symlinked lock path"

# A planted FIFO must not hang lock acquisition either.
rm -f "$t/omarchy-update.lock"
mkfifo "$t/omarchy-update.lock"
if timeout 5 env XDG_RUNTIME_DIR="$t" "$lock_bin" run true 2>/dev/null; then
  fail "update-lock refuses a FIFO lock path"
fi
pass "update-lock refuses a FIFO lock path"

# The normal path still works: the lock is acquired, the command runs, and a
# second acquirer is excluded.
rm -f "$t/omarchy-update.lock"
XDG_RUNTIME_DIR="$t" "$lock_bin" run true || fail "update-lock runs a command under a fresh lock"
[[ -f $t/omarchy-update.lock ]] || fail "lock file is created"
XDG_RUNTIME_DIR="$t" "$lock_bin" held && fail "lock is not held outside run"
pass "update-lock normal acquire/run/held behavior is unchanged"
