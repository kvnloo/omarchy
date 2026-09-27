#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
mkdir -p "$tmp_dir/power/BAT0"
printf '900000\n' >"$tmp_dir/power/BAT0/current_now"
printf '12000000\n' >"$tmp_dir/power/BAT0/voltage_now"
cat >"$tmp_dir/bin/upower" <<'STUB'
#!/bin/bash

if [[ $1 == "-e" ]]; then
  echo "/org/freedesktop/UPower/devices/battery_BAT0"
  exit 0
fi

if [[ $1 == "-i" ]]; then
  if [[ ${UPOWER_HOLDING:-} == "1" ]]; then
    cat <<'INFO'
  native-path:          BAT0
  state:                fully-charged
  energy:               45.4 Wh
  energy-full:          56.7 Wh
  energy-rate:          0.1 W
  percentage:           80%
INFO
  else
    cat <<'INFO'
  native-path:          BAT0
  state:                discharging
  energy:               28.3 Wh
  energy-full:          56.7 Wh
  energy-rate:          7.3 W
  time to empty:        2.5 hours
  percentage:           51%
INFO
  fi
  exit 0
fi

exit 1
STUB
chmod +x "$tmp_dir/bin/upower"

shell_output=$(OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)

grep -Fx $'percentage\t51%' <<<"$shell_output" >/dev/null || fail "battery status reports percentage"
grep -Fx $'state\tdischarging' <<<"$shell_output" >/dev/null || fail "battery status reports state"
grep -Fx $'rate\t10.8W' <<<"$shell_output" >/dev/null || fail "battery status reports live sysfs power rate"
grep -Fx $'size\t56Wh' <<<"$shell_output" >/dev/null || fail "battery status reports full capacity"
grep -Fx $'time\t2h 30m' <<<"$shell_output" >/dev/null || fail "battery status reports remaining time"

if matches=$(rg -n 'omarchy-battery-(capacity|remaining|remaining-time)' "$ROOT/bin" "$ROOT/test" "$ROOT/shell" "$ROOT/docs"); then
  fail "battery status owns capacity and remaining calculations" "$matches"
fi

pass "battery status owns capacity and remaining calculations"

# USB-C PD chargers register as type USB, not Mains. Charge-threshold holding
# must detect them as AC or the panel mislabels a held battery.
mkdir -p "$tmp_dir/power2/BAT0" "$tmp_dir/power2/USB1"
printf '80\n' >"$tmp_dir/power2/BAT0/charge_control_end_threshold"
printf 'USB\n' >"$tmp_dir/power2/USB1/type"
printf '1\n' >"$tmp_dir/power2/USB1/online"

holding=$(UPOWER_HOLDING=1 OMARCHY_POWER_SUPPLY_PATH="$tmp_dir/power2" PATH="$tmp_dir/bin:$PATH" "$ROOT/bin/omarchy-battery-status" --shell)
grep -Fx $'state\tholding' <<<"$holding" >/dev/null || fail "USB-PD charger counts as AC for threshold holding" "$holding"
grep -Fx $'threshold\t80%' <<<"$holding" >/dev/null || fail "holding reports the threshold" "$holding"

pass "USB-PD charger counts as AC for threshold holding"
