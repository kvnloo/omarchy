#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

installer="$ROOT/bin/omarchy-install-service-1password"

grep -q 'omarchy-pkg-add 1password 1password-cli' "$installer" ||
  fail "x86_64 path still uses omarchy-pkg-add"
pass "x86_64 path still uses omarchy-pkg-add"

grep -q '1password-latest.tar.gz' "$installer" ||
  fail "aarch64 path fetches 1password-latest.tar.gz"
pass "aarch64 path fetches 1password-latest.tar.gz"

grep -q 'after-install.sh' "$installer" ||
  fail "aarch64 path runs vendor after-install.sh"
pass "aarch64 path runs vendor after-install.sh"

[[ ! -e $ROOT/bin/omarchy-install-1password ]] ||
  fail "deleted omarchy-install-1password filename stays gone"
pass "deleted omarchy-install-1password filename stays gone"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
opt_dir="$test_tmp/opt/1Password"
payload="$test_tmp/payload"
tarball="$test_tmp/1password-latest.tar.gz"
pkg_log="$test_tmp/pkg.log"
curl_log="$test_tmp/curl.log"
after_log="$test_tmp/after.log"
mkdir -p "$stub_bin" "$payload/1password-8.12.34.arm64"

cat >"$payload/1password-8.12.34.arm64/1password" <<'SH'
#!/bin/bash
echo 8.12.34
SH
cat >"$payload/1password-8.12.34.arm64/after-install.sh" <<SH
#!/bin/bash
printf 'after-install\n' >>"$after_log"
SH
chmod +x "$payload/1password-8.12.34.arm64/1password" "$payload/1password-8.12.34.arm64/after-install.sh"
tar -C "$payload" -czf "$tarball" 1password-8.12.34.arm64

cat >"$stub_bin/uname" <<'SH'
#!/bin/bash
[[ ${1:-} == "-m" ]] || exit 1
printf '%s\n' "${TEST_UNAME:-x86_64}"
SH

cat >"$stub_bin/curl" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$curl_log"
output=
url=
while (( \$# )); do
  case \$1 in
    --output)
      output=\$2
      shift 2
      ;;
    --fail|--location|--retry)
      shift
      [[ \$1 == --retry ]] && shift
      ;;
    http*)
      url=\$1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
[[ \$url == *"/linux/tar/stable/aarch64/1password-latest.tar.gz" ]] || exit 1
[[ -n \$output ]] || exit 1
cp "$tarball" "\$output"
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
exec "$@"
SH

cat >"$stub_bin/omarchy-pkg-add" <<SH
#!/bin/bash
printf '%s\n' "\$*" >>"$pkg_log"
SH

cat >"$stub_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/uwsm-app" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$stub_bin"/*

run_installer() {
  : >"$pkg_log"
  : >"$curl_log"
  : >"$after_log"
  PATH="$stub_bin:$PATH" \
    OMARCHY_1PASSWORD_DIR="$opt_dir" \
    TEST_UNAME="$1" \
    bash "$installer" >/dev/null
}

run_installer x86_64
[[ -f $pkg_log ]] && grep -Fxq '1password 1password-cli' "$pkg_log" ||
  fail "x86_64 still installs via omarchy-pkg-add"
[[ ! -s $curl_log ]] || fail "x86_64 does not fetch the aarch64 tarball"
[[ ! -s $after_log ]] || fail "x86_64 does not run after-install.sh"
pass "x86_64 still installs via omarchy-pkg-add"

rm -rf "$opt_dir"
run_installer aarch64
[[ ! -s $pkg_log ]] || fail "aarch64 does not call omarchy-pkg-add 1password" "$(<"$pkg_log")"
grep -q '1password-latest.tar.gz' "$curl_log" ||
  fail "aarch64 fetches 1password-latest.tar.gz"
grep -Fxq 'after-install' "$after_log" ||
  fail "aarch64 runs vendor after-install.sh"
[[ -x $opt_dir/1password ]] || fail "aarch64 installs into OMARCHY_1PASSWORD_DIR"
pass "aarch64 installs via tarball and after-install.sh"

# Existence-only skip is the original bug: an older leftover must be replaced.
printf '%s\n' '#!/bin/bash' 'echo 8.12.0' >"$opt_dir/1password"
chmod +x "$opt_dir/1password"
: >"$after_log"
run_installer aarch64
grep -Fxq 'after-install' "$after_log" ||
  fail "older /opt/1Password is replaced instead of existence-skipped"
installed=$("$opt_dir/1password" --version)
[[ $installed == "8.12.34" ]] || fail "older leftover is replaced with the tarball version" "$installed"
pass "older leftover is replaced, not existence-skipped"

# Same tarball version is current: skip after-install, still no pacman.
printf '%s\n' '#!/bin/bash' 'echo 8.12.34' >"$opt_dir/1password"
chmod +x "$opt_dir/1password"
: >"$after_log"
: >"$pkg_log"
run_installer aarch64
[[ ! -s $after_log ]] || fail "current tarball version does not re-run after-install.sh"
[[ ! -s $pkg_log ]] || fail "current aarch64 install still skips pacman"
pass "matching tarball version skips reinstall"

rm -rf "$opt_dir"
run_installer arm64
[[ ! -s $pkg_log ]] || fail "arm64 alias does not call omarchy-pkg-add"
grep -Fxq 'after-install' "$after_log" || fail "arm64 alias uses the tarball path"
pass "arm64 alias uses the tarball path"
