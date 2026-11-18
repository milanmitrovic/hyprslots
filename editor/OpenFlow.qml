import QtQuick
import "Guide.js" as Guide

// What the panel still owes once it is open (Panel.qml): the opening tab,
// chosen again on the first state read, and a Record or Capture asked for
// in the open payload, started once there is a state to start it on. Kept
// out of Panel.qml so it runs without the panel's window and views
// (editor/tests/qml/tst_openflow.qml).
//
// `{"record": true}` (the bar widget's Record) starts the Layout tab's
// record flow (R) once the state is read; `{"capture": true}` (the bar's
// Capture, the Omarchy menu's and the keybind's) its capture flow (c) on
// the focused workspace. The tab it opens on is Guide.openingTab's: the
// Layout tab while there are no slots, else Assignment; one the payload asks
// for wins. Chosen again on the first state read after opening (the state
// it had may be older), unless a tab was picked meanwhile.
QtObject {
  id: flow

  // The engine whose `state` it waits for (null: none yet), and whether the
  // panel is open: nothing is started while it is closed.
  property var engine: null
  property bool opened: false

  property bool pendingRecord: false
  property bool pendingCapture: false
  property bool pendingTab: false

  // The opening tab, settled on a state read.
  signal tabSettled(int index)
  // A pending Record or Capture is due: there is a state to start it on.
  signal recordDue()
  signal captureDue()

  readonly property bool ready: flow.opened && !!flow.engine && flow.engine.state !== null

  // The panel opens with this payload (an object): the tab to show now, and
  // what is left pending. A Record or Capture is tried again once the event
  // loop turns, so a state already there starts it straight away.
  function begin(payload) {
    var p = payload || {}
    var opening = Guide.openingTab(flow.engine ? flow.engine.state : null, p)
    flow.pendingTab = !Guide.asksForTab(p)
    if (p.record === true) {
      flow.pendingRecord = true
      Qt.callLater(flow.startRecord)
    }
    if (p.capture === true) {
      flow.pendingCapture = true
      Qt.callLater(flow.startCapture)
    }
    return opening !== null ? opening : 0 // nothing read yet: Assignment, which says why
  }

  function startRecord() {
    if (!flow.pendingRecord || !flow.ready) return
    flow.pendingRecord = false
    flow.recordDue()
  }

  function startCapture() {
    if (!flow.pendingCapture || !flow.ready) return
    flow.pendingCapture = false
    flow.captureDue()
  }

  // The first state read after opening settles the opening tab.
  function settleTab() {
    if (!flow.pendingTab || !flow.ready) return
    flow.pendingTab = false
    var opening = Guide.openingTab(flow.engine.state, {})
    if (opening !== null) flow.tabSettled(opening)
  }

  // A tab picked by key or click: the opening tab is settled.
  function tabPicked() {
    flow.pendingTab = false
  }

  // The panel closed: nothing is owed any more.
  function end() {
    flow.pendingRecord = false
    flow.pendingCapture = false
    flow.pendingTab = false
  }
}
