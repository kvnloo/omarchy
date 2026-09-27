#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

run_start_log() {
  local log_file=$1
  (
    set -euo pipefail
    export OMARCHY_INSTALL_LOG_FILE="$log_file"
    unset OMARCHY_LOG_TO_STDOUT
    source "$ROOT/install/helpers/logging.sh"
    start_install_log
  )
}

# 1. A fresh install log is created without world-writable permissions.
log_new="$work_dir/new-install.log"
run_start_log "$log_new"
mode=$(stat -c '%a' "$log_new")
if (( 8#$mode & 002 )); then
  fail "fresh install log is not world-writable" "mode=$mode"
fi
pass "fresh install log is not world-writable (mode $mode)"

# 2. A pre-existing world-writable log is tightened.
log_old="$work_dir/old-install.log"
: >"$log_old"
chmod 666 "$log_old"
run_start_log "$log_old"
mode=$(stat -c '%a' "$log_old")
[[ $mode == "644" ]] || fail "pre-existing 666 install log tightened to 644" "mode=$mode"
pass "pre-existing 666 install log tightened to 644"

# 3. Logging still works after the change.
grep -q "Omarchy Setup Started" "$log_old" || fail "install log still records setup start"
pass "install log still records setup start"

# 4. stdout mode still bypasses the file entirely.
(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$work_dir/never-created.log"
  export OMARCHY_LOG_TO_STDOUT=1
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
) | grep -q "Omarchy Setup Started" || fail "stdout mode still emits setup start"
[[ ! -e $work_dir/never-created.log ]] || fail "stdout mode creates no log file"
pass "stdout mode still bypasses the file"

pass "install log is never world-writable"
