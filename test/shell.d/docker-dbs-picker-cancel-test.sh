#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Cancelling the database picker must not call an undefined function.

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TMPDIR="$T"

# Stub gum so the picker exits 1 (Esc).
mkdir -p "$T/stubs"
printf '#!/bin/bash\nexit 1\n' >"$T/stubs/gum"
chmod +x "$T/stubs/gum"
export PATH="$T/stubs:$ROOT/bin:$PATH"

out=$("$ROOT/bin/omarchy-install-docker-dbs" 2>&1) || true

if printf '%s' "$out" | grep -q 'command not found'; then
  fail "picker cancel calls an undefined function" "$out"
  exit 1
else
  pass "picker cancel degrades cleanly"
fi
