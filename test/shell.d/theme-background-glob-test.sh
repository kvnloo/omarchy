#!/bin/bash

set -euo pipefail

# Re-setting the active theme cycles to the next background. Background paths
# are compared in [[ == ]], where an unquoted right-hand side is a pattern, so
# a filename holding glob characters (`[`, `]`, `*`) never matched itself and
# rotation pinned at the first background instead of advancing.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
state="$home/.local/state/omarchy/current"
themes="$home/.config/omarchy/themes"
mkdir -p "$state" "$themes"

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

set_theme() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" \
    OMARCHY_THEME_HEADLESS=1 XDG_RUNTIME_DIR="$test_tmp" \
    bash "$ROOT/bin/omarchy-theme-set" "$1" >/dev/null 2>&1 || return $?
}

current_background() {
  readlink "$state/background"
}

# Background filenames holding glob metacharacters.
glob="$themes/globbg"
mkdir -p "$glob/backgrounds"
write_colors "$glob/colors.toml"
printf 'a' >"$glob/backgrounds/[a].png"
printf 'b' >"$glob/backgrounds/b.png"

set_theme globbg || fail "omarchy-theme-set applies a theme whose backgrounds hold glob characters"
[[ $(current_background) == */'[a].png' ]] || \
  fail "the first set picks the first background" "$(current_background)"

set_theme globbg || fail "omarchy-theme-set reapplies the active theme"
[[ $(current_background) == */b.png ]] || \
  fail "reapplying the active theme advances past a glob-character background" "$(current_background)"

set_theme globbg || fail "omarchy-theme-set reapplies the active theme a third time"
[[ $(current_background) == */'[a].png' ]] || \
  fail "rotation wraps back to the first background" "$(current_background)"

pass "background rotation advances past filenames holding glob characters"

# Ordinary filenames still cycle exactly as before.
plain="$themes/plainbg"
mkdir -p "$plain/backgrounds"
write_colors "$plain/colors.toml"
printf '1' >"$plain/backgrounds/1.png"
printf '2' >"$plain/backgrounds/2.png"

set_theme plainbg || fail "omarchy-theme-set applies a plain theme"
[[ $(current_background) == */1.png ]] || fail "the first set picks the first background"
set_theme plainbg || fail "omarchy-theme-set reapplies the plain theme"
[[ $(current_background) == */2.png ]] || \
  fail "reapplying the active theme still cycles plain filenames" "$(current_background)"

pass "plain background filenames still cycle"
