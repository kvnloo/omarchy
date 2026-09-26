#!/bin/bash

set -euo pipefail

# A theme checked out as a git submodule or linked worktree carries its git
# metadata as a .git *file* (gitdir: ...) rather than a .git directory. Its
# contents came from a stranger's repo all the same, so omarchy-theme-set must
# hold it to the installed-theme deny list -- a hostile hyprland.lua must not
# reach the staged theme, where Hyprland would load it at startup.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

marker="omarchy-theme-gitfile-marker"

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
    XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" 2>"$test_tmp/stderr" || return $?
}

write_colors() {
  cat >"$1" <<TOML
mode = "dark"

accent = "#7aa2f7"
selection = "#292e42"
muted = "#414868"

background = "#1a1b26"
foreground = "#a9b1d6"

color0 = "#1a1b26"
color1 = "#f7768e"
color2 = "#9ece6a"
color3 = "#e0af68"
color4 = "#7aa2f7"
color5 = "#bb9af7"
color6 = "#7dcfff"
color7 = "#a9b1d6"
TOML
}

# A stranger's theme checked out as a submodule: .git is a file.
evil="$themes/evilsub"
mkdir -p "$evil"
printf 'gitdir: /nowhere/modules/evilsub\n' >"$evil/.git"
write_colors "$evil/colors.toml"
printf 'os.execute("%s")\n' "$marker" >"$evil/hyprland.lua"
printf 'shell = "%s"\n' "$marker" >"$evil/kitty.conf"

set_theme evilsub || fail "omarchy-theme-set applies a submodule-checked-out theme"

! grep -q "$marker" "$state/theme/hyprland.lua" || \
  fail "a submodule checkout cannot supply hyprland.lua"
! grep -q "$marker" "$state/theme/kitty.conf" || \
  fail "a submodule checkout cannot supply kitty.conf"
grep -q '#7aa2f7' "$state/theme/colors.toml" || \
  fail "a submodule checkout keeps its colours"

pass "a .git file marks a stranger's theme like a .git directory"

# A linked worktree checkout is the same shape with a different gitdir target.
work="$themes/evilwork"
mkdir -p "$work"
printf 'gitdir: /home/user/dotfiles/.git/worktrees/evilwork\n' >"$work/.git"
write_colors "$work/colors.toml"
printf 'os.execute("%s")\n' "$marker" >"$work/hyprland.lua"

set_theme evilwork || fail "omarchy-theme-set applies a worktree-checked-out theme"

! grep -q "$marker" "$state/theme/hyprland.lua" || \
  fail "a worktree checkout cannot supply hyprland.lua"

pass "a worktree .git file marks a stranger's theme"

# A theme the user wrote themselves -- no git metadata at all -- is untouched.
mine="$themes/minegitfile"
mkdir -p "$mine"
write_colors "$mine/colors.toml"
printf 'os.execute("%s")\n' "$marker" >"$mine/hyprland.lua"

set_theme minegitfile || fail "omarchy-theme-set applies a theme the user wrote"
grep -q "$marker" "$state/theme/hyprland.lua" || \
  fail "a theme the user wrote keeps its own hyprland.lua"

pass "a theme with no git metadata is still the user's own"
