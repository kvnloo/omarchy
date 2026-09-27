#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/stubs"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

# No-ops for the desktop-integration calls the scripts make.
write_stub gtk-update-icon-cache 'exit 0'
write_stub omarchy-notification-send 'exit 0'
write_stub omarchy-cmd-present 'exit 1'

run_as() {
  HOME="$test_home" PATH="$stub_bin:$ROOT/bin:$PATH" "$@"
}

# Source icons in several formats; install_user_icon keeps the extension.
printf '<svg></svg>\n' >"$test_tmp/icon.svg"
printf 'PNGDATA\n' >"$test_tmp/icon.png"
printf 'JPGDATA\n' >"$test_tmp/icon.jpg"

run_as "$ROOT/bin/omarchy-tui-install" "Ext App" "htop" "tile" "$test_tmp/icon.svg"
run_as "$ROOT/bin/omarchy-tui-install" "Png App" "htop" "float" "$test_tmp/icon.png"
run_as "$ROOT/bin/omarchy-tui-install" "Jpg App" "htop" "tile" "$test_tmp/icon.jpg"

icon_dir="$test_home/.local/share/icons/hicolor/256x256/apps"
app_dir="$test_home/.local/share/applications"

[[ -f $icon_dir/ext-app.svg ]] || fail "install stages the svg icon" "missing $icon_dir/ext-app.svg"
[[ -f $icon_dir/png-app.png ]] || fail "install stages the png icon"
[[ -f $icon_dir/jpg-app.jpg ]] || fail "install stages the jpg icon"
pass "install stages icons with their source extensions"

# Single removal must drop the non-png icon too.
run_as "$ROOT/bin/omarchy-tui-remove" "Ext App"
[[ ! -e $icon_dir/ext-app.svg ]] || fail "tui-remove deletes a non-png installed icon" "orphan: $icon_dir/ext-app.svg"
[[ ! -e $app_dir/Ext\ App.desktop ]] || fail "tui-remove deletes the desktop file"
pass "tui-remove deletes non-png installed icons"

# A planted dotfile must survive the new glob removal.
touch "$icon_dir/.keepme"
run_as "$ROOT/bin/omarchy-tui-remove" "Png App"
[[ -f $icon_dir/.keepme ]] || fail "tui-remove does not touch dotfiles in the icon dir"
[[ ! -e $icon_dir/png-app.png ]] || fail "tui-remove still deletes png icons"
pass "tui-remove glob is safe for dotfiles and png icons"

# remove-all must drop the remaining jpg icon.
run_as "$ROOT/bin/omarchy-tui-remove-all"
[[ ! -e $icon_dir/jpg-app.jpg ]] || fail "tui-remove-all deletes non-png installed icons" "orphan: $icon_dir/jpg-app.jpg"
[[ ! -e $app_dir/Jpg\ App.desktop ]] || fail "tui-remove-all deletes desktop files"
pass "tui-remove-all deletes non-png installed icons"
