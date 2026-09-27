#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
omarchy_path="$tmpdir/omarchy"
dotfiles="$tmpdir/dotfiles"

mkdir -p "$home/.config/hypr" "$omarchy_path/config/hypr" "$dotfiles"

# The user manages ~/.config via a dotfiles repo: the config is a symlink.
printf -- '-- user dotfile, version controlled\n' >"$dotfiles/looknfeel.lua"
ln -s "$dotfiles/looknfeel.lua" "$home/.config/hypr/looknfeel.lua"
printf -- '-- omarchy default\n' >"$omarchy_path/config/hypr/looknfeel.lua"

HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/looknfeel.lua >/dev/null

# The symlink target (the user's version-controlled dotfile) must be untouched.
grep -Fq -- '-- omarchy default' "$dotfiles/looknfeel.lua" &&
  fail "refresh-config must not write the default through a symlinked user config"
grep -Fq -- '-- user dotfile, version controlled' "$dotfiles/looknfeel.lua" ||
  fail "refresh-config corrupted the symlink target of the user config"

# The symlink itself is replaced by a regular file holding the default.
[[ -L $home/.config/hypr/looknfeel.lua ]] &&
  fail "refresh-config must replace a symlinked user config, not follow it"
cmp -s "$omarchy_path/config/hypr/looknfeel.lua" "$home/.config/hypr/looknfeel.lua" ||
  fail "refresh-config writes the default into the user config path"

# The backup still reads through the link: it holds the original user content.
backup=$(find "$home/.config/hypr" -name 'looknfeel.lua.bak.*' -print -quit)
[[ -n $backup ]] || fail "refresh-config backs up the replaced user config"
grep -Fq -- '-- user dotfile, version controlled' "$backup" ||
  fail "refresh-config backup contains the user's pre-refresh config"

pass "refresh-config replaces a symlinked user config without touching the link target"

# A dangling symlink (user config removed from the dotfiles repo) must also be
# replaced rather than followed into a materialized target.
ln -s "$dotfiles/does-not-exist" "$home/.config/hypr/monitors.lua"
printf -- '-- omarchy default monitors\n' >"$omarchy_path/config/hypr/monitors.lua"

HOME="$home" OMARCHY_PATH="$omarchy_path" "$ROOT/bin/omarchy-refresh-config" hypr/monitors.lua >/dev/null

[[ -L $home/.config/hypr/monitors.lua ]] &&
  fail "refresh-config must replace a dangling symlinked user config, not follow it"
[[ -e $dotfiles/does-not-exist ]] &&
  fail "refresh-config must not materialize the target of a dangling user config symlink"
cmp -s "$omarchy_path/config/hypr/monitors.lua" "$home/.config/hypr/monitors.lua" ||
  fail "refresh-config writes the default into the user config path"

pass "refresh-config replaces a dangling symlinked user config without touching the link target"
