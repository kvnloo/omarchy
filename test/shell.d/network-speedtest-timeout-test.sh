#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-network-speedtest"

# Production invariants from tip #13239: each transfer is individually bounded,
# workers self-stop, the main loop has a hard cap, and cleanup runs before wait.
grep -Fq 'max_seconds=8' "$script" || fail "max_seconds=8 is set"
grep -Fq 'connect_timeout=5' "$script" || fail "connect_timeout=5 is set"
grep -Fq 'max_time=15' "$script" || fail "max_time=15 is set"
grep -Fq 'timeout -k 1 "$max_seconds" curl' "$script" || fail "curl is wrapped in timeout -k"
grep -Fq -- '--connect-timeout "$connect_timeout"' "$script" || fail "curl carries --connect-timeout"
grep -Fq -- '--max-time "$max_time"' "$script" || fail "curl carries --max-time"
grep -Fq '|| continue' "$script" || fail "failed attempts continue the round-robin"
if grep -E 'curl .* \|\| return$' "$script" >/dev/null; then
  fail "unbounded curl || return paths must be gone"
fi
pass "production script carries transfer-bound invariants"

# Pre-cleanup before final wait (not only the EXIT trap).
python3 - "$script" <<'PY' || fail "cleanup is invoked before final wait"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text().splitlines()
# Find the trailing cleanup + wait pair near EOF.
joined = "\n".join(text[-12:])
assert "cleanup\nwait 2>/dev/null || true" in joined, joined
pass
PY
pass "cleanup runs before final wait"

# Runtime: hung curl stub must not strand the worker past max_seconds.
# Extract traffic_worker into a harness with max_seconds=2 and a sleeping curl.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mock_bin="$test_tmp/bin"
mkdir -p "$mock_bin"

cat >"$mock_bin/curl" <<'SH'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$TEST_TMP/curl.log"
# Hang until the outer timeout kills us.
sleep 120
exit 0
SH
chmod +x "$mock_bin/curl"

cat >"$test_tmp/harness.sh" <<'SH'
#!/bin/bash
set -e
direction=down
max_seconds=2
connect_timeout=5
max_time=15
traffic_worker() {
  local urls=("$@")
  local url_count=${#urls[@]}
  local idx=$RANDOM
  local start now url
  start=$(date +%s)
  while true; do
    now=$(date +%s)
    if (( now - start >= max_seconds )); then
      break
    fi
    url=${urls[$((idx % url_count))]}
    timeout -k 1 "$max_seconds" curl -fsS --connect-timeout "$connect_timeout" --max-time "$max_time" -o /dev/null "$url" 2>/dev/null || continue
    idx=$((idx + 1))
  done
}
traffic_worker "http://hung.invalid/chunk"
SH

command -v timeout >/dev/null || fail "timeout(1) is required"

start=$(date +%s)
TEST_TMP="$test_tmp" PATH="$mock_bin:$PATH" bash "$test_tmp/harness.sh"
elapsed=$(( $(date +%s) - start ))
(( elapsed < 8 )) || fail "worker exits under max_seconds bound" "elapsed=${elapsed}s"
pass "hung transfer worker exits under bound (${elapsed}s)"

grep -E -- '--connect-timeout|--max-time' "$test_tmp/curl.log" >/dev/null || \
  fail "stub curl saw connect/max-time flags" "$(cat "$test_tmp/curl.log")"
pass "stub curl received connect/max-time flags"
