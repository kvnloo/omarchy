#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

skill="$ROOT/default/agents/skills/hyprland-ui-testing/SKILL.md"

grep -F 'name: hyprland-ui-testing' "$skill" >/dev/null ||
  fail "Hyprland UI testing skill is discoverable"

grep -F 'output="OMARCHY-VIRTUAL-test-$"' "$skill" >/dev/null ||
  fail "Hyprland UI testing uses the reserved virtual-output namespace"

grep -F 'hyprctl output create headless "$output"' "$skill" >/dev/null ||
  fail "Hyprland UI testing creates an isolated headless output"

grep -F 'hyprctl output remove "$output"' "$skill" >/dev/null ||
  fail "Hyprland UI testing tears its headless output down"

grep -F 'workspace = "99 silent"' "$skill" >/dev/null ||
  fail "Hyprland UI testing maps the first frame to a silent test workspace"

grep -F 'no_initial_focus = true' "$skill" >/dev/null ||
  fail "Hyprland UI testing forbids initial focus theft"

grep -F 'monitor = "<test-output> silent"' "$skill" >/dev/null ||
  fail "Hyprland UI testing binds the first frame to the test output"

grep -F 'grim -o "$output"' "$skill" >/dev/null ||
  fail "Hyprland UI testing captures only the isolated output"

grep -F 'hyprctl -j activeworkspace' "$skill" >/dev/null ||
  fail "Hyprland UI testing records workspace state"

grep -F 'hyprctl -j activewindow' "$skill" >/dev/null ||
  fail "Hyprland UI testing records focus state"

grep -F 'Never move the human pointer' "$skill" >/dev/null ||
  fail "Hyprland UI testing forbids pointer theft"

grep -F 'Never switch the user'''s focused monitor or workspace' "$skill" >/dev/null ||
  fail "Hyprland UI testing forbids focusmonitor/workspace theft"

grep -F 'Never load an experimental Hyprland plugin into the live human compositor' "$skill" >/dev/null ||
  fail "Hyprland UI testing keeps plugin development off the live compositor"

grep -F 'A live headless output still shares the human compositor'''s single seat' "$skill" >/dev/null ||
  fail "Hyprland UI testing does not confuse display isolation with multi-seat input"

grep -F 'Concurrent agents must use unique output names' "$skill" >/dev/null ||
  fail "Hyprland UI testing defines parallel-agent isolation"

pass "Hyprland UI testing skill pins focus-safe display isolation"
