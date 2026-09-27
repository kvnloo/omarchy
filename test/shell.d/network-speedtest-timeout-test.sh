#!/bin/bash

# Regression tests for the speedtest transfer bounds (fork issue #73):
# every network operation in bin/omarchy-network-speedtest must be bounded so
# a hung endpoint cannot strand the script or its workers.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-network-speedtest"
scratch="$ROOT/../scratch-wave-b-chunk168-speedtest"
rm -rf "$scratch"
mkdir -p "$scratch/stubs"

# --- stub PATH -------------------------------------------------------------
# omarchy-cmd-present: curl is "installed".
cat >"$scratch/stubs/omarchy-cmd-present" <<'EOF'
#!/bin/bash
exit 0
EOF
# ip: pretend the default route leaves via lo (whose sysfs counters are readable).
cat >"$scratch/stubs/ip" <<'EOF'
#!/bin/bash
echo "1.1.1.1 via 192.168.1.1 dev lo src 192.168.1.2 uid 0"
EOF
# curl: API fetch returns 3 fake OCA urls (or hangs when API_MODE=hang);
# transfers hang (CURL_MODE=hang), fail fast logging the url (CURL_MODE=fail),
# or succeed instantly (default).
cat >"$scratch/stubs/curl" <<'EOF'
#!/bin/bash
for a in "$@"; do
  case "$a" in
  *api.fast.com*)
    if [[ ${API_MODE:-} == hang ]]; then
      sleep 600
    fi
    printf '{"targets":[{"url":"http://127.0.0.1/t1"},{"url":"http://127.0.0.1/t2"},{"url":"http://127.0.0.1/t3"}]}\n'
    exit 0
    ;;
  esac
done
case "${CURL_MODE:-}" in
hang) sleep 600 ;;
fail)
  url="${@: -1}"
  printf '%s\n' "$url" >>"${CURL_LOG:?}"
  exit 7
  ;;
*) exit 0 ;;
esac
EOF
chmod +x "$scratch/stubs/"*

# Script under test: real file with the 8s bound shortened to 2s so the
# behavioral cases stay fast. The sed only touches the max_seconds constant.
sut="$scratch/speedtest-under-test"
sed 's/^max_seconds=8$/max_seconds=2/' "$script" >"$sut"
chmod +x "$sut"
grep -q '^max_seconds=2$' "$sut" || fail "test setup did not shorten max_seconds"

run_sut() {
  PATH="$scratch/stubs:$PATH" "$@"
}

# --- production invariants (static, on the real file) -----------------------
[[ $(grep -F 'timeout -k 1 "$max_seconds" curl' "$script" | grep -cvF 'fast_api_url') == 2 ]] ||
  fail "both transfer directions wrap curl in timeout -k 1"
pass "both transfer directions wrap curl in timeout -k 1"

grep -F -- '--connect-timeout "$connect_timeout"' "$script" >/dev/null &&
  grep -F -- '--max-time "$max_time"' "$script" >/dev/null ||
  fail "transfers carry --connect-timeout/--max-time backstops"
pass "transfers carry --connect-timeout/--max-time backstops"

[[ $(grep -cF 'if (( now - start >= max_seconds )); then' "$script") == 2 ]] ||
  fail "both worker loops stop at the max_seconds deadline"
pass "both worker loops stop at the max_seconds deadline"

grep -F 'if (( $(date +%s) - run_start >= max_seconds )); then' "$script" >/dev/null ||
  fail "main loop stops at the max_seconds deadline even without SIGTERM"
pass "main loop stops at the max_seconds deadline even without SIGTERM"

grep -F 'fast_urls=$(timeout' "$script" >/dev/null ||
  fail "the initial endpoint fetch is bounded too"
pass "the initial endpoint fetch is bounded too"

# Round-robin advance: each transfer attempt must be preceded by the index
# increment, so a failed attempt moves to the next URL instead of retrying.
[[ $(awk '/timeout -k 1 "\$max_seconds" curl.*\|\| continue/ { if (prev != "      idx=$((idx + 1))") bad++ } { if ($0 != "") prev=$0 } END { print bad+0 }' "$script") == 0 ]] ||
  fail "failed attempts advance the round-robin index"
pass "failed attempts advance the round-robin index"

# Stragglers are stopped before the final wait.
cleanup_line=$(grep -n '^cleanup$' "$script" | cut -d: -f1)
wait_line=$(grep -n '^wait ' "$script" | cut -d: -f1)
[[ -n $cleanup_line && -n $wait_line && $cleanup_line -lt $wait_line ]] ||
  fail "cleanup runs before the final wait"
pass "cleanup runs before the final wait"

# --- behavioral: hung transfers exit under the bound ------------------------
start=$SECONDS
rc=0
out=$(run_sut env CURL_MODE=hang timeout -k 5 30 "$sut" down 2>"$scratch/stderr.txt") || rc=$?
elapsed=$((SECONDS - start))
[[ $rc == 0 ]] || fail "hung transfers: script exited $rc instead of 0" "$(cat "$scratch/stderr.txt")"
[[ $elapsed -lt 12 ]] || fail "hung transfers: took ${elapsed}s, bound is ~2s"
[[ -n $out ]] || fail "hung transfers: no rate output printed"
pass "hung transfers exit under the bound (rc=0, ${elapsed}s, rates printed)"

# --- behavioral: hung endpoint fetch fails closed ----------------------------
start=$SECONDS
rc=0
run_sut env API_MODE=hang timeout -k 5 30 "$sut" down >"$scratch/out.txt" 2>"$scratch/stderr.txt" || rc=$?
elapsed=$((SECONDS - start))
[[ $rc == 1 ]] || fail "hung endpoint fetch: exited $rc instead of 1" "$(cat "$scratch/stderr.txt")"
[[ $elapsed -lt 8 ]] || fail "hung endpoint fetch: took ${elapsed}s, bound is ~2s"
grep -q "Failed to fetch speed test endpoints" "$scratch/stderr.txt" ||
  fail "hung endpoint fetch: missing failure message"
pass "hung endpoint fetch fails closed (rc=1, ${elapsed}s)"

# --- behavioral: failed transfers keep the round-robin moving ----------------
export CURL_LOG="$scratch/attempted-urls.txt"
: >"$CURL_LOG"
rc=0
run_sut env CURL_MODE=fail timeout -k 5 30 "$sut" down >"$scratch/out.txt" 2>/dev/null || rc=$?
[[ $rc == 0 ]] || fail "failing transfers: script exited $rc instead of 0"
[[ $(sort -u "$CURL_LOG" | wc -l) == 3 ]] ||
  fail "failing transfers: not all 3 urls were attempted" "$(sort -u "$CURL_LOG" | tr '\n' ' ')"
[[ $(wc -l <"$CURL_LOG") -gt 30 ]] ||
  fail "failing transfers: workers did not keep attempting ($(wc -l <"$CURL_LOG") attempts)"
pass "failing transfers advance the round-robin ($(wc -l <"$CURL_LOG") attempts across 3 urls)"

rm -rf "$scratch"
