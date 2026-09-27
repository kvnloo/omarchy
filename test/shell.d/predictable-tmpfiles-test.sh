#!/bin/bash

set -euo pipefail

source "$(dirname -- "${BASH_SOURCE[0]}")/base-test.sh"

work_dir=$(mktemp -d)
stub_dir="$work_dir/stubs"
mkdir -p "$stub_dir"

cleanup() {
  rm -f /tmp/upload-log.txt /tmp/omarchy-debug.log /tmp/omarchy-battlenet-installer.log
  rm -rf "$work_dir"
}
trap cleanup EXIT

# A pre-planted symlink at the fixed /tmp path redirects the script's write
# into an attacker-chosen file on the base version. Fixed scripts must never
# touch the fixed path.

# ---------- omarchy-upload-log ----------
cat >"$stub_dir/omarchy-cmd-present" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$stub_dir/curl" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" >>"$CURL_ARGS_LOG"
echo "https://logs.omarchy.org/fake-url"
exit 0
EOF
chmod +x "$stub_dir"/omarchy-cmd-present "$stub_dir"/curl

victim="$work_dir/victim-upload.txt"
: >"$victim"
ln -sf "$victim" /tmp/upload-log.txt
export CURL_ARGS_LOG="$work_dir/curl-args.txt"

PATH="$stub_dir:$PATH" bash "$ROOT/bin/omarchy-upload-log" install >/dev/null 2>&1 || true

if [[ -s $victim ]]; then
  fail "omarchy-upload-log does not follow a planted symlink at /tmp/upload-log.txt"
fi
pass "omarchy-upload-log does not follow a planted symlink at /tmp/upload-log.txt"

uploaded_file=$(grep -o 'file=@[^ ]*' "$CURL_ARGS_LOG" | head -1 | sed 's/^file=@//')
[[ $uploaded_file == /tmp/omarchy-upload-log.* ]] || fail "upload-log uses a private temp file" "file=$uploaded_file"
pass "omarchy-upload-log uploads a private temp file"

[[ -e $uploaded_file ]] && fail "upload-log cleans up its temp file"
pass "omarchy-upload-log cleans up its temp file"
rm -f /tmp/upload-log.txt

# ---------- omarchy-debug ----------
for cmd in inxi journalctl pacman expac; do
  cat >"$stub_dir/$cmd" <<EOF
#!/bin/bash
echo "stub-$cmd-output"
exit 0
EOF
  chmod +x "$stub_dir/$cmd"
done

victim="$work_dir/victim-debug.txt"
: >"$victim"
ln -sf "$victim" /tmp/omarchy-debug.log

PATH="$stub_dir:$PATH" bash "$ROOT/bin/omarchy-debug" --no-sudo --print >"$work_dir/debug-out.txt" 2>&1 || true

if [[ -s $victim ]]; then
  fail "omarchy-debug does not follow a planted symlink at /tmp/omarchy-debug.log"
fi
pass "omarchy-debug does not follow a planted symlink at /tmp/omarchy-debug.log"
grep -q "stub-inxi-output" "$work_dir/debug-out.txt" || fail "omarchy-debug --print still emits the debug payload"
pass "omarchy-debug --print still emits the debug payload"
rm -f /tmp/omarchy-debug.log

# ---------- omarchy-install-gaming-battlenet ----------
cat >"$stub_dir/omarchy-pkg-add" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$stub_dir/omarchy-install-gaming-gpu-lib32" <<'EOF'
#!/bin/bash
exit 0
EOF
cat >"$stub_dir/curl" <<'EOF'
#!/bin/bash
while (( $# > 0 )); do
  if [[ $1 == "--output" ]]; then
    : >"$2"
    shift 2
  else
    shift
  fi
done
exit 0
EOF
cat >"$stub_dir/update-desktop-database" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$stub_dir"/omarchy-pkg-add "$stub_dir"/omarchy-install-gaming-gpu-lib32 "$stub_dir"/curl "$stub_dir"/update-desktop-database

victim="$work_dir/victim-battlenet.txt"
: >"$victim"
ln -sf "$victim" /tmp/omarchy-battlenet-installer.log
export HOME="$work_dir/home"
mkdir -p "$HOME"

log_line=$(PATH="$stub_dir:$PATH" bash "$ROOT/bin/omarchy-install-gaming-battlenet" 2>/dev/null | grep "Installer log:" || true)
sleep 1

if [[ -s $victim ]]; then
  fail "battlenet installer log does not follow a planted symlink"
fi
pass "battlenet installer log does not follow a planted symlink"

log_path=${log_line#Installer log: }
[[ $log_path == /tmp/omarchy-battlenet-installer-log.* ]] || fail "battlenet reports a private installer log path" "path=$log_path"
pass "battlenet reports a private installer log path"
rm -f /tmp/omarchy-battlenet-installer.log

pass "no fixed /tmp temp files are followed through planted symlinks"
