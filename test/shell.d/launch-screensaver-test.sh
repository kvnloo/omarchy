#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"
: >"$call_log"

# Focus-dismiss policy mirrored from bin/omarchy-screensaver. Keep this table
# in lockstep with the script: never-focused must not self-dismiss (panel
# still open), and focus loss during launch grace must not either.
focus_tick() {
  local in_focus=$1 was_focused=$2 now=$3 grace_until=$4
  if ((in_focus)); then
    printf 'latch\n'
  elif ((was_focused)) && ((now >= grace_until)); then
    printf 'exit\n'
  else
    printf 'keep\n'
  fi
}

[[ $(focus_tick 0 0 0 3) == keep ]] || fail "unfocused before latch stays during grace"
[[ $(focus_tick 0 0 10 3) == keep ]] || fail "never-focused after grace still stays (panel/layer case)"
[[ $(focus_tick 1 0 0 3) == latch ]] || fail "first focus latches"
[[ $(focus_tick 0 1 1 3) == keep ]] || fail "focus loss during grace does not dismiss (multi-monitor hop)"
[[ $(focus_tick 0 1 3 3) == exit ]] || fail "focus loss after grace dismisses"
[[ $(focus_tick 0 1 10 3) == exit ]] || fail "focus loss well after grace dismisses"
pass "screensaver focus-dismiss policy covers panel and multi-monitor launch"

rg -q 'was_focused=0' "$ROOT/bin/omarchy-screensaver" || fail "screensaver latches focus before treating loss as dismiss"
rg -q 'focus_grace_until=\$\(\(SECONDS \+ 3\)\)' "$ROOT/bin/omarchy-screensaver" || fail "screensaver keeps a launch focus grace"
rg -q 'elif \(\(was_focused\)\) && \(\(SECONDS >= focus_grace_until\)\); then' "$ROOT/bin/omarchy-screensaver" || \
  fail "screensaver only exits on lost focus after latch and grace"
pass "omarchy-screensaver encodes the focus latch and launch grace"

rg -q 'closeActivePopout' "$ROOT/shell/plugins/bar/Bar.qml" || fail "bar exposes closeActivePopout"
rg -q 'function closeActivePopout\(\): string' "$ROOT/shell/shell.qml" || fail "shell IPC exposes closeActivePopout"
rg -q 'omarchy-shell -q shell closeActivePopout' "$ROOT/bin/omarchy-launch-screensaver" || \
  fail "launch-screensaver dismisses the active bar popout before spawn"
pass "launch path wires popout dismiss through shell IPC"

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-toggle-enabled" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-shell" <<'SH'
#!/bin/bash
printf 'omarchy-shell %s\n' "$*" >>"$CALL_LOG"
exit 0
SH

cat >"$mock_bin/omarchy-hyprland-monitor-focused" <<'SH'
#!/bin/bash
printf 'eDP-1\n'
SH

cat >"$mock_bin/xdg-terminal-exec" <<'SH'
#!/bin/bash
[[ ${1:-} == --print-id ]] || exit 1
printf 'Alacritty.desktop\n'
SH

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == monitors && $2 == -j ]]; then
  printf '[{"name":"eDP-1","focused":true}]\n'
  exit 0
fi
exit 0
SH

cat >"$mock_bin/jq" <<'SH'
#!/bin/bash
# Monitors pipeline is `hyprctl monitors -j | jq -r '.[] | .name'`.
if [[ $1 == -r && $2 == '.[] | .name' ]]; then
  printf 'eDP-1\n'
  exit 0
fi
exit 1
SH

cat >"$mock_bin/socat" <<'SH'
#!/bin/bash
# Emit one screensaver openwindow so wait_for_screensaver_window returns, then EOF.
printf 'openwindow>>addr,1,org.omarchy.screensaver,Alacritty\n'
SH

chmod +x "$mock_bin"/*

export CALL_LOG="$call_log"
export OMARCHY_PATH="$ROOT"
export XDG_RUNTIME_DIR="$tmpdir/runtime"
export HYPRLAND_INSTANCE_SIGNATURE=test
mkdir -p "$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE"
# Socket path is referenced but never opened — socat is mocked.

PATH="$mock_bin:$PATH" "$ROOT/bin/omarchy-launch-screensaver" force

mapfile -t calls < <(cat "$call_log")
[[ ${calls[0]} == "omarchy-shell -q shell closeActivePopout" ]] ||
  fail "launch dismisses the active popout before any hyprctl work" "calls: ${calls[*]}"

printf '%s\n' "${calls[@]}" | rg -q 'hyprctl dispatch .*org\.omarchy\.screensaver' ||
  fail "launch still spawns the screensaver after dismissing the popout" "calls: ${calls[*]}"
pass "omarchy-launch-screensaver dismisses popout before spawning screensaver"
