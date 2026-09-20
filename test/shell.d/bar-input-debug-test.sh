#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

bar="$ROOT/shell/plugins/bar/Bar.qml"
shell="$ROOT/shell/shell.qml"
command="$ROOT/bin/omarchy-debug-bar-input"

grep -Fq 'function debugBarInput()' "$bar" ||
  fail "bar exposes a read-only input diagnostic snapshot"
grep -Fq 'moduleHover.point.position.x' "$bar" ||
  fail "bar input diagnostics read the existing HoverHandler point"
grep -Fq 'moduleHover.point.scenePosition.x' "$bar" ||
  fail "bar input diagnostics include scene coordinates"
grep -Fq 'visualX:' "$bar" ||
  fail "bar input diagnostics include the visual slot origin"
grep -Fq 'visualWidth:' "$bar" ||
  fail "bar input diagnostics include the visual slot bounds"
grep -Fq 'moduleClickTargetAt(slot, slot.pointerX, slot.pointerY)' "$bar" ||
  fail "bar input diagnostics compare hover position with the left-click resolver"
if grep -Eq 'PointHandler|MouseArea.*debug|debug.*MouseArea' "$bar"; then
  fail "bar input diagnostics must not install another pointer-grabbing item"
fi
pass "bar input snapshot observes the existing pointer path without adding a grab"

grep -Fq 'function debugBarInput(): string' "$shell" ||
  fail "shell exposes bar input diagnostics over IPC"
pass "shell exposes bar input diagnostics over IPC"

grep -Fq '# omarchy:summary=Capture bar pointer and hit-test diagnostics' "$command" ||
  fail "bar input diagnostic command declares CLI metadata"
grep -Fq 'omarchy-shell shell debugBarInput' "$command" ||
  fail "bar input diagnostic command captures the live shell pointer state"
grep -Fq 'hyprctl cursorpos' "$command" ||
  fail "bar input diagnostic command captures the compositor cursor"
grep -Fq 'VISUAL_INPUT_DIVERGENCE' "$command" ||
  fail "bar input diagnostic command classifies compositor-vs-QML hit divergence"
grep -Fq 'LEFT_TARGET_DIVERGENCE' "$command" ||
  fail "bar input diagnostic command classifies left-target routing divergence"
grep -Fq 'PATHS_AGREE_AT_CAPTURE' "$command" ||
  fail "bar input diagnostic command names a clean capture instead of overclaiming a cause"
grep -Fq 'hyprctl layers' "$command" ||
  fail "bar input diagnostic command captures layer-shell state"
grep -Fq 'hyprctl monitors -j' "$command" ||
  fail "bar input diagnostic command captures monitor geometry"
pass "bar input diagnostic command correlates shell and compositor state"
