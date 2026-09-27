#!/bin/bash
#
# Red-on-base test: omarchy-notification-send must accept a lone `--` to end
# option parsing, so a headline/description that is exactly a known option
# token (e.g. "-u") is sent as text instead of being swallowed as an option.

set -euo pipefail

export TMPDIR=~/workspace/scratch/wave-b/c175/hunt1/tmp
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
ROOT="${TEST_ROOT:-$ROOT}"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/bin"
cat >"$tmp_dir/bin/busctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >"${BUSCTL_CAPTURE:?}"
echo "u 99"
STUB
chmod +x "$tmp_dir/bin/busctl"
export BUSCTL_CAPTURE="$tmp_dir/busctl-args"

send="$ROOT/bin/omarchy-notification-send"

# 1. Headline that is exactly a known option token, via --.
if ! out=$(PATH="$tmp_dir/bin:$PATH" "$send" -p -- "-u" "battery low" 2>"$tmp_dir/err"); then
  fail "headline '-u' is accepted after --" "$(cat "$tmp_dir/err")"
fi
[[ $out == "99" ]] || fail "print-id emits the notification id" "got: $out"
grep -Fx -- "-u" "$BUSCTL_CAPTURE" >/dev/null ||
  fail "headline '-u' reaches the bus as the summary" "$(cat "$BUSCTL_CAPTURE")"

# 2. Description that is exactly a known option token, via --.
if ! PATH="$tmp_dir/bin:$PATH" "$send" "head" -- "-g" >/dev/null 2>"$tmp_dir/err"; then
  fail "description '-g' is accepted after --" "$(cat "$tmp_dir/err")"
fi
grep -Fx -- "-g" "$BUSCTL_CAPTURE" >/dev/null ||
  fail "description '-g' reaches the bus as the body" "$(cat "$BUSCTL_CAPTURE")"

# 3. --exec still works after -- in the trailing position.
if ! PATH="$tmp_dir/bin:$PATH" "$send" "head" "desc" -- --exec /bin/true x >/dev/null 2>"$tmp_dir/err"; then
  fail "--exec still works after trailing --" "$(cat "$tmp_dir/err")"
fi
grep -F 'omarchy-exec-argv' "$BUSCTL_CAPTURE" >/dev/null ||
  fail "--exec hint is still attached" "$(cat "$BUSCTL_CAPTURE")"

# 4. Ordinary option parsing is unchanged without --.
if ! out=$(PATH="$tmp_dir/bin:$PATH" "$send" -p -u critical "head" "desc" 2>"$tmp_dir/err"); then
  fail "plain options still parse" "$(cat "$tmp_dir/err")"
fi
[[ $out == "99" ]] || fail "plain invocation still prints id" "got: $out"

pass "notification-send honors -- to end option parsing"
