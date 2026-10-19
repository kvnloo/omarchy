#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

run_node_test "bar underline geometry follows exact widget and tray icon centers" <<'JS'
const fs = require('fs')
const source = fs.readFileSync(root + '/shell/plugins/bar/Bar.qml', 'utf8')
const start = source.indexOf('id: openPanelIndicator')
const end = source.indexOf('Behavior on opacity', start)
assert(start !== -1 && end > start, 'open-panel marker exists')
const marker = source.slice(start, end)

// The QML position binding is pure JavaScript; evaluate the production
// expressions rather than duplicating the arithmetic in the test.
function binding(axis, nextAxis) {
  const matcher = new RegExp('(?:^|\\n)\\s*' + axis + ':\\s*([\\s\\S]*?)\\n\\s*' + nextAxis + ':')
  const match = marker.match(matcher)
  assert(match, 'open-panel marker has a ' + axis + ' binding')
  return new Function('root', 'slot', 'parent', 'width', 'height', 'inset', 'return (' + match[1].trim() + ')')
}
const x = binding('x', 'y')
const y = binding('y', 'z')
const cases = [
  [10.5, 12, 21, 1],
  [13.5, 15, 27, 1.25],
  [15.5, 12, 31, 2],
  [17.5, 20, 35, 1.5],
  [12.75, 10, 52, 1.25],
]
for (const [center, along, size, dpr] of cases) {
  const slot = { panelIndicatorCenter: center }
  const parent = { width: size, height: size }
  for (const position of ['top', 'bottom']) {
    const left = x({ vertical: false, position }, slot, parent, along, 2, 2)
    assert(Math.abs((left + along / 2 - center) * dpr) < 1e-8,
      'horizontal ' + position + ' underline centered for size ' + size + ' at scale ' + dpr)
  }
  for (const position of ['left', 'right']) {
    const top = y({ vertical: true, position }, slot, parent, 2, along, 2)
    assert(Math.abs((top + along / 2 - center) * dpr) < 1e-8,
      'vertical ' + position + ' underline centered for size ' + size + ' at scale ' + dpr)
  }
}
// Keep the across-bar inset unchanged on every side.
assert(x({ vertical: true, position: 'left' }, {}, { width: 30, height: 30 }, 2, 12, 2) === 26, 'left bar inset')
assert(x({ vertical: true, position: 'right' }, {}, { width: 30, height: 30 }, 2, 12, 2) === 2, 'right bar inset')
assert(y({ vertical: false, position: 'top' }, {}, { width: 30, height: 30 }, 12, 2, 2) === 26, 'top bar inset')
assert(y({ vertical: false, position: 'bottom' }, {}, { width: 30, height: 30 }, 12, 2, 2) === 2, 'bottom bar inset')
JS
