#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

orphan_pkgs="$ROOT/bin/omarchy-update-orphan-pkgs"
require_command script
require_command timeout

temp_dirs=()
cleanup() { rm -rf "${temp_dirs[@]}"; }
trap cleanup EXIT

# Stubs: pacman reports one orphan (or none), gum records its invocation and
# then hangs like a real prompt waiting on a human, sudo drops privileges.
make_stubs() {
  local dir=$1 gum_behavior=$2 orphans=$3
  mkdir -p "$dir"
  if [[ $orphans == "one" ]]; then
    printf '#!/bin/bash\nif [[ ${1:-} == "-Qtdq" ]]; then printf "orphan-pkg\\n"; fi\n' >"$dir/pacman"
  else
    printf '#!/bin/bash\n: \n' >"$dir/pacman"
  fi
  {
    printf '#!/bin/bash\ntouch "$STUB_DIR/gum-invoked"\n'
    if [[ $gum_behavior == "hang" ]]; then
      printf 'sleep 30\n'
    elif [[ $gum_behavior == "no" ]]; then
      printf 'exit 1\n'
    else
      printf 'exit 0\n'
    fi
  } >"$dir/gum"
  printf '#!/bin/bash\nexec "$@"\n' >"$dir/sudo"
  chmod +x "$dir/pacman" "$dir/gum" "$dir/sudo"
}

# Runs the script with stdio on a pty, like the real `omarchy update` flow
# (which always re-execs under `script -qefc`), so the -t checks see ttys.
run_on_pty() {
  local stub_dir=$1 unattended=$2
  local out rc
  out=$(STUB_DIR="$stub_dir" PATH="$stub_dir:$PATH" \
    OMARCHY_UPDATE_UNATTENDED="$unattended" \
    timeout 15 script -qec "bash \"$orphan_pkgs\"" /dev/null 2>&1) && rc=0 || rc=$?
  printf '%s' "$out" >"$stub_dir/output"
  return "$rc"
}

# -y sets OMARCHY_UPDATE_UNATTENDED=1 (bin/omarchy-update), whose contract is
# "Interactive review steps report and move on instead of waiting": the orphan
# prompt must not block an unattended run even when stdio is a tty.
stub=$(mktemp -d); temp_dirs+=("$stub")
make_stubs "$stub" hang one
if run_on_pty "$stub" 1; then
  pass "unattended run reports orphans without prompting"
else
  fail "unattended run reports orphans without prompting" \
    "exit=$? (124 means the prompt hung waiting on a human)"
fi
[[ ! -e $stub/gum-invoked ]] ||
  fail "unattended run reports orphans without prompting" "gum was invoked"
grep -F "orphaned package(s) found. Re-run" "$stub/output" >/dev/null ||
  fail "unattended run reports orphans without prompting" "report message missing"

# The interactive decline path is unchanged: a human at the terminal still
# gets the prompt and can keep the packages.
stub=$(mktemp -d); temp_dirs+=("$stub")
make_stubs "$stub" no one
run_on_pty "$stub" 0 ||
  fail "interactive decline keeps orphaned packages" "exit=$?"
[[ -e $stub/gum-invoked ]] ||
  fail "interactive decline keeps orphaned packages" "gum was not invoked"
grep -F "Keeping orphaned packages." "$stub/output" >/dev/null ||
  fail "interactive decline keeps orphaned packages" "keep message missing"
pass "interactive decline keeps orphaned packages"

# The interactive accept path is unchanged: confirming still removes them.
stub=$(mktemp -d); temp_dirs+=("$stub")
make_stubs "$stub" yes one
run_on_pty "$stub" 0 ||
  fail "interactive confirm removes orphaned packages" "exit=$?"
grep -F "Removing orphan system packages" "$stub/output" >/dev/null ||
  fail "interactive confirm removes orphaned packages" "removal message missing"
pass "interactive confirm removes orphaned packages"

# No orphans: quiet exit regardless of mode.
stub=$(mktemp -d); temp_dirs+=("$stub")
make_stubs "$stub" hang none
run_on_pty "$stub" 1 ||
  fail "no orphans exits quietly" "exit=$?"
[[ ! -e $stub/gum-invoked ]] ||
  fail "no orphans exits quietly" "gum was invoked"
pass "no orphans exits quietly"
