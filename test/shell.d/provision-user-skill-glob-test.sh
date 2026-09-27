#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Script under test. PROVISION_USER_SCRIPT / PROVISION_USER_BINDIR override it
# so the same test can run against the pre-fix script for the red/green proof.
script="${PROVISION_USER_SCRIPT:-$ROOT/bin/omarchy-provision-user}"
omarchy_bin="${PROVISION_USER_BINDIR:-$ROOT/bin}"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

# Stub the leaf commands the script calls after the skill loop.
for command in xdg-user-dirs-update xdg-settings xdg-mime omarchy-refresh-applications; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
chmod +x "$mock_bin"/*

mkdir -p "$test_tmp/install/user"
: >"$test_tmp/install/user/all.sh"

run_case() {
  local home="$1" omarchy="$2"
  mkdir -p "$home"

  HOME="$home" PATH="$mock_bin:$omarchy_bin:/usr/bin:/bin" \
    OMARCHY_PATH="$omarchy" OMARCHY_INSTALL="$test_tmp/install" \
    bash "$script" >/dev/null ||
    fail "omarchy-provision-user finishes when the skills glob matches nothing"

  for dir in .agents/skills .claude/skills .codex/skills .pi/agent/skills .gemini/config/skills .hermes/skills; do
    local d="$home/$dir"
    if [[ -L $d/* ]]; then
      fail "omarchy-provision-user plants no literal '*' symlink in ~/$dir"
    fi
    if [[ -n $(ls -A "$d") ]]; then
      fail "omarchy-provision-user creates no links in ~/$dir"
    fi
  done
}

# Case 1: no default/agents/skills dir at all (dev checkout edge).
omarchy1="$test_tmp/omarchy1"
mkdir -p "$omarchy1"
run_case "$test_tmp/home1" "$omarchy1"

# Case 2: the skills dir exists but is empty; the glob still matches nothing.
omarchy2="$test_tmp/omarchy2"
mkdir -p "$omarchy2/default/agents/skills"
run_case "$test_tmp/home2" "$omarchy2"

pass "omarchy-provision-user skips the skill loop when the glob matches nothing"
