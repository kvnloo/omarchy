#!/bin/bash
# Red-on-base: omarchy-tui-remove with a slash in the name escapes the
# applications directory and deletes files it never owned. Fixed: the name is
# refused and removal deletes the indexed launcher path.
source test/shell.d/base-test.sh

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

setup_home() {
  rm -rf "$T/home"
  mkdir -p "$T/home/.local/share/applications" \
    "$T/home/.local/share/icons/hicolor/256x256/apps" \
    "$T/home/.local/share/applications/icons"
  mkdir -p "$T/stubs"
  printf '#!/bin/bash\nexit 0\n' >"$T/stubs/omarchy-menu-select"
  printf '#!/bin/bash\nexit 0\n' >"$T/stubs/omarchy-notification-send"
  chmod +x "$T/stubs"/omarchy-*
}

SCRIPT_UNDER_TEST=${SCRIPT_UNDER_TEST:-"$ROOT/bin/omarchy-tui-remove"}
run_remove() {
  HOME="$T/home" PATH="$T/stubs:$PATH" OMARCHY_REMOVE_NOTIFY=false \
    bash "$SCRIPT_UNDER_TEST" "$@" </dev/null >/dev/null 2>&1
  return $?
}

# 1. red-on-base: "../victim" escapes the applications dir on the unfixed script
setup_home
printf 'victim\n' >"$T/home/.local/share/victim.desktop"
run_remove "../victim"
if [[ -e $T/home/.local/share/victim.desktop ]]; then
  pass "slash name cannot escape the applications dir"
else
  fail "slash name cannot escape the applications dir" \
    "base deleted \$HOME/.local/share/victim.desktop via ../victim"
fi

# 2. fixed: slash name is refused, victim intact, non-zero exit
setup_home
printf 'victim\n' >"$T/home/.local/share/victim.desktop"
if run_remove "../victim"; then
  fail "slash name is refused with non-zero exit" "exit was 0"
elif [[ -e $T/home/.local/share/victim.desktop ]]; then
  pass "slash name is refused with non-zero exit"
else
  fail "slash name is refused with non-zero exit" "victim.desktop was deleted"
fi

# 3. fixed: removing a real indexed TUI launcher still works, icons cleaned
setup_home
cat >"$T/home/.local/share/applications/myapp.desktop" <<'EOF'
[Desktop Entry]
Exec=xdg-terminal-exec --app-id=TUI.myapp -e myapp
EOF
printf 'icon' >"$T/home/.local/share/icons/hicolor/256x256/apps/myapp.png"
run_remove "myapp"
if [[ ! -e $T/home/.local/share/applications/myapp.desktop && ! -e $T/home/.local/share/icons/hicolor/256x256/apps/myapp.png ]]; then
  pass "indexed TUI launcher and icon are removed"
else
  fail "indexed TUI launcher and icon are removed" "launcher or icon still present"
fi

# 4. fixed: plain unknown name is a harmless no-op
setup_home
run_remove "no-such-tui" && pass "unknown plain name is a harmless no-op" ||
  fail "unknown plain name is a harmless no-op" "non-zero exit"
