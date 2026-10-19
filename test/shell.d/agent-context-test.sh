#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq
require_command timeout

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin"
export OMARCHY_AGENT_TEST_DIR="$test_tmp"
target="$ROOT/bin/omarchy-agent-context"

cat >"$test_tmp/bin/hyprctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_AGENT_TEST_DIR/calls"
case "$*" in
  "-j monitors") cat "$OMARCHY_AGENT_TEST_DIR/monitors" ;;
  "-j workspaces") cat "$OMARCHY_AGENT_TEST_DIR/workspaces" ;;
  *) exit 7 ;;
esac
STUB
chmod +x "$test_tmp/bin/hyprctl"
export PATH="$test_tmp/bin:$PATH"

cat >"$test_tmp/monitors" <<'JSON'
[{"name":"DP-1","focused":true,"serial":"HIDDEN-SERIAL","description":"HIDDEN-MODEL","activeWorkspace":{"id":7,"name":"review"}},{"name":"HDMI-A-1","focused":false,"serial":"HIDDEN-OTHER","activeWorkspace":{"id":12,"name":"private"}}]
JSON
cat >"$test_tmp/workspaces" <<'JSON'
[{"id":7,"name":"review","monitor":"DP-1","windows":2,"lastwindowtitle":"HIDDEN-WINDOW-TITLE","lastwindow":"HIDDEN-WINDOW-ID"},{"id":12,"name":"private","monitor":"HDMI-A-1","windows":7,"lastwindowtitle":"HIDDEN-SECOND"}]
JSON

out=$(bash "$target" --json)
jq -e '
  .schemaVersion == 1
  and (.monitors | length) == 2
  and .monitors[0].focused == true
  and .monitors[0].activeWorkspace.name == "review"
  and (.workspaces | length) == 2
  and .workspaces[0].windows == 2
  and (.monitors[0] | keys) == ["activeWorkspace","focused","name"]
  and (.workspaces[0] | keys) == ["id","monitor","name","windows"]
' <<<"$out" >/dev/null || fail "agent context returns only allowlisted monitor/workspace fields"
[[ $out != *HIDDEN* ]] || fail "agent context exposes private titles or hardware data"
[[ $(wc -l <"$test_tmp/calls") -eq 2 ]] || fail "agent context makes only two read-only Hyprland queries"
pass "agent context redacts sensitive Hyprland fields"

focused=$(bash "$target" --focused --json)
jq -e '
  .schemaVersion == 1
  and (.monitors | length) == 1
  and .monitors[0].name == "DP-1"
  and (.workspaces | length) == 1
  and .workspaces[0].id == 7
' <<<"$focused" >/dev/null || fail "focused agent context returns only current monitor and workspace"
[[ $focused != *HIDDEN* && $focused != *HDMI-A-1* && $focused != *private* ]] || fail "focused context leaked an unfocused monitor or workspace"
[[ $(bash "$target" --json --focused) == "$focused" ]] || fail "focused context should accept flags in either order"
pass "focused agent context hides other monitors and workspaces"

rm -f "$test_tmp/calls"
status=0
bash "$target" --bad >"$test_tmp/stdout" 2>"$test_tmp/stderr" || status=$?
(( status == 1 )) && [[ ! -s $test_tmp/stdout ]] || fail "agent context rejects unknown flags without output"
[[ ! -e $test_tmp/calls ]] || fail "unknown argument must fail before talking to Hyprland"
pass "agent context rejects unknown arguments without querying the compositor"

for bad_flags in '--focused --focused' '--json --json'; do
  status=0
  # Intentional word splitting to pass both duplicated flags.
  bash "$target" $bad_flags >"$test_tmp/stdout" 2>"$test_tmp/stderr" || status=$?
  (( status == 1 )) && [[ ! -s $test_tmp/stdout && ! -e $test_tmp/calls ]] || fail "agent context rejects duplicate flags before querying Hyprland"
done
pass "agent context rejects duplicate flags without querying the compositor"

printf 'not json\n' >"$test_tmp/workspaces"
status=0
bash "$target" >"$test_tmp/stdout" 2>"$test_tmp/stderr" || status=$?
(( status == 1 )) && [[ ! -s $test_tmp/stdout ]] || fail "agent context refuses malformed compositor data"
grep -q 'invalid Hyprland response' "$test_tmp/stderr" || fail "agent context explains invalid compositor data"
pass "agent context emits no partial snapshot on malformed Hyprland JSON"

rm -f "$test_tmp/workspaces"
status=0
bash "$target" >"$test_tmp/stdout" 2>"$test_tmp/stderr" || status=$?
(( status == 1 )) && [[ ! -s $test_tmp/stdout ]] || fail "agent context refuses unreadable compositor state"
pass "agent context fails closed when workspace data is unavailable"

cat >"$test_tmp/workspaces" <<'JSON'
[{"id":7,"name":"review","monitor":"DP-1","windows":2},{"id":12,"name":"private","monitor":"HDMI-A-1","windows":7}]
JSON
sed -i 's/"focused":true/"focused":false/' "$test_tmp/monitors"
focused=$(bash "$target" --focused)
jq -e '(.monitors | length) == 0 and (.workspaces | length) == 0' <<<"$focused" >/dev/null || fail "focused agent context must not fall back to exposing other workspaces"
pass "focused context reveals nothing without a focused monitor"
