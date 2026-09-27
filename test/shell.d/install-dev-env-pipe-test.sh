#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
sh_log="$test_tmp/sh.log"
opam_log="$test_tmp/opam.log"
mkdir -p "$stub_bin"

# TEST_CURL_MODE: ok | fail | truncate
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
case "${TEST_CURL_MODE:-ok}" in
  ok) echo "# fake installer"; exit 0 ;;
  fail) exit 6 ;;
  truncate) echo "echo PARTIAL-MARKER-RAN"; exit 28 ;;
esac
SH
chmod +x "$stub_bin/curl"

for c in mise omarchy-pkg-add; do
  printf '#!/bin/bash\nexit 0\n' >"$stub_bin/$c"
  chmod +x "$stub_bin/$c"
done
cat >"$stub_bin/sh" <<'SH'
#!/bin/bash
printf 'sh ran: %s\n' "$*" >>"$TEST_SH_LOG"
# Drain stdin only when it is not a terminal, so piped installers are
# recorded without blocking the test.
if [[ ! -t 0 ]]; then
  timeout 2 cat >>"$TEST_SH_LOG" 2>/dev/null || true
fi
SH
chmod +x "$stub_bin/sh"
cat >"$stub_bin/opam" <<'SH'
#!/bin/bash
printf 'opam ran: %s\n' "$*" >>"$TEST_OPAM_LOG"
exit 0
SH
chmod +x "$stub_bin/opam"
# bash -c is used by the script; route it through the stubbed sh logger too.
printf '#!/bin/bash\nexec sh "$@"\n' >"$stub_bin/bash"
chmod +x "$stub_bin/bash"

run_env() {
  : >"$sh_log"
  : >"$opam_log"
  TEST_CURL_MODE="$1" TEST_SH_LOG="$sh_log" TEST_OPAM_LOG="$opam_log" \
    PATH="$stub_bin:/usr/bin:/bin" \
    "$ROOT/bin/omarchy-install-dev-env" "$2"
}

# A failed uv download must abort loudly, never silently succeed.
set +e
run_env fail python >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "python aborts when the uv download fails" "exit=$status"
[[ ! -s $sh_log ]] || fail "sh never runs on a failed uv download" "$(cat "$sh_log")"
pass "python aborts loudly when the uv download fails"

# A truncated uv download must not be executed.
set +e
run_env truncate python >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "python aborts when the uv download is truncated" "exit=$status"
grep -q "PARTIAL-MARKER" "$sh_log" && fail "truncated uv installer is never executed" "$(cat "$sh_log")"
pass "python never executes a truncated uv download"

# A failed rustup download must abort loudly, never no-op with exit 0.
set +e
run_env fail rust >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "rust aborts when the rustup download fails" "exit=$status"
[[ ! -s $sh_log ]] || fail "bash never runs an empty rustup installer" "$(cat "$sh_log")"
pass "rust aborts loudly when the rustup download fails"

# A failed opam download must abort before `opam init`.
set +e
run_env fail ocaml >/dev/null 2>&1
status=$?
set -e
[[ $status -ne 0 ]] || fail "ocaml aborts when the opam download fails" "exit=$status"
[[ ! -s $opam_log ]] || fail "opam never runs on a failed download" "$(cat "$opam_log")"
pass "ocaml aborts loudly when the opam download fails"

# Happy paths still install.
run_env ok python >/dev/null 2>&1 || fail "python installs when the download works"
grep -q "sh ran" "$sh_log" || fail "uv installer runs on a good download"
run_env ok rust >/dev/null 2>&1 || fail "rust installs when the download works"
run_env ok ocaml >/dev/null 2>&1 || fail "ocaml installs when the download works"
grep -q "opam ran" "$opam_log" || fail "opam init runs on a good download"
pass "all three installers run on a good download"
