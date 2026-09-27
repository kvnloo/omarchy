#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command tmux

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
mkdir -p "$home"

# A hermetic tmux config: one annotated binding per table the menu reads.
cat >"$test_tmp/tmux.conf" <<'CONF'
bind-key -N "Create window" -T prefix C new-window
bind-key -N "Split pane" -n M-Enter split-window
bind-key -N "Yank selection" -T copy-mode-vi y send-keys -X copy-selection
CONF

rendered=$(env -i PATH="/usr/bin:/bin" HOME="$home" TMUX_CONF="$test_tmp/tmux.conf" \
  OMARCHY_PATH="$ROOT" bash "$ROOT/bin/omarchy-menu-tmux-keybindings" --print)

[[ -n $rendered ]] || fail "the tmux keybindings menu renders with a stubbed server"
pass "the tmux keybindings menu renders with a stubbed server"

# tmux prints the list-keys -P string directly against the key with no
# separator of its own (verified through 3.5a). Without the trailing space the
# menu parses "prefixC" as the table and "Create" as the key, and every row
# renders as mangled text like "PREFIXC + CREATE → window".
grep -q 'PREFIX + C  *→ Create window' <<<"$rendered" ||
  fail "a prefix-table binding renders its key and note" "$rendered"
pass "a prefix-table binding renders its key and note"

grep -q 'ALT + ENTER  *→ Split pane' <<<"$rendered" ||
  fail "a root-table binding renders without a table prefix" "$rendered"
pass "a root-table binding renders without a table prefix"

grep -q 'COPY MODE + y  *→ Yank selection' <<<"$rendered" ||
  fail "a copy-mode-vi binding renders under its table name" "$rendered"
pass "a copy-mode-vi binding renders under its table name"

! grep -Eq 'PREFIX[A-Z]|ROOT[A-Z]' <<<"$rendered" ||
  fail "no table name leaks into a key" "$rendered"
pass "no table name leaks into a key"
