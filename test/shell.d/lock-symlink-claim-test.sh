#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

theme_set_bin="$ROOT/bin/omarchy-theme-set"
brightness_bin="$ROOT/bin/omarchy-brightness-display"
export PATH="$ROOT/bin:$PATH"

t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT

# A theme fixture so omarchy-theme-set reaches the lock: with HOME pointed at
# the scratch dir the user theme path below is the only theme source.
mkdir -p "$t/home/.config/omarchy/themes/testtheme"
echo '[colors]' >"$t/home/.config/omarchy/themes/testtheme/colors.toml"
mkdir -p "$t/stubs"
for c in omarchy-theme-set-templates omarchy-notification-send omarchy-hook \
  omarchy-theme-switcher omarchy-theme-bg-cache omarchy-shell \
  omarchy-restart-terminal omarchy-restart-hyprctl omarchy-restart-btop \
  omarchy-restart-opencode omarchy-restart-helix omarchy-theme-set-foot \
  omarchy-theme-set-tmux omarchy-theme-set-gnome omarchy-theme-set-pi \
  omarchy-theme-set-claude omarchy-theme-set-hermes omarchy-theme-set-t3code \
  omarchy-theme-set-browser omarchy-theme-set-vscode omarchy-theme-set-obsidian \
  omarchy-theme-set-keyboard; do
  printf '#!/bin/bash\nexit 0\n' >"$t/stubs/$c"
  chmod +x "$t/stubs/$c"
done

# A planted symlink at the theme lock path must not hand the truncating open
# to the link target: the lock file is only ever created by omarchy-theme-set
# itself, so a link here is always foreign.
echo "precious" >"$t/victim.txt"
ln -s "$t/victim.txt" "$t/xrd/omarchy-theme-set.lock" 2>/dev/null || {
  mkdir -p "$t/xrd"
  ln -s "$t/victim.txt" "$t/xrd/omarchy-theme-set.lock"
}
if HOME="$t/home" XDG_RUNTIME_DIR="$t/xrd" PATH="$t/stubs:$PATH" \
  "$theme_set_bin" testtheme 2>"$t/err"; then
  fail "theme-set refuses a symlinked lock path"
fi
[[ $(<"$t/victim.txt") == "precious" ]] || fail "symlink target is left untouched"
grep -q "omarchy-theme-set.lock" "$t/err" || fail "refusal names the lock path"
[[ ! -e $t/home/.local/state/omarchy/current/next-theme ]] || fail "no staging happened before the refusal"
pass "theme-set refuses a symlinked lock path"

# A planted FIFO must not hang lock acquisition either.
rm -f "$t/xrd/omarchy-theme-set.lock"
mkfifo "$t/xrd/omarchy-theme-set.lock"
if timeout 10 env HOME="$t/home" XDG_RUNTIME_DIR="$t/xrd" PATH="$t/stubs:$PATH" \
  "$theme_set_bin" testtheme 2>/dev/null; then
  fail "theme-set refuses a FIFO lock path"
fi
pass "theme-set refuses a FIFO lock path"

# The normal path still works end to end through the new guard.
rm -f "$t/xrd/omarchy-theme-set.lock"
HOME="$t/home" XDG_RUNTIME_DIR="$t/xrd" PATH="$t/stubs:$PATH" \
  "$theme_set_bin" testtheme >/dev/null 2>&1 || fail "theme-set runs under a fresh lock"
[[ $(<"$t/home/.local/state/omarchy/current/theme.name") == "testtheme" ]] || fail "theme name is recorded"
[[ -f $t/xrd/omarchy-theme-set.lock ]] || fail "lock file is created"
pass "theme-set normal lock acquire and theme switch are unchanged"

# --- omarchy-brightness-display ---

bhome="$t/bhome"
mkdir -p "$t/bstubs"
cat >"$t/bstubs/omarchy-hyprland-monitor-focused" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$t/bstubs/omarchy-hyprland-monitor-focused-apple" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$t/bstubs/omarchy-hw-display" <<'EOF'
#!/bin/bash
echo fakescreen
EOF
cat >"$t/bstubs/brightnessctl" <<EOF
#!/bin/bash
echo "\$@" >>"$t/brightnessctl-args"
if [[ \$* == *"-m"* ]]; then
  echo "fakescreen,backlight,100,50%"
