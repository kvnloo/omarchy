#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stubdir="$tmpdir/stubs"
mkdir -p "$stubdir"

# Every external the script touches is stubbed; invocations are logged.
cat >"$stubdir/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$STUB_LOG"
if [[ $1 == -v && -n ${SUDO_V_FAIL:-} ]]; then exit 1; fi
if [[ $* == *tailscaled.service* && -n ${DISABLE_FAIL:-} ]]; then exit 1; fi
exit 0
EOF
for c in tailscale systemctl omarchy-plugin-disable omarchy-webapp-remove omarchy-pkg-drop; do
  cat >"$stubdir/$c" <<EOF
#!/bin/bash
echo "$c \$*" >>"\$STUB_LOG"
exit 0
EOF
done
chmod +x "$stubdir"/*

run_remove() {
  STUB_LOG="$tmpdir/log" PATH="$stubdir:$PATH" bash "$ROOT/bin/omarchy-remove-service-tailscale" >"$tmpdir/out" 2>"$tmpdir/err"
  echo $?
}

# 1. Cancelled sudo prompt: exit 130 before any teardown.
: >"$tmpdir/log"
rc=$(SUDO_V_FAIL=1 run_remove)
[[ $rc == 130 ]] || fail "cancelled sudo exits 130 (got $rc)"
grep -q "sudo -v" "$tmpdir/log" || fail "sudo -v runs first"
grep -q "plugin-disable" "$tmpdir/log" && fail "cancelled sudo must not tear down the plugin"
grep -q "tailscaled" "$tmpdir/log" && fail "cancelled sudo must not touch tailscaled"
grep -q "Tailscale has been removed" "$tmpdir/out" && fail "cancelled sudo must not print success"
pass "cancelled sudo aborts removal with exit 130"

# 2. Failed tailscaled disable is no longer swallowed: abort, no success line.
: >"$tmpdir/log"
rc=$(DISABLE_FAIL=1 run_remove)
[[ $rc != 0 ]] || fail "failed tailscaled disable must not exit 0 (got $rc)"
grep -q "plugin-disable" "$tmpdir/log" && fail "failed disable must not tear down the plugin"
grep -q "Tailscale has been removed" "$tmpdir/out" && fail "failed disable must not print success"
pass "failed tailscaled disable aborts without success message"

# 3. Happy path still completes.
: >"$tmpdir/log"
rc=$(run_remove)
[[ $rc == 0 ]] || fail "happy path exits 0 (got $rc)"
grep -q "plugin-disable omarchy.tailscale" "$tmpdir/log" || fail "happy path disables the plugin"
grep -q "Tailscale has been removed" "$tmpdir/out" || fail "happy path prints success"
pass "successful removal completes end to end"
