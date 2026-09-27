#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# omarchy-launch-or-focus-tui flattened "$@" into an unquoted string that
# omarchy-launch-or-focus evals: arguments with spaces were re-split, $(...)
# executed, and a stray quote killed the launch. The fix %q-quotes each
# argument so the one eval round restores the original argv.
#
# LOFT_UNDER_TEST overrides the script under test (used for red-on-base).

LOFT="${LOFT_UNDER_TEST:-$ROOT/bin/omarchy-launch-or-focus-tui}"
LOF_DIR="$ROOT/bin"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
export TMPDIR="$test_tmp"

stubbin="$test_tmp/stubbin"
mkdir -p "$stubbin"

cat >"$stubbin/hyprctl" <<'EOF'
#!/bin/bash
echo '[]'
EOF
cat >"$stubbin/setsid" <<'EOF'
#!/bin/bash
exec "$@"
EOF
cat >"$stubbin/omarchy-launch-tui" <<EOF
#!/bin/bash
printf 'ltui got %d args:' "\$#" >>"$test_tmp/argv.log"
printf ' <%s>' "\$@" >>"$test_tmp/argv.log"
printf '\n' >>"$test_tmp/argv.log"
EOF
chmod +x "$stubbin"/*

run_loft() {
  : >"$test_tmp/argv.log"
  PATH="$stubbin:$LOF_DIR:/usr/bin:/bin" bash "$LOFT" "$@" >/dev/null 2>"$test_tmp/stderr.log"
  echo "rc=$?"
}

require_command jq

# 1. An argument containing spaces must arrive as one argument.
out=$(run_loft mycmd 'two words')
argv=$(cat "$test_tmp/argv.log")
[[ $argv == "ltui got 2 args: <mycmd> <two words>" ]] \
  || fail "spaced argument re-split" "$argv"
pass "spaced argument survives as one argv word"

# 2. Command substitution inside an argument must not execute.
marker="$test_tmp/pwned"
rm -f "$marker"
run_loft 'btop$(touch "$marker")' >/dev/null
[[ ! -e $marker ]] || fail "command substitution executed" "marker $marker exists"
argv=$(cat "$test_tmp/argv.log")
[[ $argv == 'ltui got 1 args: <btop$(touch "$marker")>' ]] \
  || fail "injection argument mangled" "$argv"
pass "command substitution in an argument does not execute"

# 3. An apostrophe must not break the launch.
out=$(run_loft "don't")
argv=$(cat "$test_tmp/argv.log")
[[ $argv == "ltui got 1 args: <don't>" ]] || fail "apostrophe broke the launch" "$argv"
[[ $out == "rc=0" ]] || fail "apostrophe launch exited nonzero" "$out / $(cat "$test_tmp/stderr.log")"
pass "apostrophe argument launches cleanly"

# 4. --app-id= passthrough still reaches the inner launcher for xdg-terminal-exec.
run_loft --app-id=custom.id mycmd >/dev/null
argv=$(cat "$test_tmp/argv.log")
[[ $argv == "ltui got 2 args: <--app-id=custom.id> <mycmd>" ]] \
  || fail "--app-id passthrough broken" "$argv"
pass "--app-id= still forwarded to omarchy-launch-tui"
