#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
pkg_log="$test_tmp/pkg.log"
mkdir -p "$stub_bin"

for c in omarchy-hw-intel omarchy-battery-present; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$c"
  chmod +x "$stub_bin/$c"
done
cat >"$stub_bin/omarchy-pkg-add" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_PKG_LOG"
SH
chmod +x "$stub_bin/omarchy-pkg-add"
printf '#!/bin/bash\nexit 0\n' >"$stub_bin/sudo"
chmod +x "$stub_bin/sudo"

write_cpuinfo() {
  printf 'processor\t: 0\nmodel\t\t: %s\nmodel name\t: Fake CPU\n' "$1" >"$test_tmp/cpuinfo"
}

run_lpmd() {
  : >"$pkg_log"
  TEST_PKG_LOG="$pkg_log" OMARCHY_CPUINFO_PATH="$test_tmp/cpuinfo" \
    PATH="$stub_bin:/usr/bin:/bin" \
    bash "$ROOT/install/hardware/intel/lpmd.sh"
}

assert_installs() {
  local model="$1" label="$2"
  write_cpuinfo "$model"
  run_lpmd
  grep -q "intel-lpmd" "$pkg_log" || fail "lpmd installs on $label (model $model)"
  pass "lpmd installs on $label (model $model)"
}

assert_skips() {
  local model="$1" label="$2"
  write_cpuinfo "$model"
  run_lpmd
  [[ ! -s $pkg_log ]] || fail "lpmd skips $label (model $model)"
  pass "lpmd skips $label (model $model)"
}

# Arrow Lake models were missing from the allowlist despite the
# "Alder Lake and newer" comment: 181 (ARL-U), 197 (ARL-H), 198 (ARL-S).
assert_installs 181 "Arrow Lake-U"
assert_installs 197 "Arrow Lake-H"
assert_installs 198 "Arrow Lake-S"

# Previously supported generations still install.
assert_installs 151 "Alder Lake"
assert_installs 170 "Meteor Lake"
assert_installs 189 "Lunar Lake"
assert_installs 204 "Panther Lake"

# Non-hybrid / unsupported models still skip.
assert_skips 60 "Haswell"
assert_skips 999 "unknown model"
