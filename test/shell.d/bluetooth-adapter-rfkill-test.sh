#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
rfkill_root="$tmpdir/rfkill"
log="$tmpdir/rfkill.log"
powered="$tmpdir/powered"
mkdir -p "$mock_bin" "$rfkill_root"

write_rfkill() {
  local index=$1 name=$2 type=$3 soft=${4:-0}
  local dir="$rfkill_root/rfkill$index"
  mkdir -p "$dir"
  printf '%s\n' "$index" >"$dir/index"
  printf '%s\n' "$name" >"$dir/name"
  printf '%s\n' "$type" >"$dir/type"
  printf '%s\n' "$soft" >"$dir/soft"
}

cat >"$mock_bin/rfkill" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$RFKILL_LOG"
exit 0
SH

cat >"$mock_bin/bluetoothctl" <<'SH'
#!/bin/bash
case "${1:-}" in
  list)
    printf 'Controller AA:BB:CC:DD:EE:01 one\n'
    printf 'Controller AA:BB:CC:DD:EE:02 two\n'
    ;;
  show)
    printf '\tPowered: %s\n' "$(cat "$POWERED_FILE")"
    ;;
  power)
    [[ ${2:-} == on ]] && printf 'yes\n' >"$POWERED_FILE"
    ;;
esac
exit 0
SH

chmod +x "$mock_bin/rfkill" "$mock_bin/bluetoothctl"

run_power() {
  : >"$log"
  PATH="$mock_bin:$PATH" \
    RFKILL_LOG="$log" \
    POWERED_FILE="$powered" \
    OMARCHY_RFKILL_PATH="$rfkill_root" \
    OMARCHY_BLUETOOTH_POWER_WAIT_SECONDS=0 \
    "$ROOT/bin/omarchy-bluetooth-power" "$@"
}

# A ThinkPad-like topology: one platform master plus the real HCI switch.
write_rfkill 0 tpacpi_bluetooth_sw bluetooth 0
write_rfkill 3 hci0 bluetooth 0
write_rfkill 4 phy0 wlan 0
printf 'yes\n' >"$powered"

run_power off
grep -Fx 'block 3' "$log" >/dev/null ||
  fail "Bluetooth off blocks the HCI rfkill" "$(cat "$log")"
if grep -Eq 'block (bluetooth|0)$' "$log"; then
  fail "Bluetooth off never blocks the type or platform master" "$(cat "$log")"
fi
pass "Bluetooth off leaves platform master switches alone"

# Every real Bluetooth controller is part of the global Omarchy on/off state.
write_rfkill 7 hci1 bluetooth 0
run_power off
grep -Fx 'block 3' "$log" >/dev/null ||
  fail "Bluetooth off blocks the first adapter" "$(cat "$log")"
grep -Fx 'block 7' "$log" >/dev/null ||
  fail "Bluetooth off blocks the second adapter" "$(cat "$log")"
[[ $(grep -c '^block ' "$log") -eq 2 ]] ||
  fail "Bluetooth off touches only HCI adapters" "$(cat "$log")"
pass "Bluetooth off spans multiple HCI adapters without widening to the type"

# If only a platform switch remains, refusing is safer than repeating the
# destructive type-wide block that made the adapter disappear in the first place.
rm -rf "$rfkill_root/rfkill3" "$rfkill_root/rfkill7"
if run_power off 2>/dev/null; then
  fail "Bluetooth off refuses when no adapter rfkill is present"
fi
[[ ! -s $log ]] ||
  fail "Bluetooth off performs no rfkill mutation without an adapter" "$(cat "$log")"
pass "Bluetooth off fails closed when only platform rfkills remain"

# On may stay type-wide: unblocking a platform switch cannot power-cut hardware,
# and it is the recovery path for machines already stranded by the old behavior.
printf 'no\n' >"$powered"
run_power on
grep -Fx 'unblock bluetooth' "$log" >/dev/null ||
  fail "Bluetooth on still clears every stale Bluetooth soft block" "$(cat "$log")"
pass "Bluetooth on can recover stale platform blocks"

# Toggle uses the same narrow off path.
rm -rf "$rfkill_root"
mkdir -p "$rfkill_root"
write_rfkill 0 dell-bluetooth bluetooth 0
write_rfkill 5 hci0 bluetooth 0
printf 'yes\n' >"$powered"
run_power toggle
grep -Fx 'block 5' "$log" >/dev/null ||
  fail "Bluetooth toggle uses the adapter-only off path" "$(cat "$log")"
if grep -Eq 'block (bluetooth|0)$' "$log"; then
  fail "Bluetooth toggle never blocks the platform switch" "$(cat "$log")"
fi
pass "Bluetooth toggle shares the adapter-only invariant"
