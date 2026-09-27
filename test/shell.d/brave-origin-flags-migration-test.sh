#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

migration="$ROOT/migrations/1784510887.sh"
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin"

# The migration only acts when the beta package is installed.
cat >"$test_dir/bin/omarchy-pkg-present" <<'STUB'
#!/bin/bash
[[ $1 == brave-origin-beta-bin ]]
STUB
for cmd in omarchy-pkg-aur-add omarchy-pkg-drop omarchy-default-browser; do
  cat >"$test_dir/bin/$cmd" <<'STUB'
#!/bin/bash
exit 0
STUB
done
# Not the beta desktop, so the default-browser switch is skipped.
cat >"$test_dir/bin/xdg-settings" <<'STUB'
#!/bin/bash
echo "chromium.desktop"
STUB
chmod +x "$test_dir/bin/"*

home="$test_dir/home"
flags="$home/.config/brave-origin-flags.conf"

run_migration() {
  HOME="$home" OMARCHY_PATH="$ROOT" PATH="$test_dir/bin:$PATH" \
    bash -euo pipefail "$migration" >/dev/null
}

# A user who customized stable flags before moving to beta keeps them.
mkdir -p "$home/.config"
printf '# my custom flags\n--ozone-platform=wayland\n' >"$flags"
before=$(sha256sum "$flags")

run_migration

[[ $before == $(sha256sum "$flags") ]] ||
  fail "migration preserves an existing brave-origin-flags.conf" "$(cat "$flags")"
pass "migration preserves an existing brave-origin-flags.conf"

# A user without stable flags gets the shipped defaults seeded.
rm -f "$flags"
run_migration

[[ -f $flags ]] || fail "migration seeds brave-origin-flags.conf when absent"
cmp -s "$flags" "$ROOT/config/chromium-flags.conf" ||
  fail "migration seeds the shipped chromium flags" "$(cat "$flags")"
pass "migration seeds brave-origin-flags.conf when absent"

# The dead beta flags file is still cleaned up.
touch "$home/.config/brave-origin-beta-flags.conf"
run_migration

[[ ! -e $home/.config/brave-origin-beta-flags.conf ]] ||
  fail "migration removes the beta flags file"
pass "migration removes the beta flags file"
