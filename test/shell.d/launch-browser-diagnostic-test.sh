#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

for command in fixture-browser xdg-settings xdg-mime; do
  printf '#!/bin/bash\nexit 0\n' >"$mock_bin/$command"
done
for command in systemd-run omarchy-cmd-browser-handoff omarchy-hyprland-focus-app; do
  cat >"$mock_bin/$command" <<'EOF'
#!/bin/bash
printf '%s\n' "$0 $*" >>"$OMARCHY_TEST_SIDE_EFFECTS"
exit 1
EOF
done
chmod +x "$mock_bin"/*
export PATH="$mock_bin:$ROOT/bin:$PATH"
export OMARCHY_PATH="$ROOT" HYPRLAND_INSTANCE_SIGNATURE=test XDG_CURRENT_DESKTOP=Hyprland

for mode in missing-default data-home data-dirs; do
  fixture="$test_tmp/$mode"
  mkdir -p "$fixture/home" "$fixture/config" "$fixture/data/applications"
  export HOME="$fixture/home" XDG_CONFIG_HOME="$fixture/config"
  export XDG_CONFIG_DIRS="$fixture/empty-config" XDG_DATA_HOME="$fixture/empty-data"
  export XDG_DATA_DIRS="$fixture/empty-system-data" OMARCHY_TEST_SIDE_EFFECTS="$fixture/effects"

  if [[ $mode != "missing-default" ]]; then
    printf '[Default Applications]\nx-scheme-handler/http=omarchy-fixture-only.desktop;\n' >"$XDG_CONFIG_HOME/mimeapps.list"
    printf '[Desktop Entry]\nExec=fixture-browser %%U\n' >"$fixture/data/applications/omarchy-fixture-only.desktop"
    if [[ $mode == "data-home" ]]; then
      export XDG_DATA_HOME="$fixture/data"
    else
      export XDG_DATA_DIRS="$fixture/data"
    fi
    [[ $(omarchy-cmd-default-browser) == "omarchy-fixture-only.desktop" ]] ||
      fail "the real resolver finds the configured browser in $mode"
  fi

  status=0
  bash "$ROOT/bin/omarchy-launch-browser" "https://example.test/diagnostic" 2>"$fixture/error" || status=$?
  (( status == 1 )) || fail "unresolved browser fails with exit 1 for $mode"
  [[ ! -e $OMARCHY_TEST_SIDE_EFFECTS ]] || fail "unresolved browser causes no handoff, spawn or focus for $mode"
  if [[ $mode == "missing-default" ]]; then
    grep -F "no default browser is set. Choose one with 'omarchy default browser'." "$fixture/error" >/dev/null ||
      fail "missing default keeps its configuration hint"
  else
    grep -F "could not resolve an executable for 'omarchy-fixture-only.desktop'." "$fixture/error" >/dev/null ||
      fail "configured but unresolved browser gets a distinct diagnostic for $mode"
    ! grep -F "no default browser is set" "$fixture/error" >/dev/null ||
      fail "configured browser is not reported as missing for $mode"
  fi
  pass "browser diagnostic distinguishes missing default from unresolved executable for $mode"
done
