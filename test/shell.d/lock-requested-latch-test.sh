#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// When lock() is called and lockRequested is latched but the session is not
// actually locked or secure, clear the latch so the request can retry.
// Fixes #10299: a stalled lock must not prevent later lock attempts.
assert(
  /function lock\(\): string \{[\s\S]*if \(root\.lockRequested && !sessionLock\.locked && !sessionLock\.secure\) \{[\s\S]*root\.lockRequested = false/.test(serviceQml),
  'lock() clears a stalled lockRequested latch before retrying'
)

assert(
  /if \(root\.lockRequested && !sessionLock\.locked && !sessionLock\.secure\) \{[\s\S]*root\.pendingSessionLock = false/.test(serviceQml),
  'lock() clears pendingSessionLock when resetting a stalled request'
)

assert(
  /if \(root\.lockRequested && !sessionLock\.locked && !sessionLock\.secure\) \{[\s\S]*sessionLockStabilizeTimer\.stop\(\)/.test(serviceQml),
  'lock() stops the stabilize timer when resetting a stalled request'
)

assert(
  /if \(root\.lockRequested && !sessionLock\.locked && !sessionLock\.secure\) \{[\s\S]*pendingSessionLockTimer\.stop\(\)/.test(serviceQml),
  'lock() stops the pending timer when resetting a stalled request'
)

// The latch reset must happen before the locked check, so beginLock() gets called.
assert(
  /function lock\(\): string \{[\s\S]*if \(root\.lockRequested && !sessionLock\.locked && !sessionLock\.secure\) \{[\s\S]*\}\s*if \(!root\.locked && !root\.beginLock\(\)\)/.test(serviceQml),
  'lock() resets the latch before checking root.locked'
)
JS
