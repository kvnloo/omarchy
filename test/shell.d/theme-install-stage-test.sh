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

write_stub omarchy-theme-set 'exit 0'

export HOME="$test_home"
export PATH="$stub_bin:$ROOT/bin:$PATH"

THEMES_DIR="$test_home/.config/omarchy/themes"

# The user already has a customized "example" theme installed.
mkdir -p "$THEMES_DIR/example"
echo "precious customization" >"$THEMES_DIR/example/colors.toml"

# Case 1: the clone fails (bad URL). The existing theme must survive.
write_stub git 'exit 1'
set +e
out=$("$ROOT/bin/omarchy-theme-install" \
  "https://github.com/example/omarchy-example-theme.git" 2>&1)
rc=$?
set -e
(( rc != 0 )) || fail "theme-install fails when the clone fails"
[[ -f $THEMES_DIR/example/colors.toml ]] || fail "failed install preserves the existing theme" "theme dir was deleted"
grep -q "precious customization" "$THEMES_DIR/example/colors.toml" || fail "existing theme content is intact"
compgen -G "$THEMES_DIR/.install.tmp.*" >/dev/null && fail "failed install cleans up its staging dir"
pass "failed install preserves the existing theme"

# Case 2: the clone succeeds. The new theme swaps into place.
write_stub git 'mkdir -p "$4" && echo "fresh clone" >"$4/colors.toml"'
set +e
out=$("$ROOT/bin/omarchy-theme-install" \
  "https://github.com/example/omarchy-example-theme.git" 2>&1)
rc=$?
set -e
(( rc == 0 )) || fail "theme-install succeeds when the clone succeeds" "rc=$rc out=$out"
grep -q "fresh clone" "$THEMES_DIR/example/colors.toml" || fail "successful install replaces the theme" "$(cat "$THEMES_DIR/example/colors.toml" 2>/dev/null)"
compgen -G "$THEMES_DIR/.install.tmp.*" >/dev/null && fail "successful install cleans up its staging dir"
pass "successful install swaps the staged clone into place"
