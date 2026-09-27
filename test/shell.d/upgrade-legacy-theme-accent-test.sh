#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

upgrade_to_quattro="$ROOT/bin/omarchy-upgrade-to-quattro"
require_command awk

# Extracts the named function body. The theme shim embeds a Hyprland config in
# heredocs with bare `}` lines, so a closing brace only ends the function when
# it appears outside a heredoc.
function_body() {
  local name="$1" line inside=0 heredoc_end=""
  while IFS= read -r line; do
    if (( inside == 0 )); then
      [[ $line == "$name() {" ]] && inside=1
      continue
    fi
    if [[ -n $heredoc_end ]]; then
      printf '%s\n' "$line"
      [[ $line == "$heredoc_end" ]] && heredoc_end=""
      continue
    fi
    if [[ $line == *"<<"* ]]; then
      printf '%s\n' "$line"
      local rest=${line#*<<}
      rest=${rest#-}
      rest=${rest//\'/}
      rest=${rest//\"/}
      heredoc_end=${rest%%[[:space:]]*}
      continue
    fi
    [[ $line == "}" ]] && break
    printf '%s\n' "$line"
  done <"$upgrade_to_quattro"
}

eval "write_legacy_theme_hyprland_conf() {
$(function_body write_legacy_theme_hyprland_conf)
}"

# The function shells out through run_as_user; execute the heredoc directly.
run_as_user() { "$@"; }

temp_dirs=()
cleanup() { rm -rf "${temp_dirs[@]}"; }
trap cleanup EXIT

run_accent_case() {
  local description="$1" colors_content="$2" expected="$3"
  local home
  home=$(mktemp -d)
  temp_dirs+=("$home")
  mkdir -p "$home/.config/hypr" "$home/.local/state/omarchy/current/theme"
  printf 'source = ~/.local/state/omarchy/current/theme/hyprland.conf\n' >"$home/.config/hypr/hyprland.conf"
  if [[ -n $colors_content ]]; then
    printf '%s\n' "$colors_content" >"$home/.local/state/omarchy/current/theme/colors.toml"
  fi

  target_home="$home"
  write_legacy_theme_hyprland_conf

  local generated="$home/.local/state/omarchy/current/theme/hyprland.conf"
  [[ -f $generated ]] || fail "$description (theme shim was not written)"
  if grep -F -x "\$activeBorderColor = rgb($expected)" "$generated" >/dev/null; then
    pass "$description"
  else
    fail "$description" "expected rgb($expected), wrote: $(grep -F '$activeBorderColor' "$generated" || true)"
  fi
}

run_accent_case "quoted accent without comment" \
  'accent = "#7aa2f7"' "7aa2f7"

run_accent_case "quoted accent with trailing comment" \
  'accent = "#7aa2f7" # brand blue' "7aa2f7"

run_accent_case "quoted accent with comment and no padding" \
  'accent="#89b4fa"#tokyo night' "89b4fa"

run_accent_case "unquoted accent with trailing comment" \
  'accent = 7aa2f7 # brand blue' "7aa2f7"

run_accent_case "unquoted accent without comment" \
  'accent = 7aa2f7' "7aa2f7"

run_accent_case "eight-digit accent with trailing comment" \
  'accent = "#7aa2f755" # translucent' "7aa2f755"

run_accent_case "missing accent falls back to the default" \
  'background = "#1a1b26"' "7aa2f7"

run_accent_case "missing colors.toml falls back to the default" \
  '' "7aa2f7"

run_accent_case "malformed accent falls back to the default" \
  'accent = "not-a-color" # oops' "7aa2f7"
