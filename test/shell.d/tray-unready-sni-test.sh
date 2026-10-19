#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test "tray menu ObjectModel readiness" <<'JS'
const fs = require('fs')
const tray = requireFromRoot('shell/plugins/bar/widgets/TrayModel.js')
const source = fs.readFileSync(root + '/shell/plugins/bar/widgets/Tray.qml', 'utf8')

assert(
  !tray.menuModelHasChildren({ values: [] }),
  'empty QsMenuOpener ObjectModel is not ready'
)
assert(
  tray.menuModelHasChildren({ values: [{ text: 'Open' }] }),
  'non-empty QsMenuOpener ObjectModel is ready'
)
assert(
  !tray.menuModelHasChildren({ length: 1 }),
  'array-style length on the ObjectModel itself is not treated as readiness'
)

const openTray = source.slice(
  source.indexOf('function openTrayMenu('),
  source.indexOf('function trayIconSource(')
)
assert(!/item\.display\(/.test(openTray), 'unready SNI path does not take a platform popup grab')
assert(
  /if \(!item \|\| !item\.menu\) return/.test(openTray),
  'SNI without a menu is a no-op'
)
assert(/^\s*trayMenuPending = false\n\s*if \(!item \|\| !item\.menu\) return/m.test(openTray), 'any new click, even on an item without a menu, cancels the previous pending one')
assert(/trayMenuPending = true\n\s*trayMenuPendingTimer\.restart\(\)\n\s*syncTrayMenuOpen\(\)/.test(openTray), 'a click marks the menu pending for a bounded time, then opens it if rows are already there')

const sync = source.slice(
  source.indexOf('function syncTrayMenuOpen()'),
  source.indexOf('function openTrayMenu(')
)
assert(
  /var hasChildren = TrayModel\.menuModelHasChildren\(trayMenuOpener\.children\)/.test(sync),
  'readiness uses ObjectModel values through the production helper'
)
assert(
  /if \(hasChildren && trayMenuPending\) \{\s*trayMenuPending = false\s*trayMenuOpen = true/.test(sync),
  'rows open the popup only for a pending click, once'
)
assert(
  /else if \(!hasChildren && trayMenuOpen\) \{(\s*\/\/.*)*\s*trayMenuOpen = false\s*\}/.test(sync),
  'dropping back to zero rows releases the popup without cancelling a click on another item'
)

const opener = source.slice(
  source.indexOf('QsMenuOpener {\n    id: trayMenuOpener'),
  source.indexOf('PopupCard {\n    id: trayMenuPopup')
)
assert(/onChildrenChanged: Qt\.callLater\(root\.syncTrayMenuOpen\)/.test(opener), 'a menu handle that loads late is observed')
assert(
  /target: trayMenuOpener\.children\s*function onValuesChanged\(\) \{ Qt\.callLater\(root\.syncTrayMenuOpen\) \}/.test(opener),
  'rows added to or removed from a loaded menu are observed once the update settles, so replacing every row does not close the menu'
)
assert(
  /id: trayMenuPendingTimer\s*interval: \d+\s*onTriggered: root\.trayMenuPending = false/.test(opener),
  'a pending click expires'
)

// Exercise production QML JavaScript state transitions without pinning a
// UX-tunable timeout. This does not simulate an outside desktop click.
const vm = require('vm')
function syncMenuWithState(rows, pending, open) {
  const state = {
    TrayModel: tray,
    trayMenuOpener: { children: { values: rows } },
    trayMenuPending: pending,
    trayMenuOpen: open
  }
  vm.runInNewContext(sync + '\n' + 'syncTrayMenuOpen()', state)
  return { pending: state.trayMenuPending, open: state.trayMenuOpen }
}
assertDeepEqual(
  syncMenuWithState([], true, false),
  { pending: true, open: false },
  'pending click with no rows never grabs focus'
)
assertDeepEqual(
  syncMenuWithState([{ text: 'Open' }], true, false),
  { pending: false, open: true },
  'ready rows consume the click and open once'
)
assertDeepEqual(
  syncMenuWithState([{ text: 'Open' }], false, false),
  { pending: false, open: false },
  'rows arriving after cancellation or timeout cannot reopen the menu'
)
assertDeepEqual(
  syncMenuWithState([], false, true),
  { pending: false, open: false },
  'losing all rows releases an open menu grab'
)
assertDeepEqual(
  syncMenuWithState([{ text: 'Open' }], false, true),
  { pending: false, open: true },
  'already open populated menu stays open'
)
assert(
  /function onActivePopoutChanged\(\) \{\s*if \(root\.bar\.activePopout\) root\.trayMenuPending = false/.test(opener),
  'another bar popup cancels a pending tray click'
)
assert(
  /target: SystemTray\.items\s*function onValuesChanged\(\) \{\s*if \(SystemTray\.items\.values\.indexOf\(root\.activeTrayItem\) !== -1\) return\s*if \(root\.trayMenuOpen\) root\.close\(\)\s*else root\.trayMenuPending = false/.test(opener),
  'an item leaving the whole tray closes its open menu, or cancels its pending click'
)

const closeFn = source.slice(
  source.indexOf('function close()'),
  source.indexOf('function syncTrayMenuOpen()')
)
assert(/trayMenuPending = false/.test(closeFn), 'close() cancels a pending open so a dismissed menu cannot reopen itself')
assert(!/activeTrayItem = null/.test(closeFn), 'close() keeps the active item so the menu fades out with its rows')
// Exercise the production root method AND the actual MouseArea exit handler,
// not a duplicate implementation or a timeout constant. No QML/compositor
// events are synthesized by Node: those still need a live shell regression.
const cancelSource = source.slice(
  source.indexOf('function cancelPendingTrayMenuFor(anchorItem) {'),
  source.indexOf('function syncTrayMenuOpen()')
)
assert(cancelSource.startsWith('function cancelPendingTrayMenuFor('),
  'tray has a specific cancellation method for its originating icon')
const trayItemSource = source.slice(source.indexOf('component TrayItem: Item {'))
const exitedHandler = /onExited:\s*\{([\s\S]*?)\n\s*\}\n\s*onPressed:/.exec(trayItemSource)
assert(!!exitedHandler, 'tray mouse exit delegates pending cancellation')

function exitIcon(clickedIcon, exitedIcon, pending, hasBar) {
  const state = {
    root: {
      trayMenuPending: pending,
      trayMenuOpen: !pending,
      activeTrayAnchor: clickedIcon,
      bar: hasBar ? { hideTooltip: function() {} } : null
    },
    trayItemRoot: exitedIcon
  }
  vm.runInNewContext(cancelSource +
    '\nroot.cancelPendingTrayMenuFor = cancelPendingTrayMenuFor\n' +
    exitedHandler[1], state)
  return state.root
}
const ownerIcon = {}, otherIcon = {}
assert(!exitIcon(ownerIcon, ownerIcon, true, true).trayMenuPending,
  'leaving the clicked icon cancels the pending menu before delayed rows arrive')
assert(exitIcon(ownerIcon, otherIcon, true, true).trayMenuPending,
  'another tray icon cannot cancel a newer click on the original icon')
const visibleMenu = exitIcon(ownerIcon, ownerIcon, false, true)
assert(visibleMenu.trayMenuOpen && !visibleMenu.trayMenuPending,
  'leaving after the menu opened does not dismiss it')
assert(!exitIcon(ownerIcon, ownerIcon, true, false).trayMenuPending,
  'abandonment cancels even when the tooltip/bar host has gone away')

JS
