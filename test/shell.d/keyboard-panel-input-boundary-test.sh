#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

panel="$ROOT/shell/Ui/KeyboardPanel.qml"

grep -F 'import Quickshell.Hyprland' "$panel" >/dev/null ||
  fail "KeyboardPanel imports the compositor focus-grab integration"

grep -F 'mask: Region { item: card }' "$panel" >/dev/null ||
  fail "KeyboardPanel input is scoped to the visible card"

grep -F 'HyprlandFocusGrab {' "$panel" >/dev/null ||
  fail "KeyboardPanel delegates outside-click dismissal to Hyprland"

grep -F 'active: root.open && root.focusPrimed' "$panel" >/dev/null ||
  fail "KeyboardPanel starts its focus grab only after keyboard-focus priming"

grep -F 'windows: root.anchorWindow ? [root, root.anchorWindow] : [root]' "$panel" >/dev/null ||
  fail "KeyboardPanel keeps the panel and its real bar surface in the focus grab"

grep -F 'onCleared: if (root.open) root.close()' "$panel" >/dev/null ||
  fail "KeyboardPanel closes when compositor focus leaves its owned surfaces"

for obsolete in   'omarchy-keyboard-panel-dismiss'   'function pressTargetAt'   'function forwardBarClick'   '_barStripSize'
do
  if grep -Fq "$obsolete" "$panel"; then
    fail "KeyboardPanel no longer carries the obsolete input path: $obsolete"
  fi
done

pass "KeyboardPanel has one input owner per surface and no synthetic bar click path"
