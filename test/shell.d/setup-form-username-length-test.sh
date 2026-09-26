#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmp_dir=$(mktemp -d)
trap 'rm -r "$tmp_dir"' EXIT

# gum reads its scripted answers from GUM_SCRIPT, one "status:output" line per
# invocation, mirroring the harness in setup-form-test.sh.
cat >"$tmp_dir/gum" <<'EOF'
#!/bin/bash
count=$(($(cat "$GUM_COUNT") + 1))
printf '%s' "$count" >"$GUM_COUNT"

line=$(sed -n "${count}p" "$GUM_SCRIPT")
printf '%s\n' "${line#*:}"
exit "${line%%:*}"
EOF

cat >"$tmp_dir/driver" <<'EOF'
#!/bin/bash

set -euo pipefail

source "$ROOT/install/provisioning/setup-form.sh"

notice() { printf '%s\n' "$1" >>"$NOTICES"; }

omarchy_username_taken() { return 1; }

"$PROMPT_FN"

printf 'username=%s\n' "${username:-}"
EOF

chmod +x "$tmp_dir/gum" "$tmp_dir/driver"
export PATH="$tmp_dir:$PATH"
export GUM_SCRIPT="$tmp_dir/script" GUM_COUNT="$tmp_dir/count" NOTICES="$tmp_dir/notices"
export PROMPT_FN=omarchy_prompt_username

status=0

run_prompt() {
  printf '%s\n' "$@" >"$GUM_SCRIPT"
  printf '0' >"$GUM_COUNT"
  : >"$NOTICES"
  "$tmp_dir/driver" >"$tmp_dir/out" 2>"$tmp_dir/err" && status=0 || status=$?
}

field() { sed -n "s/^$1=//p" "$tmp_dir/out"; }

assert_notices() {
  local description=$1 expected=$2
  local actual
  actual=$(<"$NOTICES")
  [[ $actual == "$expected" ]] || fail "$description" "expected notices: $expected
actual notices:   $actual"
}

long33=$(printf 'u%.0s' {1..33})
long32=$(printf 'u%.0s' {1..32})

# useradd rejects names longer than 32 characters, and first-boot setup pins
# the username before useradd runs — a too-long name must never leave the form.
run_prompt "0:$long33" "0:david"
((status == 0)) || fail "username prompt returns after a rejected long name" "status: $status"
[[ $(field username) == "david" ]] || fail "username prompt re-asks after a too-long name"
assert_notices "username prompt explains the length rejection" "Username must be 32 characters or fewer"
pass "usernames longer than 32 characters are rejected with a length notice"

run_prompt "0:$long32"
((status == 0)) || fail "username prompt returns for a 32-character name" "status: $status"
[[ $(field username) == "$long32" ]] || fail "username prompt keeps a 32-character name"
assert_notices "no notice for a 32-character name" ""
pass "a 32-character username is accepted at the useradd boundary"

# The length gate runs before the character check, so a long name with bad
# characters still gets the length notice rather than the character one.
run_prompt "0:$(printf 'U%.0s' {1..40})" "0:david"
[[ $(field username) == "david" ]] || fail "username prompt re-asks after a long invalid name"
assert_notices "length is checked before the character pattern" "Username must be 32 characters or fewer"
pass "the length check runs ahead of the character-pattern check"
