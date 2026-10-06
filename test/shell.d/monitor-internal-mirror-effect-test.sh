#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
home="$tmpdir/home"
state="$home/.local/state/omarchy/toggles/hypr"
mkdir -p "$mock_bin" "$state"
call_log="$tmpdir/calls"
: >"$call_log"

# Compositor fixture: after reload, either honor the mirror toggle or keep extended.
# MODE=override simulates hyprmoncfg (or any last-wins layout) leaving mirrorOf none.
cat >"$tmpdir/monitors.json" <<'JSON'
[
  {"name":"eDP-1","mirrorOf":"none","disabled":false},
  {"name":"DP-2","mirrorOf":"none","disabled":false,"x":1280,"y":0}
]
JSON

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf '%s %s\n' "hyprctl" "$*" >>"$CALL_LOG"
case "$*" in
  "monitors -j")
    # Pre-toggle discovery of the first active external.
    cat <<'JSON'
[
  {"name":"eDP-1","mirrorOf":"none","disabled":false},
  {"name":"DP-2","mirrorOf":"none","disabled":false,"x":1280,"y":0}
]
JSON
    ;;
  "monitors all -j")
    if [[ ${MIRROR_EFFECT:-override} == honor ]]; then
      cat <<'JSON'
[
  {"name":"eDP-1","mirrorOf":"none","disabled":false},
  {"name":"DP-2","mirrorOf":"eDP-1","disabled":false,"x":0,"y":0}
]
JSON
    else
      cat "$MONITORS_JSON"
    fi
    ;;
  reload)
    ;;
  *)
    ;;
esac
SH

cat >"$mock_bin/omarchy-hyprland-monitor-laptop" <<'SH'
#!/bin/bash
printf 'eDP-1\n'
SH

cat >"$mock_bin/omarchy-hyprland-toggle" <<'SH'
#!/bin/bash
printf 'toggle %s\n' "$*" >>"$CALL_LOG"
# off for disable toggle: just succeed
exit 0
SH

cat >"$mock_bin/omarchy-hyprland-toggle-disabled" <<'SH'
#!/bin/bash
# Mirror toggle is currently absent → disabled → on() may enable it.
[[ ! -f "$HOME/.local/state/omarchy/toggles/hypr/$1.lua" ]]
SH

cat >"$mock_bin/omarchy-hyprland-toggle-enabled" <<'SH'
#!/bin/bash
[[ -f "$HOME/.local/state/omarchy/toggles/hypr/$1.lua" ]]
SH

cat >"$mock_bin/omarchy-notification-send" <<'SH'
#!/bin/bash
printf 'notify %s\n' "$*" >>"$CALL_LOG"
SH

# sleep no-op so verify poll is instant in tests
cat >"$mock_bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$mock_bin"/*

run_mirror() {
  local mode="$1"
  rm -f "$state/internal-monitor-mirror.lua"
  : >"$call_log"
  env HOME="$home" CALL_LOG="$call_log" MONITORS_JSON="$tmpdir/monitors.json" \
    MIRROR_EFFECT="$mode" PATH="$mock_bin:$PATH" \
    "$ROOT/bin/omarchy-hyprland-monitor-internal-mirror" on
}

# --- Case: override (hyprmoncfg / last-wins layout) must not report success ---
set +e
run_mirror override >/dev/null 2>&1
rc=$?
set -e

[[ $rc -ne 0 ]] || fail "mirror on fails when compositor keeps extended layout" "exit=$rc (expected non-zero)"
! grep -F 'Mirroring enabled' "$call_log" >/dev/null ||
  fail "mirror on does not claim success when mirror did not take effect" "calls: $(cat "$call_log")"
grep -F 'Mirror did not take effect' "$call_log" >/dev/null ||
  fail "mirror on reports the override conflict" "calls: $(cat "$call_log")"
[[ ! -f $state/internal-monitor-mirror.lua ]] ||
  fail "mirror on rolls back the toggle when mirror did not take effect"
pass "mirror on fails closed when compositor keeps extended layout"

# --- Case: honor (toggle wins) reports success ---
set +e
run_mirror honor >/dev/null 2>&1
rc=$?
set -e

[[ $rc -eq 0 ]] || fail "mirror on succeeds when compositor applies mirror" "exit=$rc"
grep -F 'Mirroring enabled (DP-2)' "$call_log" >/dev/null ||
  fail "mirror on claims success only after mirror took effect" "calls: $(cat "$call_log")"
[[ -f $state/internal-monitor-mirror.lua ]] ||
  fail "mirror on keeps the toggle when mirror took effect"
pass "mirror on succeeds when compositor applies mirror"

# Static: success notification must follow reload+verify, not precede reload.
# (guards against regressing to notify-before-verify)
awk '
  /hyprctl reload/ { reload++ }
  /Mirroring enabled/ {
    if (reload < 1) { print "success notified before reload"; exit 1 }
  }
' "$call_log" >/dev/null
pass "success notification is only sent after reload verification"
