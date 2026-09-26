#!/bin/bash

source "$(dirname "$0")/base-test.sh"

TEST_HOME=$(mktemp -d)
trap 'rm -rf "$TEST_HOME"' EXIT

FAKE_BIN="$TEST_HOME/bin"
CURRENT_THEME="$TEST_HOME/.local/state/omarchy/current/theme"
SETTINGS="$TEST_HOME/.config/Code/User/settings.json"
mkdir -p "$FAKE_BIN" "$CURRENT_THEME" "$(dirname "$SETTINGS")"

cat >"$FAKE_BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
[[ $1 == code ]] # only the Code editor exists in this fixture
EOF

cat >"$FAKE_BIN/omarchy-toggle-enabled" <<'EOF'
#!/bin/bash
exit 1
EOF

chmod +x "$FAKE_BIN"/*

run_sync() {
  PATH="$FAKE_BIN:$ROOT/bin:$PATH" HOME="$TEST_HOME" "$ROOT/bin/omarchy-theme-set-vscode"
}

# Set path: a pre-existing value containing an escaped quote must be fully
# replaced, and a theme label containing a comma must land intact.
printf '{"name":"Tokyo Night, Storm"}\n' >"$CURRENT_THEME/vscode.json"
printf '{\n    "editor.fontSize": 14,\n    "workbench.colorTheme": "Old \\"Quoted\\" Theme",\n    "workbench.iconTheme": "x"\n}\n' >"$SETTINGS"

run_sync

jq -e . "$SETTINGS" >/dev/null || fail "VS Code settings stay valid JSON when replacing an escaped-quote value"
[[ $(jq -r '."workbench.colorTheme"' "$SETTINGS") == "Tokyo Night, Storm" ]] ||
  fail "VS Code theme label with a comma is written intact"
pass "VS Code set path replaces escaped-quote values and keeps comma labels"

# Removal path: with no descriptor and no generated theme, a label containing
# a comma or brace must be removed without corrupting the file.
rm -f "$CURRENT_THEME/vscode.json"
printf '{\n    "editor.fontSize": 14,\n    "workbench.colorTheme": "Tokyo Night, Storm",\n    "workbench.iconTheme": "x"\n}\n' >"$SETTINGS"

run_sync

jq -e . "$SETTINGS" >/dev/null || fail "VS Code settings stay valid JSON when removing a comma label"
jq -e 'has("workbench.colorTheme") | not' "$SETTINGS" >/dev/null ||
  fail "VS Code colorTheme key is removed when the theme carries none"
[[ $(jq -r '."workbench.iconTheme"' "$SETTINGS") == "x" ]] ||
  fail "VS Code removal preserves neighboring keys"
pass "VS Code removal path drops comma labels without corrupting settings"
