#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# hibernation-remove must delete the resume kernel-parameter drop-in that
# hibernation-setup wrote. Leaving it bakes a stale resume= device and offset
# (pointing at the deleted swapfile) into every regenerated boot entry.
# Needs a mount namespace to fake /etc and /swap, so root-only here.

if (( EUID != 0 )); then
  skip "hibernation-remove resume drop-in removal (needs root for a mount namespace)"
  exit 0
fi

if ! command -v unshare >/dev/null; then
  skip "hibernation-remove resume drop-in removal (unshare not available)"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/stubs" "$tmp/fakeroot/etc/mkinitcpio.conf.d" \
  "$tmp/fakeroot/etc/limine-entry-tool.d" "$tmp/fakeroot/swap"

printf 'HOOKS+=(resume)\n' >"$tmp/fakeroot/etc/mkinitcpio.conf.d/omarchy_resume.conf"
printf 'KERNEL_CMDLINE[default]+=" resume=/dev/disk/by-uuid/AAAA resume_offset=12345"\n' \
  >"$tmp/fakeroot/etc/limine-entry-tool.d/resume.conf"
printf '# Btrfs swapfile for system hibernation\n/swap/swapfile none swap defaults,pri=0 0 0\n' \
  >"$tmp/fakeroot/etc/fstab"
: >"$tmp/fakeroot/swap/swapfile"

printf '#!/bin/bash\nexec "$@"\n' >"$tmp/stubs/sudo"
printf '#!/bin/bash\nexit 0\n' >"$tmp/stubs/swapoff"
printf '#!/bin/bash\nif [[ ${1:-} == "--show" ]]; then echo "/swap/swapfile partition 8388604 0 -2"; fi\nexit 0\n' >"$tmp/stubs/swapon"
printf '#!/bin/bash\ncase "$1 $2" in\n"subvolume show") exit 0;;\n"subvolume delete") rm -rf -- "${@: -1}"/* 2>/dev/null; exit 0;;\nesac\nexit 0\n' >"$tmp/stubs/btrfs"
printf '#!/bin/bash\nexit 0\n' >"$tmp/stubs/gum"
printf '#!/bin/bash\ntouch "%s/regen-marker"\nexit 0\n' "$tmp" >"$tmp/stubs/limine-mkinitcpio"
chmod +x "$tmp"/stubs/*

swap_created=0
if [[ ! -d /swap ]]; then
  mkdir -p /swap
  swap_created=1
fi

unshare -m bash -c '
  set -e
  mount --bind "$0/fakeroot/etc" /etc
  mount --bind "$0/fakeroot/swap" /swap
  export PATH="$0/stubs:$PATH"
  bash "$1" >/dev/null
' "$tmp" "$ROOT/bin/omarchy-hibernation-remove"

if (( swap_created == 1 )); then
  rmdir /swap 2>/dev/null || true
fi

[[ ! -f $tmp/fakeroot/etc/limine-entry-tool.d/resume.conf ]] ||
  fail "hibernation-remove deletes the stale resume kernel-parameter drop-in"
[[ ! -f $tmp/fakeroot/etc/mkinitcpio.conf.d/omarchy_resume.conf ]] ||
  fail "hibernation-remove still deletes the mkinitcpio resume hook"
if grep -q swapfile "$tmp/fakeroot/etc/fstab"; then
  fail "hibernation-remove still removes the fstab swap entry"
fi
[[ -f $tmp/regen-marker ]] ||
  fail "hibernation-remove still regenerates the boot entries"

pass "hibernation-remove deletes the stale resume kernel-parameter drop-in"
