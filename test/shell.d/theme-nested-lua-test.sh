#!/bin/bash

set -euo pipefail

# The stranger's denied list holds at every depth, not just the top level.
# stage_installed_dir used to copy nested files unchecked, so hyprland/init.lua
# from a repo-installed theme staged verbatim -- and Lua's ?/init.lua fallback
# loads it at login whenever no hyprland.lua was generated (a theme without
# colors.toml gets no templates).

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

marker="omarchy-theme-nested-lua-marker"

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 \
    XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" 2>"$test_tmp/stderr" || return $?
}

staged() {
  printf '%s' "$state/theme/$1"
}

assert_staged() {
  [[ -f $(staged "$1") ]] || fail "$2"
}

assert_not_staged() {
  [[ ! -e $(staged "$1") ]] || fail "$2"
}

# A repo theme with no colors.toml gets no generated Lua, so a nested init.lua
# would previously be the only candidate Lua's require could find.
nested="$themes/nested"
mkdir -p "$nested/hyprland" "$nested/gum_env" "$nested/backgrounds" "$nested/.git"
printf 'os.execute("%s")\n' "$marker" >"$nested/hyprland/init.lua"
printf 'os.execute("%s")\n' "$marker" >"$nested/gum_env/init.lua"
printf 'png\n' >"$nested/backgrounds/ok.png"

set_theme nested || fail "omarchy-theme-set applies a theme with nested directories"

assert_not_staged hyprland/init.lua "a nested hyprland/init.lua is not staged"
assert_not_staged gum_env/init.lua "a nested gum_env/init.lua is not staged"
assert_staged backgrounds/ok.png "benign nested files still stage"
grep -q 'init.lua' "$test_tmp/stderr" || fail "omarchy-theme-set names the nested files it dropped"

pass "nested Lua from a stranger's theme never reaches the staged theme"

# The denied list applies below the top level too.
deep="$themes/deep"
mkdir -p "$deep/sub" "$deep/.git"
printf '{}\n' >"$deep/sub/vscode.json"
printf 'png\n' >"$deep/sub/ok.png"

set_theme deep || fail "omarchy-theme-set applies a theme with a nested denied file"

assert_not_staged sub/vscode.json "a nested vscode.json is not staged"
assert_staged sub/ok.png "benign nested files still stage"

pass "the denied list holds below the top level"

# With colors.toml the generated Lua wins, and the nested copy is dropped too.
shadowed="$themes/shadowed"
mkdir -p "$shadowed/hyprland" "$shadowed/.git"
printf 'os.execute("%s")\n' "$marker" >"$shadowed/hyprland/init.lua"
cat >"$shadowed/colors.toml" <<TOML
mode = "dark"
accent = "#7aa2f7"
background = "#1a1b26"
foreground = "#a9b1d6"
TOML

set_theme shadowed || fail "omarchy-theme-set applies a theme with colors.toml and nested Lua"

assert_staged hyprland.lua "hyprland.lua is generated from Omarchy's template"
! grep -q "$marker" "$(staged hyprland.lua)" || fail "the generated hyprland.lua carries no theme code"
assert_not_staged hyprland/init.lua "the nested init.lua is dropped even when shadowed"

pass "nested Lua loses to the generated file and is dropped"
