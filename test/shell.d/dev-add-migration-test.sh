#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command git

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

git -C "$test_tmp" init -q
git -C "$test_tmp" config user.email test@example.com
git -C "$test_tmp" config user.name test
touch "$test_tmp/stub"
git -C "$test_tmp" add stub
git -C "$test_tmp" commit -qm stub

first=$(OMARCHY_PATH="$test_tmp" "$ROOT/bin/omarchy-dev-add-migration" --no-edit)
second=$(OMARCHY_PATH="$test_tmp" "$ROOT/bin/omarchy-dev-add-migration" --no-edit)

[[ -f $first ]] || fail "first migration file was created" "$first"
[[ -f $second ]] || fail "second migration file was created" "$second"
[[ $first != "$second" ]] || fail "a second migration before the next commit gets its own file" "both returned $first"

pass "a second migration before the next commit gets its own file"
