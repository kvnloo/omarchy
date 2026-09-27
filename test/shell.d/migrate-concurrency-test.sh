#!/bin/bash

# Two concurrent omarchy-migrate runners must not execute the same migration
# twice. The login notifier's toast launches omarchy-migrate in a terminal with
# no coordination against omarchy update's own migration phase, and the command
# is documented as safe to run by hand at any time.

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

mkdir -p "$test_dir/bin" "$test_dir/omarchy/migrations"

# Dispatcher under test, plus a stub for the notification dismissal it ends with.
cp "$ROOT/bin/omarchy-migrate" "$test_dir/bin/omarchy-migrate"
cat >"$test_dir/bin/omarchy-notification-dismiss" <<'STUB'
#!/bin/bash
exit 0
STUB
chmod +x "$test_dir/bin/"*

# One slow migration, so two runners started together are guaranteed to overlap.
cat >"$test_dir/omarchy/migrations/1790000000.sh" <<'MIGRATION'
echo "Running slow migration"
sleep 2
echo ran >>"$MIGRATION_RUNS"
MIGRATION
chmod 644 "$test_dir/omarchy/migrations/1790000000.sh"

export MIGRATION_RUNS="$test_dir/runs.log"

run_migrator() {
  HOME="$test_dir/home" \
    OMARCHY_PATH="$test_dir/omarchy" \
    OMARCHY_MIGRATION_STATE="$test_dir/state" \
    PATH="$test_dir/bin:/usr/bin:/bin" \
    bash "$test_dir/bin/omarchy-migrate" >/dev/null 2>&1
}

run_migrator &
pid_a=$!
run_migrator &
pid_b=$!
wait "$pid_a"
wait "$pid_b"

[[ -f $MIGRATION_RUNS ]] ||
  fail "concurrent runners execute each migration exactly once" "migration never ran"
runs=$(wc -l <"$MIGRATION_RUNS")
(( runs == 1 )) ||
  fail "concurrent runners execute each migration exactly once" "migration ran $runs times"
[[ -f $test_dir/state/1790000000.sh ]] ||
  fail "concurrent runners leave the completion marker" "marker missing"
pass "concurrent runners execute each migration exactly once"
