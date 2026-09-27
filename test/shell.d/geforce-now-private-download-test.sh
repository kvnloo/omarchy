#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The GeForce NOW installer must not download into a fixed name under /tmp:
# curl -O follows symlinks, so a pre-planted /tmp/GeForceNOWSetup.bin symlink
# would redirect the download bytes into an unrelated file.

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME="$T/home" TMPDIR="$T"

# Sanity: the script never touches a fixed /tmp path or relies on cd /tmp.
src="$ROOT/bin/omarchy-install-gaming-geforce-now"

if grep -nE '(^|[[:space:]])cd /tmp([[:space:]]|$)' "$src"; then
  fail "script still cd's into /tmp"
  exit 1
else
  pass "no cd /tmp"
fi

if grep -n 'curl -L.*-o "\$installer"\|-o "\$installer_dir' "$src"; then
  pass "download targets a private path"
else
  fail "download does not target a private path"
  exit 1
fi

if grep -nE 'chmod \+x GeForceNOWSetup\.bin|^\./GeForceNOWSetup\.bin' "$src"; then
  fail "script still operates on the fixed name"
  exit 1
else
  pass "no fixed-name operations"
fi
