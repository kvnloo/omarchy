#!/bin/bash

# omarchy-hyprland-monitor-watch must survive a dead Hyprland socket: it is
# launched once via exec-once with no supervisor, so if socat exits the watcher
# has to reconnect instead of falling off the end of the script.
source "$(dirname "$0")/base-test.sh"

watch="${MONITOR_WATCH_UNDER_TEST:-$ROOT/bin/omarchy-hyprland-monitor-watch}"
[[ -x $watch ]] || fail "monitor watch script is executable: $watch"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/run" "$work/stubs"
export XDG_RUNTIME_DIR="$work/run"
export HYPRLAND_INSTANCE_SIGNATURE="test-sig"
export CALL_LOG="$work/calls"

# Dead socket: socat exits immediately, the way a dead Hyprland socket behaves.
cat >"$work/stubs/socat" <<'SH'
#!/bin/bash
echo "socat $*" >>"$CALL_LOG"
exit 1
SH
for c in omarchy-hyprland-monitor-clamshell omarchy-hyprland-monitor-modeless \
  omarchy-hyprland-monitor-external-active omarchy-hw-laptop \
  omarchy-hyprland-reload-guard; do
  printf '#!/bin/bash\nexit 1\n' >"$work/stubs/$c"
done
chmod +x "$work"/stubs/*
export PATH="$work/stubs:/usr/bin:/bin"

# Give the watcher a few reconnect windows, then kill it. The outer timeout
# bounds the whole run so a runaway loop cannot hang the suite.
timeout 12 bash "$watch" &
watcher=$!
socat_calls=0
for _ in $(seq 1 40); do
  sleep 0.25
  socat_calls=$(grep -c '^socat' "$CALL_LOG" 2>/dev/null || echo 0)
  (( socat_calls >= 2 )) && break
done
kill "$watcher" 2>/dev/null
wait "$watcher" 2>/dev/null

(( socat_calls >= 2 )) || fail "watcher reconnects after socat exits" \
  "socat invocations: $socat_calls (expected >= 2 within the test window)"
pass "watcher reconnects after socat exits (socat invoked $socat_calls times)"
