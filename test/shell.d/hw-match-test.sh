#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# A missing pattern used to make the greps match every readable DMI file,
# turning a forgotten argument into a hardware "yes" for any caller.
if "$ROOT/bin/omarchy-hw-match" 2>/dev/null; then
  fail "hw-match refuses a missing pattern"
fi
pass "hw-match refuses a missing pattern"

# The error should say what was missing.
usage=$("$ROOT/bin/omarchy-hw-match" 2>&1 >/dev/null || true)
[[ $usage == *"Usage: omarchy-hw-match <pattern>"* ]] ||
  fail "hw-match usage names the missing pattern" "actual: $usage"
pass "hw-match usage names the missing pattern"
