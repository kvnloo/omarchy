#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-tui-install must validate the app name (its sibling
# omarchy-webapp-install has require_plain_name + desktop_string_escape):
# a '/' escapes the applications dir and a newline injects keys into the
# generated .desktop file.

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TMPDIR="$T"
export PATH="$ROOT/bin:$PATH"

failures=0

# A: path traversal via '/'
"$ROOT/bin/omarchy-tui-install" '../escaped-tui' 'true' 'float' 'someicon' >/dev/null 2>&1 || true
if [[ -f $T/home/.local/share/escaped-tui.desktop ]]; then
  fail "'../escaped-tui' wrote outside the applications dir"
  failures=1
else
  pass "slash name refused or contained"
fi

# B: newline in the name injects a second key into the desktop entry
evil_name=$'Bad\nExec=touch '"$T/pwned2"
"$ROOT/bin/omarchy-tui-install" "$evil_name" 'true' 'float' 'someicon' >/dev/null 2>&1 || true
if grep -rq 'Exec=touch' "$T/home/.local/share/applications/" 2>/dev/null; then
  fail "newline in name injected an Exec= line"
  failures=1
else
  pass "no key injection from newline name"
fi

[[ $failures -eq 0 ]]
