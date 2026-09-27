#!/bin/bash
#
# Red-on-base test: omarchy-theme-bg-next must advance to the next background
# even when the user backgrounds dir is a symlink. find -L lists entries by
# their link path while the stored symlink target is the realpath, so the
# string comparison never matches and cycling sticks on the first background.

set -euo pipefail

export TMPDIR=~/workspace/scratch/wave-b/c175/hunt1/tmp
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
ROOT="${TEST_ROOT:-$ROOT}"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

home="$tmp_dir/home"
mkdir -p "$home/bin" "$home/.local/state/omarchy/current/theme/backgrounds" \
  "$home/.config/omarchy/backgrounds" "$home/elsewhere"
touch "$home/.local/state/omarchy/current/theme/backgrounds/a.jpg"
touch "$home/.local/state/omarchy/current/theme/backgrounds/b.jpg"
touch "$home/elsewhere/u1.jpg" "$home/elsewhere/u2.jpg"
ln -s "$home/elsewhere" "$home/.config/omarchy/backgrounds/mytheme"
echo "mytheme" >"$home/.local/state/omarchy/current/theme.name"

# Faithful stand-in for the real omarchy-theme-bg-set: stores realpath target.
cat >"$home/bin/omarchy-theme-bg-set" <<STUB
#!/bin/bash
BACKGROUND="\$(realpath "\$1")"
ln -nsf "\$BACKGROUND" "$home/.local/state/omarchy/current/background"
printf 'SET -> %s\n' "\$BACKGROUND"
STUB
cat >"$home/bin/omarchy-notification-send" <<'STUB'
#!/bin/bash
echo "NOTIFY: $*"
STUB
chmod +x "$home/bin"/*

first=$(HOME="$home" PATH="$home/bin:$PATH" bash "$ROOT/bin/omarchy-theme-bg-next" | grep '^SET')
second=$(HOME="$home" PATH="$home/bin:$PATH" bash "$ROOT/bin/omarchy-theme-bg-next" | grep '^SET')

[[ -n $first && -n $second ]] || fail "both cycles set a background" "first='$first' second='$second'"
[[ $first != "$second" ]] || fail "bg next advances past a symlinked backgrounds dir" "stuck on: $first"

pass "theme-bg-next cycles through symlinked background dirs"
