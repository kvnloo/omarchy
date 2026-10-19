#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "$0")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const source = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const utilSource = fs.readFileSync(path.join(root, 'shell/Commons/Util.qml'), 'utf8')
const readingKeyMatch = utilSource.match(/function readingKey\(event, vim\) \{([\s\S]*?)\n  \}/)
assert(!!readingKeyMatch, 'menu navigation uses the real reading-direction helper')
const catcher = source.slice(source.indexOf('id: keyCatcher'))
const handlerSource = catcher.match(/Keys\.onPressed: (function\(event\) \{[\s\S]*?\n        \})/)
assert(!!handlerSource, 'menu key handler is testable from production QML')

const Qt = {
  Key_Delete: 1, Key_Escape: 2, Key_Backspace: 3, Key_Left: 4,
  Key_Up: 5, Key_Down: 6, Key_PageUp: 7, Key_PageDown: 8,
  Key_Right: 9, Key_Return: 10, Key_Enter: 11
}

function press(key, kind, opts = {}) {
  const calls = []
  const mode = opts.mode || 'menu'
  const active = opts.cursorActive !== false
  const root = {
    deleteConfirmOpen: false, filterText: opts.filterText === undefined ? 'partial' : opts.filterText, dmenuActive: mode !== 'menu',
    mode, cursorActive: active, selectedIndex: 0,
    rowSelectable: index => index === 0 && !opts.disabled,
    activateIndex: index => calls.push('activate:' + index),
    applyDmenuSelection: value => calls.push('submit:' + value),
    settleCursor: () => calls.push('settle'),
    goBack: () => calls.push('back')
  }
  const displayModel = { count: 1, get: () => ({ kind, disabled: !!opts.disabled }) }
  const Util = {
    editsFilter: () => false,
    readingKey: vm.runInNewContext('(function readingKey(event, vim) {' + readingKeyMatch[1] + '\n})', {
      Qt, I18n: { rightToLeft: !!opts.rtl }
    })
  }
  const onKey = vm.runInNewContext('(' + handlerSource[1] + ')', { Qt, Util, root, displayModel })
  const event = { key, accepted: false }
  onKey(event)
  return { calls, accepted: event.accepted }
}

assertDeepEqual(press(Qt.Key_Right, 'action'), { calls: [], accepted: true }, 'Right never executes a menu action, including Shutdown')
assertDeepEqual(press(Qt.Key_Right, 'app'), { calls: [], accepted: true }, 'Right never launches an app')
assertDeepEqual(press(Qt.Key_Right, 'dmenu', { mode: 'input' }), { calls: [], accepted: true }, 'Right never submits a partial input')
assertDeepEqual(press(Qt.Key_Right, 'dmenu', { mode: 'select' }), { calls: [], accepted: true }, 'Right never chooses a select-menu option')
assertDeepEqual(press(Qt.Key_Right, 'menu'), { calls: ['activate:0'], accepted: true }, 'Right opens the highlighted submenu')
assertDeepEqual(press(Qt.Key_Right, 'link'), { calls: ['activate:0'], accepted: true }, 'Right follows a menu link')
assertDeepEqual(press(Qt.Key_Right, 'menu', { disabled: true }), { calls: [], accepted: true }, 'Right cannot enter a disabled submenu')
assertDeepEqual(press(Qt.Key_Right, 'menu', { cursorActive: false }), { calls: ['settle'], accepted: true }, 'Right only settles an inactive cursor')
assertDeepEqual(press(Qt.Key_Right, 'action', { filterText: '' }), { calls: [], accepted: true }, 'Right does not execute Shutdown on an empty search')
assertDeepEqual(press(Qt.Key_Left, 'menu', { filterText: '' }), { calls: ['back'], accepted: true }, 'LTR Left still navigates back')
assertDeepEqual(press(Qt.Key_Left, 'menu', { rtl: true }), { calls: ['activate:0'], accepted: true }, 'RTL physical Left opens the submenu as logical Right')
assertDeepEqual(press(Qt.Key_Left, 'action', { rtl: true }), { calls: [], accepted: true }, 'RTL physical Left cannot execute Shutdown')
assertDeepEqual(press(Qt.Key_Right, 'action', { rtl: true, filterText: '' }), { calls: ['back'], accepted: true }, 'RTL physical Right navigates back rather than executing an action')
assertDeepEqual(press(Qt.Key_Left, 'dmenu', { rtl: true, mode: 'input' }), { calls: [], accepted: true }, 'RTL input forward arrow never submits a partial value')
assertDeepEqual(press(Qt.Key_Return, 'action'), { calls: ['activate:0'], accepted: true }, 'Enter still activates actions')
assertDeepEqual(press(Qt.Key_Enter, 'app'), { calls: ['activate:0'], accepted: true }, 'Numpad Enter still launches apps')
assertDeepEqual(press(Qt.Key_Return, 'dmenu', { mode: 'input' }), { calls: ['submit:partial'], accepted: true }, 'Enter still submits text input')
assertDeepEqual(press(Qt.Key_Return, 'dmenu', { mode: 'select' }), { calls: ['activate:0'], accepted: true }, 'Enter still selects a menu option')
JS
