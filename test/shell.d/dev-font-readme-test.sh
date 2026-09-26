#!/bin/bash

source "$(dirname "$0")/base-test.sh"

require_command python3

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

# A working copy of the shipped font plus a README that carries no mark list.
cp "$ROOT/default/fonts/omarchy/omarchy.ttf" "$TEST_HOME/omarchy.ttf"
printf '# Marks\n\nNo marks recorded yet.\n' >"$TEST_HOME/README.md"
printf '<svg viewBox="0 0 24 24"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2z"/></svg>' >"$TEST_HOME/mark.svg"

if python3 "$ROOT/bin/omarchy-dev-font" add --font "$TEST_HOME/omarchy.ttf" \
    testmark "$TEST_HOME/mark.svg" >/dev/null 2>&1; then
  pass "dev font add succeeds when the README has no mark list"
else
  fail "dev font add succeeds when the README has no mark list"
fi

if grep -q -- '- `U+E90F` — testmark' "$TEST_HOME/README.md"; then
  pass "the new mark is appended when the README has no mark list"
else
  fail "the new mark is appended when the README has no mark list"
fi

# A README that already carries a mark list keeps the entry grouped with the
# other marks instead of drifting to the end of the file.
printf -- '- `U+E900` — omarchy\n\n## Other docs\n' >"$TEST_HOME/README.md"
if ! python3 "$ROOT/bin/omarchy-dev-font" add --font "$TEST_HOME/omarchy.ttf" \
    --codepoint U+E910 testmark2 "$TEST_HOME/mark.svg" >/dev/null 2>&1; then
  fail "dev font add succeeds when the README already has a mark list"
fi

entry_line=$(grep -n -- '- `U+E910` — testmark2' "$TEST_HOME/README.md" | cut -d: -f1)
docs_line=$(grep -n -- '## Other docs' "$TEST_HOME/README.md" | cut -d: -f1)
if [[ -n $entry_line && -n $docs_line && $entry_line -lt $docs_line ]]; then
  pass "the new mark is inserted after the last mark, not at the end"
else
  fail "the new mark is inserted after the last mark, not at the end"
fi
