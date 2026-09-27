#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/stubs"
test_home="$test_tmp/home"
mkdir -p "$stub_bin" "$test_home"

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

write_stub omarchy-cmd-present 'exit 1'
write_stub omarchy-notification-send 'exit 0'

app_dir="$test_tmp/apps"
mkdir -p "$app_dir/sub"

# A top-level web app and one nested in a subdirectory, as installs
# predating the name validation could produce.
cat >"$app_dir/Top App.desktop" <<'EOF'
[Desktop Entry]
Name=Top App
Exec=omarchy-launch-webapp https://example.com/top
Type=Application
EOF
cat >"$app_dir/sub/Nested App.desktop" <<'EOF'
[Desktop Entry]
Name=Nested App
Exec=omarchy-launch-webapp https://example.com/nested
Type=Application
EOF

HOME="$test_home" PATH="$stub_bin:$ROOT/bin:$PATH" \
  "$ROOT/bin/omarchy-webapp-remove-all" "$app_dir" >/dev/null

[[ ! -e "$app_dir/Top App.desktop" ]] || fail "remove-all deletes top-level web apps"
pass "webapp-remove-all deletes top-level web apps"

[[ ! -e "$app_dir/sub/Nested App.desktop" ]] || \
  fail "webapp-remove-all deletes nested web app launchers" "survivor: $app_dir/sub/Nested App.desktop"
pass "webapp-remove-all deletes nested web app launchers"
