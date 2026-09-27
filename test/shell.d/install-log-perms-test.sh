#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

log_file="$work_dir/install.log"

(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$log_file"
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
)

[[ -f $log_file ]] || fail "start_install_log creates the install log"

perms=$(stat -c '%a' "$log_file")
(( 8#$perms & 8#002 )) && fail "install log is world-writable (mode $perms): any local user can truncate or forge the root-owned install audit log"
(( 8#$perms & 8#004 )) || fail "install log lost world readability (mode $perms): omarchy-upload-log runs as the user and must still read it"

# Pre-existing logs created by the old code must be tightened too.
chmod 666 "$log_file"
(
  set -euo pipefail
  export OMARCHY_INSTALL_LOG_FILE="$log_file"
  source "$ROOT/install/helpers/logging.sh"
  start_install_log
)
perms=$(stat -c '%a' "$log_file")
(( 8#$perms & 8#002 )) && fail "start_install_log leaves a pre-existing world-writable install log at mode $perms"

# Exploit check: an unprivileged user must not be able to append to the log.
if command -v setpriv >/dev/null 2>&1; then
  if setpriv --reuid=nobody --regid=nogroup --clear-groups sh -c "echo forged >>'$log_file'" 2>/dev/null; then
    fail "unprivileged user can append forged lines to the install log"
  fi
  grep -q forged "$log_file" && fail "forged line landed in the install log"
fi

pass "install log is created without world-writable permissions"
