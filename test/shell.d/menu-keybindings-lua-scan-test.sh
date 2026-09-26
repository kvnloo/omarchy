#!/bin/bash

# Tip #13276: the Lua bind-scan stub must survive qconsole-like comparisons so
# user bindings declared after default.hypr.qconsole still reach the source map.

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua

tmpdir=$(mktemp -d) && [[ -n $tmpdir && -d $tmpdir ]] ||
  fail "the test gets a temporary directory"
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
mkdir -p "$home/.config/hypr"

# Minimal user config: exercise the metamethods tip #13276 adds, then declare a
# bind that only lands in the source map if the scan keeps going.
cat >"$home/.config/hypr/hyprland.lua" <<'LUA'
local mon = hl.get_active_monitor()
-- qconsole.lua compares and divides by monitor.scale; without __lt/__div the
-- scan aborts here and never reaches the user bind below.
if mon and mon.scale and mon.scale > 0 then
  local _ = mon.width / mon.scale
end
-- ipairs must terminate: a stub that answers positive integer keys hangs.
for _, _ in ipairs(hl.get_monitors()) do
end
hl.bind("SUPER + W", "reprieve close", { description = "Close parked window" })
LUA

# Drive the exact Lua heredoc shipped in omarchy-menu-keybindings.
start=$(grep -n "lua <<'LUA'" "$ROOT/bin/omarchy-menu-keybindings" | head -1 | cut -d: -f1)
end=$(grep -n "^LUA$" "$ROOT/bin/omarchy-menu-keybindings" | head -1 | cut -d: -f1)
(( start > 0 && end > start )) || fail "Lua bind-scan heredoc is present in omarchy-menu-keybindings"
sed -n "$((start + 1)),$((end - 1))p" "$ROOT/bin/omarchy-menu-keybindings" >"$tmpdir/scan.lua"

tsv=$(
  HOME="$home" OMARCHY_PATH="$ROOT" lua "$tmpdir/scan.lua" 2>"$tmpdir/stderr"
) || fail "Lua bind scan exits successfully"

! grep -q 'lua bind scan failed' "$tmpdir/stderr" ||
  fail "Lua bind scan must survive monitor comparisons" "$(cat "$tmpdir/stderr")"
pass "Lua bind scan survives monitor comparisons and ipairs"

[[ $tsv == *$'\tClose parked window\tW\texec\treprieve close'* ]] ||
  fail "scan recovers exec dispatcher for the user bind" "tsv: $tsv"
pass "scan recovers exec dispatcher for the user bind"

# Cache key bump is what retires poisoned keybindings-*.records after the tip.
grep -q "printf 'v14\\\\n'" "$ROOT/bin/omarchy-menu-keybindings" ||
  fail "keybindings cache key is bumped to v14"
pass "keybindings cache key is bumped to v14"
