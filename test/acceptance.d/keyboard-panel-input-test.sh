#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_output="KeyboardPanel-Test"
created=0
original_monitor=$(hyprctl -j monitors | jq -r '.[] | select(.focused == true).name' | head -n1)

monitor_present() {
  hyprctl -j monitors | jq -e --arg name "$1" '.[] | select(.name == $name)' >/dev/null
}

namespace_count() {
  hyprctl -j layers | jq --arg ns "$1" '[.. | objects | select(.namespace? == $ns)] | length'
}

focus_monitor() {
  hyprctl dispatch "hl.dsp.focus({ monitor = \"$1\" })" >/dev/null 2>&1 ||
    hyprctl dispatch focusmonitor "$1" >/dev/null
}

cleanup() {
  trap - EXIT
  omarchy-shell shell hide omarchy.weather >/dev/null 2>&1 || true
  if [[ -n $original_monitor ]]; then
    focus_monitor "$original_monitor" >/dev/null 2>&1 || true
  fi
  if (( created )); then
    hyprctl output remove "$test_output" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ! monitor_present "$test_output"; then
  hyprctl output create headless "$test_output" >/dev/null ||
    fail "KeyboardPanel acceptance can create a second output"
  created=1
fi
wait_until "KeyboardPanel test output appears" 15 monitor_present "$test_output"

focus_monitor "$test_output" ||
  fail "KeyboardPanel acceptance can focus the second output"
sleep 1

omarchy-shell shell summon omarchy.weather >/dev/null
wait_until "KeyboardPanel opens on a second output" 15 layer_present "omarchy-keyboard-panel"

[[ $(namespace_count "omarchy-keyboard-panel-dismiss") -eq 0 ]] ||
  fail "KeyboardPanel creates no per-monitor dismissal surfaces" "$(hyprctl layers)"
pass "KeyboardPanel creates no per-monitor dismissal surfaces"

[[ $(namespace_count "omarchy-keyboard-panel") -eq 1 ]] ||
  fail "one open panel owns one layer surface" "$(hyprctl layers)"
pass "one open panel owns one layer surface across multiple outputs"

screenshot "success-keyboard-panel-multimonitor-open"

# The existing keyboard-focus prime must still make a keyboard-summoned panel
# own Escape after it settles, including on the synthetic second output.
sleep 1
wtype -k Escape
wait_until "Escape closes KeyboardPanel on the second output" 15 layer_absent "omarchy-keyboard-panel"

# Repeated open/close is the regression shape from #10875: the old design
# created and destroyed N-1 extra fullscreen layer surfaces on every cycle.
for round in 1 2 3; do
  omarchy-shell shell summon omarchy.weather >/dev/null
  wait_until "KeyboardPanel cycle $round opens" 15 layer_present "omarchy-keyboard-panel"
  [[ $(namespace_count "omarchy-keyboard-panel-dismiss") -eq 0 ]] ||
    fail "KeyboardPanel cycle $round creates no dismissal twins" "$(hyprctl layers)"
  omarchy-shell shell hide omarchy.weather >/dev/null
  wait_until "KeyboardPanel cycle $round closes" 15 layer_absent "omarchy-keyboard-panel"
done
pass "KeyboardPanel repeated opens create no extra dismissal surfaces"

trap - EXIT
cleanup
