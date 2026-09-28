#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
mkdir -p "$home"

# Stubs: a fixed sink, a pactl that records mute toggles, a silent OSD.
mkdir -p "$tmpdir/stubbin"
printf '#!/bin/bash\necho testsink\n' >"$tmpdir/stubbin/omarchy-audio-output-sink"
cat >"$tmpdir/stubbin/pactl" <<EOF
#!/bin/bash
case "\$1" in
  get-sink-volume) echo "Volume: front-left: 32768 / 50%" ;;
  get-sink-mute) echo "Mute: no" ;;
  set-sink-mute) printf '%s\n' "\$*" >>"$tmpdir/pactl-calls" ;;
esac
EOF
printf '#!/bin/bash\nexit 0\n' >"$tmpdir/stubbin/omarchy-osd"
chmod +x "$tmpdir/stubbin/"*

# The /tmp fallback is what the symlink attack targets, so run the handler
# the way cron/ssh/env -i would: with XDG_RUNTIME_DIR unset.
run_handler() {
  env -u XDG_RUNTIME_DIR HOME="$home" PATH="$tmpdir/stubbin:$PATH" \
    "$ROOT/bin/omarchy-audio-output-volume" "$@"
}

run_handler mute-toggle
state_file="$home/.local/state/omarchy/omarchy-audio-output-volume-mute-toggle.last"
[[ -f $state_file ]] ||
  fail "debounce timestamp lands in the user state dir" "missing: $state_file"
pass "debounce timestamp lands in the user state dir"

[[ ! -e /tmp/omarchy-audio-output-volume-mute-toggle.last ]] ||
  fail "debounce timestamp does not touch /tmp"
pass "debounce timestamp does not touch /tmp"

# Attacker plants a symlink at the old predictable /tmp name pointing at a
# victim-writable file: the write must not follow it.
rm -f "$state_file" "$tmpdir/pactl-calls"
printf 'precious\n' >"$tmpdir/victim.txt"
ln -s "$tmpdir/victim.txt" /tmp/omarchy-audio-output-volume-mute-toggle.last
run_handler mute-toggle
rm -f /tmp/omarchy-audio-output-volume-mute-toggle.last
[[ $(cat "$tmpdir/victim.txt") == "precious" ]] ||
  fail "planted symlink is not followed" "$(cat "$tmpdir/victim.txt")"
pass "planted symlink is not followed"

# Attacker plants a huge timestamp at the old /tmp name: the mute key must
# still toggle instead of exiting early on (now - last < 250).
rm -f "$state_file" "$tmpdir/pactl-calls"
printf '9999999999999\n' > /tmp/omarchy-audio-output-volume-mute-toggle.last
run_handler mute-toggle
rm -f /tmp/omarchy-audio-output-volume-mute-toggle.last
grep -q "set-sink-mute testsink toggle" "$tmpdir/pactl-calls" 2>/dev/null ||
  fail "planted timestamp does not disable the mute key" "$(cat "$tmpdir/pactl-calls" 2>/dev/null)"
pass "planted timestamp does not disable the mute key"
