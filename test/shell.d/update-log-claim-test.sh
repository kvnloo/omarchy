#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

require_command script
require_command mktemp

# script(1) truncates and follows links when opening its typescript. Pull the
# claim helper out of the updater the same way browser-policy-dir-test.sh
# extracts its cleanup handler, then prove the fixed log path cannot be a
# planted link anymore.
claim_update_log_fn=$(sed -n '/^claim_update_log() {/,/^}/p' "$ROOT/bin/omarchy-update")
[[ -n $claim_update_log_fn ]] || fail "omarchy-update defines claim_update_log"
eval "$claim_update_log_fn"

log=$test_tmp/update.log
victim=$test_tmp/victim.dat

# A planted symlink: without the claim, script(1) writes straight through it.
echo "precious" >"$victim"
ln -s "$victim" "$log"
script -qefc "echo MARKER" "$log" >/dev/null 2>&1 || true
grep -q "MARKER" "$victim" || fail "red: script(1) follows a planted symlink at the log path"
pass "red: script(1) follows a planted symlink at the log path"

# With the claim, the same planted symlink is atomically swapped for a fresh
# regular file before script(1) ever opens the path.
echo "precious" >"$victim"
ln -sf "$victim" "$log"
claim_update_log "$log" || fail "claim_update_log accepts a clean claim over a planted symlink"
[[ ! -L $log && -f $log ]] || fail "claim_update_log leaves a regular file, not a link"
script -qefc "echo MARKER" "$log" >/dev/null 2>&1
[[ $(cat "$victim") == "precious" ]] || fail "claim_update_log keeps script(1) away from the symlink target"
grep -q "MARKER" "$log" || fail "claim_update_log still produces a usable update log"
pass "claim_update_log neutralizes a planted symlink at the log path"

# A planted hard link: the target shares the inode, so link-count checks are
# the only signal. The claim must hand back a fresh inode and leave the
# original target's data and link count alone.
echo "precious" >"$victim"
rm -f "$log"
ln "$victim" "$log"
[[ $(stat -c '%h' -- "$victim") == "2" ]] || fail "test setup plants a real hard link"
claim_update_log "$log" || fail "claim_update_log accepts a clean claim over a planted hard link"
[[ $(stat -c '%h' -- "$log") == "1" ]] || fail "claim_update_log hands back a single-link inode"
[[ $(stat -c '%h' -- "$victim") == "1" ]] || fail "claim_update_log detaches the hard-linked target"
[[ $(cat "$victim") == "precious" ]] || fail "claim_update_log preserves the hard-linked target"
pass "claim_update_log neutralizes a planted hard link at the log path"

# The ordinary case: no pre-existing file, and a prior root-owned log, both
# end with a regular 644 file ready for script(1).
rm -f "$log"
claim_update_log "$log" || fail "claim_update_log creates the log when absent"
[[ -f $log && ! -L $log ]] || fail "claim_update_log creates a regular file"
[[ $(stat -c '%a' -- "$log") == "644" ]] || fail "claim_update_log keeps the log world-readable like script(1) would"
claim_update_log "$log" || fail "claim_update_log re-claims a log from a previous run"
pass "claim_update_log handles the ordinary create and re-claim cases"

# A directory squatting on the path: rename(2) cannot swap it, so the claim
# must fail instead of letting script(1) error out mid-update.
rm -f "$log"
mkdir -p "$log"
claim_update_log "$log" 2>/dev/null && fail "claim_update_log refuses a directory at the log path"
pass "claim_update_log refuses a directory at the log path"

unset -f claim_update_log
