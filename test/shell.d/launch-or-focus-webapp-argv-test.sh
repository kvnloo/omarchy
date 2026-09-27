#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# omarchy-launch-or-focus-webapp builds its eval'd launch command with unquoted
# $@, so an argument carrying $(...) is EXECUTED and arguments with spaces are
# re-split when omarchy-launch-or-focus evals the string.

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TMPDIR="$T"

# Stub the launcher sink with the REAL dispatch line verbatim:
#   eval exec setsid $LAUNCH_COMMAND
cat >"$T/omarchy-launch-or-focus" <<'EOF'
#!/bin/bash
LAUNCH_COMMAND="$2"
eval exec setsid $LAUNCH_COMMAND
EOF
# Stub the browser launcher so nothing real executes; record argv it received.
cat >"$T/omarchy-launch-webapp" <<'EOF'
#!/bin/bash
printf 'argv_count=%d\n' "$#" >"$0.received"
i=1; for a in "$@"; do printf 'arg%d=<%s>\n' "$i" "$a"; i=$((i + 1)); done >>"$0.received"
EOF
chmod +x "$T"/omarchy-launch-or-focus "$T"/omarchy-launch-webapp
export PATH="$T:$ROOT/bin:$PATH"

payload="https://example.com/\$(touch \"$T/pwned\")"
"$ROOT/bin/omarchy-launch-or-focus-webapp" "SomePattern" "$payload" "--flag=a b" >/dev/null 2>&1 || true

failures=0
if [[ -f $T/pwned ]]; then
  fail "command substitution in the URL argument was executed"
  failures=1
else
  pass "payload is not executed"
fi

received=$(cat "$T/omarchy-launch-webapp.received")
if printf '%s' "$received" | grep -q '^arg2=<--flag=a b>$'; then
  pass "'--flag=a b' arrives as one argument"
else
  fail "'--flag=a b' was re-split at eval time" "$received"
  failures=1
fi

[[ $failures -eq 0 ]]
