#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/hyprctl" <<'SH'
#!/bin/bash
[[ $1 == "-j" ]] || exit 2

case "$2" in
  monitors) printf '%s\n' "$OMARCHY_TEST_MONITORS_JSON" ;;
  workspaces) printf '%s\n' "$OMARCHY_TEST_WORKSPACES_JSON" ;;
  clients) printf '%s\n' "$OMARCHY_TEST_CLIENTS_JSON" ;;
  activeworkspace) printf '%s\n' "$OMARCHY_TEST_ACTIVE_WORKSPACE_JSON" ;;
  activewindow) printf '%s\n' "$OMARCHY_TEST_ACTIVE_WINDOW_JSON" ;;
  *) exit 2 ;;
esac
SH
chmod +x "$mock_bin/hyprctl"

cat >"$mock_bin/socat" <<'SH'
#!/bin/bash
printf '%s\n' \
  'openwindow>>0xabc,1,foot,Agent' \
  'monitoraddedv2>>1,DP-1,Secondary'
SH
chmod +x "$mock_bin/socat"

monitors='[
  {"id":0,"name":"HDMI-A-1","description":"Primary","width":1920,"height":1080,"x":0,"y":0,"scale":1.0,"transform":0,"focused":true,"activeWorkspace":{"id":1},"specialWorkspace":{"id":0}},
  {"id":1,"name":"DP-1","description":"Secondary","width":2560,"height":1440,"x":1920,"y":0,"scale":1.0,"transform":0,"focused":false,"activeWorkspace":{"id":2},"specialWorkspace":{"id":0}}
]'
workspaces='[
  {"id":1,"name":"1","monitor":"HDMI-A-1","monitorID":0,"windows":1,"hasfullscreen":false,"lastwindow":"0xabc"},
  {"id":2,"name":"2","monitor":"DP-1","monitorID":1,"windows":1,"hasfullscreen":false,"lastwindow":"0xdef"}
]'
clients='[
  {"address":"0xabc","mapped":true,"hidden":false,"pid":101,"class":"foot","initialClass":"foot","title":"Agent","initialTitle":"foot","at":[10,20],"size":[800,600],"workspace":{"id":1},"monitor":0,"floating":false,"fullscreen":0},
  {"address":"0xdef","mapped":true,"hidden":false,"pid":202,"class":"chromium","initialClass":"chromium","title":"Docs","initialTitle":"Chromium","at":[2100,100],"size":[1200,900],"workspace":{"id":2},"monitor":1,"floating":false,"fullscreen":0}
]'
active_workspace='{"id":1}'
active_window='{"address":"0xabc","pid":101}'

run_state() {
  PATH="$mock_bin:$PATH" \
    HYPRLAND_INSTANCE_SIGNATURE="fixture-instance" \
    OMARCHY_TEST_MONITORS_JSON="$monitors" \
    OMARCHY_TEST_WORKSPACES_JSON="$workspaces" \
    OMARCHY_TEST_CLIENTS_JSON="$clients" \
    OMARCHY_TEST_ACTIVE_WORKSPACE_JSON="$active_workspace" \
    OMARCHY_TEST_ACTIVE_WINDOW_JSON="$active_window" \
    "$ROOT/bin/omarchy-desktop-state"
}

first=$(run_state)
second=$(run_state)

jq -e '
  .schema == "omarchy.desktop-state.v1"
  and .compositor.kind == "hyprland"
  and .compositor.instance == "fixture-instance"
  and (.monitors | length) == 2
  and .monitors[1].x == 1920
  and (.workspaces | length) == 2
  and (.windows | length) == 2
  and .windows[1].id == "0xdef"
  and .active.workspace == 1
  and .active.window == "0xabc"
  and (.revision | test("^[0-9a-f]{64}$"))
' <<<"$first" >/dev/null || fail "desktop state returns normalized structured state"

[[ $(jq -r '.revision' <<<"$first") == $(jq -r '.revision' <<<"$second") ]] ||
  fail "desktop state revision is deterministic for unchanged state"

reordered_monitors=$(jq -c 'reverse' <<<"$monitors")
reordered_workspaces=$(jq -c 'reverse' <<<"$workspaces")
reordered_clients=$(jq -c 'reverse' <<<"$clients")
reordered=$(
  monitors=$reordered_monitors
  workspaces=$reordered_workspaces
  clients=$reordered_clients
  run_state
)
[[ $(jq -r '.revision' <<<"$first") == $(jq -r '.revision' <<<"$reordered") ]] ||
  fail "desktop state revision changes when compositor enumeration order changes"

pass "desktop state normalizes Hyprland state with a stable revision"

changed_clients=${clients/\[2100,100\]/[2200,100]}
changed=$(
  clients=$changed_clients
  run_state
)

[[ $(jq -r '.revision' <<<"$first") != $(jq -r '.revision' <<<"$changed") ]] ||
  fail "desktop state revision changes when semantic desktop state changes"

jq -e '.windows[1].x == 2200' <<<"$changed" >/dev/null ||
  fail "desktop state publishes updated window geometry"

pass "desktop state revision tracks semantic changes"

if PATH="$mock_bin:$PATH" \
  OMARCHY_TEST_MONITORS_JSON='{}' \
  OMARCHY_TEST_WORKSPACES_JSON="$workspaces" \
  OMARCHY_TEST_CLIENTS_JSON="$clients" \
  OMARCHY_TEST_ACTIVE_WORKSPACE_JSON="$active_workspace" \
  OMARCHY_TEST_ACTIVE_WINDOW_JSON="$active_window" \
  "$ROOT/bin/omarchy-desktop-state" >/dev/null 2>&1; then
  fail "desktop state accepts malformed monitor payload"
fi

pass "desktop state fails closed on malformed compositor payloads"

events=$(
  PATH="$mock_bin:$PATH" \
    XDG_RUNTIME_DIR="$test_tmp/runtime" \
    HYPRLAND_INSTANCE_SIGNATURE="fixture-instance" \
    "$ROOT/bin/omarchy-desktop-state" --watch
)

jq -s -e '
  length == 2
  and .[0].schema == "omarchy.desktop-event.v1"
  and .[0].type == "invalidate"
  and .[0].event == "openwindow"
  and .[0].data == "0xabc,1,foot,Agent"
  and .[1].event == "monitoraddedv2"
' <<<"$events" >/dev/null || fail "desktop state watch normalizes Hyprland invalidation events"

pass "desktop state watch exposes compositor invalidations without polling"
