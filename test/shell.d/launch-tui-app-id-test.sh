#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/stubs"
mkdir -p "$stub_bin"

export CAPTURE_FILE="$test_tmp/captured-args"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

# Stay in the test process tree: drop the leading -- and run the rest.
write_stub setsid 'exec "$@"'
write_stub uwsm-app 'if [[ ${1:-} == "--" ]]; then shift; fi; exec "$@"'
# Record the exact argv xdg-terminal-exec received, one arg per line.
write_stub xdg-terminal-exec 'printf "%s\n" "$@" > "$CAPTURE_FILE"'

run_as() {
  PATH="$stub_bin:$ROOT/bin:$PATH" "$@"
}

captured() {
  grep -c -- "$1" "$CAPTURE_FILE" 2>/dev/null || true
}

# A whole command line (as keybindings generate) must not break basename:
# the app-id comes from the first word of the command.
: >"$CAPTURE_FILE"
run_as "$ROOT/bin/omarchy-launch-tui" "zsh -c 'echo hi'" 2>"$test_tmp/stderr.txt"
appid=$(grep '^--app-id=' "$CAPTURE_FILE" || true)
[[ $appid == "--app-id=org.omarchy.zsh" ]] || fail "multi-word command yields first-word app-id" "got: $appid"
[[ $(captured "^-e$") == "1" ]] || fail "command still passed via -e"
! grep -q "basename" "$test_tmp/stderr.txt" || fail "no basename error for multi-word command" "$(cat "$test_tmp/stderr.txt")"
pass "multi-word TUI command gets a well-formed first-word app-id"

# Single-word commands keep their existing app-id.
: >"$CAPTURE_FILE"
run_as "$ROOT/bin/omarchy-launch-tui" btop --foo 2>/dev/null
appid=$(grep '^--app-id=' "$CAPTURE_FILE" || true)
[[ $appid == "--app-id=org.omarchy.btop" ]] || fail "single-word command app-id unchanged" "got: $appid"
pass "single-word command app-id unchanged"

# A path command uses its basename.
: >"$CAPTURE_FILE"
run_as "$ROOT/bin/omarchy-launch-tui" /usr/bin/btop 2>/dev/null
appid=$(grep '^--app-id=' "$CAPTURE_FILE" || true)
[[ $appid == "--app-id=org.omarchy.btop" ]] || fail "path command uses basename for app-id" "got: $appid"
pass "path command uses basename for app-id"

# An explicit app-id with spaces must survive as one argument.
: >"$CAPTURE_FILE"
run_as "$ROOT/bin/omarchy-launch-tui" --app-id="my app" btop 2>/dev/null
appid=$(grep '^--app-id=' "$CAPTURE_FILE" || true)
[[ $appid == "--app-id=my app" ]] || fail "explicit app-id passed as one argument" "got: $appid"
[[ $(captured '^app$') == "0" ]] || fail "explicit app-id not word-split"
pass "explicit app-id with spaces passed as one argument"
