#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')

const barSource = fs.readFileSync(path.join(root, 'shell/plugins/bar/Bar.qml'), 'utf8')

const tooltipBlock = barSource.slice(
  barSource.indexOf('id: tooltipBubble'),
  barSource.indexOf('id: tooltipLabel')
)

assert(
  /width:\s*tooltipWindow\.width/.test(tooltipBlock)
    && /height:\s*tooltipWindow\.height/.test(tooltipBlock),
  'bar tooltip bubble fills its rounded-up window'
)

JS
