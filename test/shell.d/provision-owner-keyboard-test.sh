#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-provision-owner"
helpers=$(sed -n '/^set_vconsole_value() {/,/^}/p' "$script")
apply=$(sed -n '/^apply_keyboard() {/,/^}/p' "$script")
[[ -n $helpers && -n $apply ]] || fail "provision-owner keyboard helpers exist"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$scratch/bin"

cat >"$scratch/bin/tty" <<'STUB'
#!/bin/bash
echo /dev/pts/1
STUB

cat >"$scratch/bin/localectl" <<'STUB'
#!/bin/bash
if [[ $* == "--no-pager list-keymaps" ]]; then
  printf '%s\n' us de colemak dvorak
  exit 0
fi
exit 1
STUB

cat >"$scratch/bin/systemd-firstboot" <<'STUB'
#!/bin/bash
for arg in "$@"; do
  case "$arg" in
    --keymap=*) keymap=${arg#--keymap=} ;;
  esac
done
printf 'KEYMAP=%s\n' "$keymap" >"$OMARCHY_VCONSOLE_CONF"
STUB

chmod +x "$scratch/bin/"*

run_case() {
  local keymap="$1"
  local conf="$scratch/$keymap.conf"
  : >"$scratch/log"
  OMARCHY_VCONSOLE_CONF="$conf" LOG_FILE="$scratch/log" PATH="$scratch/bin:$PATH" \
    bash -c "$helpers
$apply
log_step() { :; }
apply_keyboard \"$keymap\""
  printf '%s\n' "$conf"
}

colemak_conf=$(run_case colemak)
grep -Fx 'KEYMAP=colemak' "$colemak_conf" >/dev/null || fail "colemak keeps its console keymap"
grep -Fx 'XKBLAYOUT=us' "$colemak_conf" >/dev/null || fail "colemak writes us XKB layout"
grep -Fx 'XKBVARIANT=colemak' "$colemak_conf" >/dev/null || fail "colemak writes the XKB variant"
pass "colemak persists console and XKB coordinates"

dvorak_conf=$(run_case dvorak)
grep -Fx 'KEYMAP=dvorak' "$dvorak_conf" >/dev/null || fail "dvorak keeps its console keymap"
grep -Fx 'XKBLAYOUT=us' "$dvorak_conf" >/dev/null || fail "dvorak writes us XKB layout"
grep -Fx 'XKBVARIANT=dvorak' "$dvorak_conf" >/dev/null || fail "dvorak writes the XKB variant"
pass "dvorak persists console and XKB coordinates"

de_conf=$(run_case de)
grep -Fx 'KEYMAP=de' "$de_conf" >/dev/null || fail "ordinary layouts still persist their console keymap"
if grep -Eq '^XKB(LAYOUT|VARIANT)=' "$de_conf"; then
  fail "ordinary layouts are not rewritten as special XKB variants" "$(cat "$de_conf")"
fi
pass "ordinary layouts keep the existing firstboot path"
