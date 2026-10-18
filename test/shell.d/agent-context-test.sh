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
[{"name":"DP-1","focused":true,"serial":"HIDDEN-SERIAL","description":"HIDDEN-MODEL","activeWorkspace":{"id":7,"name":"review"}}]
JSON
cat >"$test_tmp/workspaces" <<'JSON'
[{"id":7,"name":"review","monitor":"DP-1","windows":2,"lastwindowtitle":"HIDDEN-WINDOW-TITLE","lastwindow":"HIDDEN-WINDOW-ID"}]
JSON

out=$(bash "$target" --json)
jq -e '
  .schemaVersion == 1
  and (.monitors | length) == 1
  and .monitors[0].focused == true
  and .monitors[0].activeWorkspace.name == "review"
  and (.workspaces | length) == 1
  and .workspaces[0].windows == 2
  and (.monitors[0] | keys) == ["activeWorkspace","focused","name"]
  and (.workspaces[0] | keys) == ["id","monitor","name","windows"]
' <<<"$out" >/dev/null || fail "agent context returns only allowlisted monitor/workspace fields"
[[ $out != *HIDDEN* ]] || fail "agent context exposes private titles or hardware data"
[[ $(wc -l <"$test_tmp/calls") -eq 2 ]] || fail "agent context makes only two read-only Hyprland queries"
pass "agent context redacts sensitive Hyprland fields"

rm -f "$test_tmp/calls"
status=0
bash "$target" --bad >"$test_tmp/stdout" 2>"$test_tmp/stderr" || status=$?
(( status == 1 )) && [[ ! -s $test_tmp/stdout ]] || fail "agent context rejects unknown flags without output"
[[ ! -e $test_tmp/calls ]] || fail "unknown argument must fail before talking to Hyprland"
pass "agent context rejects unknown arguments without querying the compositor"

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
