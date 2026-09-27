#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

migration="$ROOT/migrations/1790527000.sh"
install_script="$ROOT/install/config/increase-lockout-limit.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
authfile="$test_tmp/system-auth"
migration_copy="$test_tmp/migration.sh"
mkdir -p "$stub_bin"

# The install script writes the preauth line for new installs: it must be
# audible — a lockout shows up as a lockout, not as a wrong password.
preauth_line=$(grep -E 'pam_faillock\.so.*preauth' "$install_script")
[[ -n $preauth_line ]] || fail "install script still writes a pam_faillock preauth line"
[[ $preauth_line != *silent* ]] ||
  fail "install script preauth line is audible (no silent)" "$preauth_line"
pass "install script writes the preauth line without silent"

# The migration repairs a root-owned path no unprivileged suite can write, so
# retarget a scratch copy. Fail if the path is not named exactly once, so this
# seam cannot quietly stop standing for the file it copies.
occurrences=$(grep -Fo /etc/pam.d/system-auth "$migration" | wc -l) || occurrences=0
(( occurrences == 1 )) ||
  fail "migration names its authfile exactly once, so the test can retarget a copy" \
    "found $occurrences occurrences"
grep -Fxq 'system_auth="/etc/pam.d/system-auth"' "$migration" ||
  fail "the production path is a fixed literal, not caller-controlled"
sed 's|^system_auth="/etc/pam.d/system-auth"$|system_auth="'"$authfile"'"|' \
  "$migration" >"$migration_copy"
pass "migration names its target once, and the test drives a retargeted copy"

# Stub sudo: apply only the sed it is expected to run, against the retarget.
cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
set -euo pipefail
exec "$@"
SH
chmod +x "$stub_bin/sudo"
run_migration() {
  PATH="$stub_bin:$PATH" bash "$migration_copy"
}

write_fixture() {
  printf '%s\n' "$@" >"$authfile"
}

# Legacy installer output: silent must be stripped, everything else kept.
write_fixture \
  '#%PAM-1.0' \
  'auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120' \
  'auth       [default=die]               pam_faillock.so authfail deny=10 unlock_time=120' \
  'auth       required                    pam_faillock.so authsucc'
run_migration
grep -Eq 'pam_faillock\.so[[:space:]]+preauth[[:space:]]+deny=10[[:space:]]+unlock_time=120$' "$authfile" ||
  fail "migration strips silent from the legacy preauth line"
grep -q 'pam_faillock\.so authfail deny=10 unlock_time=120' "$authfile" ||
  fail "migration leaves the authfail line alone"
pass "migration strips silent from the preauth line, keeps the rest"

# Already-audible line: no-op.
before=$(cat "$authfile")
run_migration
[[ $(cat "$authfile") == "$before" ]] || fail "migration is a no-op on an audible line"
pass "migration is a no-op once silent is gone"

# Idempotency: a second run changes nothing on the legacy fixture either.
write_fixture \
  'auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120'
run_migration
first=$(cat "$authfile")
run_migration
[[ $(cat "$authfile") == "$first" ]] || fail "migration is idempotent on rerun"
pass "migration is idempotent"

# No preauth line at all: untouched.
write_fixture \
  'auth       required                    pam_unix.so try_first_pass nullok'
before=$(cat "$authfile")
run_migration
[[ $(cat "$authfile") == "$before" ]] || fail "migration touches nothing when no preauth line exists"
pass "migration does nothing when there is no preauth line"

# Silent only on the authfail line: not our defect, untouched.
write_fixture \
  'auth       [default=die]               pam_faillock.so authfail silent deny=10 unlock_time=120'
before=$(cat "$authfile")
run_migration
[[ $(cat "$authfile") == "$before" ]] || fail "migration leaves a silent authfail line alone"
pass "migration does not touch a silent authfail line"

# Missing file: the migration no-ops instead of failing the queue.
rm -f "$authfile"
run_migration
pass "migration no-ops when the target file does not exist"