fi
exit 0
EOF
chmod +x "$t/bstubs/"*

# A planted symlink at the brightness lock path must not hand the truncating
# open to the link target: brightness keys are pressed in sessions where
# XDG_RUNTIME_DIR can be unset, so the /tmp fallback is plantable.
echo "precious" >"$t/bvictim.txt"
ln -s "$t/bvictim.txt" "$t/xrd/omarchy-brightness-display.lock"
if XDG_RUNTIME_DIR="$t/xrd" PATH="$t/bstubs:$PATH" \
  "$brightness_bin" --no-osd +5% 2>"$t/berr"; then
  fail "brightness-display refuses a symlinked lock path"
fi
[[ $(<"$t/bvictim.txt") == "precious" ]] || fail "symlink target is left untouched"
grep -q "omarchy-brightness-display.lock" "$t/berr" || fail "refusal names the lock path"
[[ ! -s $t/brightnessctl-args ]] 2>/dev/null || fail "no brightness change happened before the refusal"
pass "brightness-display refuses a symlinked lock path"

# A planted FIFO must not hang lock acquisition either.
rm -f "$t/xrd/omarchy-brightness-display.lock"
mkfifo "$t/xrd/omarchy-brightness-display.lock"
if timeout 10 env XDG_RUNTIME_DIR="$t/xrd" PATH="$t/bstubs:$PATH" \
  "$brightness_bin" --no-osd +5% 2>/dev/null; then
  fail "brightness-display refuses a FIFO lock path"
fi
pass "brightness-display refuses a FIFO lock path"

# The normal path still adjusts brightness through the new guard.
rm -f "$t/xrd/omarchy-brightness-display.lock"
rm -f "$t/brightnessctl-args"
XDG_RUNTIME_DIR="$t/xrd" PATH="$t/bstubs:$PATH" \
  "$brightness_bin" --no-osd +5% >/dev/null 2>&1 || fail "brightness-display runs under a fresh lock"
grep -q "set 55%" "$t/brightnessctl-args" || fail "brightness step is applied past the guard"
[[ -f $t/xrd/omarchy-brightness-display.lock ]] || fail "lock file is created"
pass "brightness-display normal lock acquire and step are unchanged"

# --- fallback lock directory (no XDG_RUNTIME_DIR) ---

# Without XDG_RUNTIME_DIR the lock must land in a private per-UID directory,
# not directly in shared /tmp: that closes the TOCTOU the pre-open check
# could not (another local user swapping the pathname between check and open).
lock_helper="$ROOT/bin/omarchy-lock-dir"
fallback_dir="/tmp/omarchy-lock-$UID"
rm -rf "$fallback_dir"
dir_out=$(env -u XDG_RUNTIME_DIR "$lock_helper") || fail "omarchy-lock-dir works without XDG_RUNTIME_DIR"
[[ $dir_out == "$fallback_dir" ]] || fail "fallback dir is per-UID under /tmp" "$dir_out"
[[ $(stat -c %a "$fallback_dir") == "700" ]] || fail "fallback dir is mode 700"
pass "omarchy-lock-dir creates a private per-UID fallback directory"

# A planted symlink at the fallback directory must be refused, not followed.
rm -rf "$fallback_dir"
ln -s "$t" "$fallback_dir"
if env -u XDG_RUNTIME_DIR "$lock_helper" 2>"$t/ldir-err"; then
  fail "omarchy-lock-dir refuses a symlinked fallback directory"
fi
rm -f "$fallback_dir"
pass "omarchy-lock-dir refuses a symlinked fallback directory"

# End to end: theme-set without XDG_RUNTIME_DIR locks in the private dir and
# applies the theme.
rm -rf "$fallback_dir"
rm -rf "$t/home/.local"
env -u XDG_RUNTIME_DIR HOME="$t/home" PATH="$t/stubs:$ROOT/bin:$PATH" \
  "$theme_set_bin" testtheme >/dev/null 2>&1 || fail "theme-set runs without XDG_RUNTIME_DIR"
[[ $(<"$t/home/.local/state/omarchy/current/theme.name") == "testtheme" ]] || fail "theme name is recorded"
[[ -f $fallback_dir/omarchy-theme-set.lock ]] || fail "lock file is created in the private fallback dir"
rm -rf "$fallback_dir"
pass "theme-set uses the private fallback lock directory end to end"
