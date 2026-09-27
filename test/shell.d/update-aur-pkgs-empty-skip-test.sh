#!/bin/bash

# omarchy-update-aur-pkgs must skip its AUR phase (the network probe and
# `yay -Sua`) when no foreign packages are installed. `pacman -Qem` exits
# 0 with empty output in that case, so testing the exit status is a
# vacuous guard: every update would fire the network probe and run yay.

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Point at a different copy of the script to prove red-on-base against the
# pre-fix version; defaults to the repo tree under test.
SCRIPT="${AUR_UPDATE_SCRIPT:-$ROOT/bin/omarchy-update-aur-pkgs}"

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

CALL_LOG="$test_tmp/calls"

run_update_aur_pkgs() {
  : >"$CALL_LOG"
  FOREIGN_PKGS="$1" CALL_LOG="$CALL_LOG" \
    PATH="$stub_bin:/usr/bin:/bin" \
    bash "$SCRIPT" >/dev/null 2>&1
}

write_stub pacman '
  echo "pacman $*" >>"$CALL_LOG"
  printf "%s" "$FOREIGN_PKGS"
  exit 0
'
write_stub omarchy-pkg-aur-accessible '
  echo "omarchy-pkg-aur-accessible $*" >>"$CALL_LOG"
  exit 0
'
write_stub yay '
  echo "yay $*" >>"$CALL_LOG"
  exit 0
'

# No foreign packages: pacman prints nothing and exits 0 (real behavior).
run_update_aur_pkgs ""
grep -q '^yay ' "$CALL_LOG" &&
  fail "no foreign packages means yay is not invoked" "$(cat "$CALL_LOG")"
grep -q '^omarchy-pkg-aur-accessible ' "$CALL_LOG" &&
  fail "no foreign packages means the AUR network probe is not fired" "$(cat "$CALL_LOG")"
pass "AUR phase is skipped when no foreign packages are installed"

# A foreign package present: the update phase still runs.
run_update_aur_pkgs "foreign-package"
grep -q '^yay ' "$CALL_LOG" ||
  fail "a foreign package installed means yay is invoked" "$(cat "$CALL_LOG")"
pass "AUR phase runs when a foreign package is installed"
