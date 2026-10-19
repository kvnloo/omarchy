#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const appSource = fs.readFileSync(root + '/shell/services/AppLibrary.qml', 'utf8')
const search = requireFromRoot('shell/services/AppSearch.js')
const match = appSource.match(/^  function appsSignature\(\) \{[\s\S]*?^  \}/m)
assert(match, 'the AppLibrary signature function exists in production source')

const DesktopEntries = { applications: { values: [] } }
const AppSearch = {
  keywordText: function(entry) {
    return entry && Array.isArray(entry.keywords) ? entry.keywords.join(' ') : ''
  }
}
const signature = vm.runInNewContext('(' + match[0] + ')', { DesktopEntries, AppSearch })
function getSignature(entries) {
  DesktopEntries.applications.values = entries
  return signature()
}

const editor = {
  id: 'editor.desktop',
  name: 'Editor',
  genericName: 'Text editor',
  comment: 'Edit text',
  icon: 'editor',
  keywords: ['editor']
}
const changedComment = { ...editor, comment: 'Edit diagrams' }
const browser = {
  id: 'browser.desktop',
  name: 'Browser',
  genericName: 'Web browser',
  comment: 'Browse the internet',
  icon: 'browser',
  keywords: ['browser']
}

assert(getSignature([editor]) !== getSignature([changedComment]),
  'changing only Comment refreshes app-list consumers')
assertEqual(search.sortedEntries([editor], 'diagrams').length, 0,
  'old description has no new search hit')
assertEqual(search.sortedEntries([changedComment], 'diagrams').length, 1,
  'new description changes real AppSearch results')
assertEqual(getSignature([editor, browser]), getSignature([browser, editor]),
  'reordering the unchanged app set causes no refresh')
assertEqual(getSignature([editor]), getSignature([{ ...editor }]),
  'a new object with unchanged data causes no refresh')
assert(getSignature([editor]) !== getSignature([{ ...editor, name: 'New Editor' }]),
  'renaming an app refreshes the label')
assert(getSignature([editor]) !== getSignature([{ ...editor, icon: 'new-icon' }]),
  'changing an icon refreshes app rows')
assert(getSignature([editor]) !== getSignature([{ ...editor, keywords: ['ide'] }]),
  'changing keywords refreshes search')
JS
