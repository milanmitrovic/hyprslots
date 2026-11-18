import QtQuick
import QtTest
import "../.."

// OpenFlow.qml (what Panel.qml owes once open): the opening tab, settled on
// the first state read unless a tab was picked; a payload's Record or
// Capture, started once there is a state and the panel is open, and only
// once. The engine is a stand-in holding `state`.
TestCase {
  id: testCase
  name: "OpenFlow"

  QtObject {
    id: fakeEngine
    property var state: null
  }

  Component {
    id: flowComponent
    OpenFlow {}
  }

  SignalSpy {
    id: tabSpy
    signalName: "tabSettled"
  }

  SignalSpy {
    id: recordSpy
    signalName: "recordDue"
  }

  SignalSpy {
    id: captureSpy
    signalName: "captureDue"
  }

  readonly property int assignment: 0
  readonly property int layout: 1
  readonly property int desk: 2

  // An engine state with `slots` slots, running and editable.
  function stateWith(slots) {
    var list = []
    for (var i = 0; i < slots; i++) list.push({ name: "s" + i })
    return { ok: true, slots: list, config: { editable: true } }
  }

  function makeFlow(props) {
    fakeEngine.state = null
    var p = { engine: fakeEngine, opened: true }
    for (var k in props || {}) p[k] = props[k]
    var flow = createTemporaryObject(flowComponent, testCase, p)
    verify(flow !== null)
    for (var spy of [tabSpy, recordSpy, captureSpy]) {
      spy.clear()
      spy.target = flow
    }
    return flow
  }

  // Let Qt.callLater run.
  function turn() {
    wait(0)
    wait(0)
  }

  function test_the_state_used_by_these_tests_steers_the_opening_tab() {
    var flow = makeFlow()
    fakeEngine.state = stateWith(0)
    compare(flow.begin({}), testCase.layout, "no slots: the Layout tab")
    fakeEngine.state = stateWith(2)
    compare(flow.begin({}), testCase.assignment, "slots: Assignment")
  }

  function test_opening_before_any_state_shows_assignment_and_settles_later() {
    var flow = makeFlow()
    compare(flow.begin({}), testCase.assignment)
    verify(flow.pendingTab)
    flow.settleTab()
    compare(tabSpy.count, 0, "nothing to settle on yet")
    verify(flow.pendingTab)
    fakeEngine.state = stateWith(0)
    flow.settleTab()
    compare(tabSpy.count, 1)
    compare(tabSpy.signalArguments[0][0], testCase.layout)
    verify(!flow.pendingTab)
    // Only the first read after opening settles it.
    fakeEngine.state = stateWith(3)
    flow.settleTab()
    compare(tabSpy.count, 1)
  }

  function test_a_tab_picked_before_the_state_is_read_stays() {
    var flow = makeFlow()
    flow.begin({})
    flow.tabPicked()
    fakeEngine.state = stateWith(0)
    flow.settleTab()
    compare(tabSpy.count, 0)
  }

  function test_a_tab_the_payload_asks_for_is_not_settled_again() {
    var flow = makeFlow()
    compare(flow.begin({ tab: "Desk" }), testCase.desk)
    verify(!flow.pendingTab)
    fakeEngine.state = stateWith(0)
    flow.settleTab()
    compare(tabSpy.count, 0)
  }

  function test_an_unknown_tab_name_is_not_asked_for() {
    var flow = makeFlow()
    compare(flow.begin({ tab: "Nope" }), testCase.assignment)
    verify(flow.pendingTab)
  }

  function test_a_missing_payload_is_an_empty_one() {
    var flow = makeFlow()
    compare(flow.begin(null), testCase.assignment)
    compare(flow.begin(undefined), testCase.assignment)
    verify(flow.pendingTab)
    verify(!flow.pendingRecord && !flow.pendingCapture)
  }

  function test_record_waits_for_the_state_then_starts_once() {
    var flow = makeFlow()
    compare(flow.begin({ record: true }), testCase.layout)
    verify(flow.pendingRecord)
    verify(!flow.pendingTab, "Record asks for the Layout tab")
    turn()
    compare(recordSpy.count, 0, "no state yet: it waits")
    verify(flow.pendingRecord)
    fakeEngine.state = stateWith(1)
    flow.startRecord()
    compare(recordSpy.count, 1)
    verify(!flow.pendingRecord)
    flow.startRecord()
    compare(recordSpy.count, 1, "started once")
    compare(captureSpy.count, 0)
  }

  function test_record_starts_on_the_next_turn_when_the_state_is_there() {
    var flow = makeFlow()
    fakeEngine.state = stateWith(1)
    flow.begin({ record: true })
    compare(recordSpy.count, 0, "not inside open() itself")
    tryCompare(recordSpy, "count", 1)
    verify(!flow.pendingRecord)
  }

  function test_capture_waits_for_the_state_then_starts_once() {
    var flow = makeFlow()
    compare(flow.begin({ capture: true }), testCase.layout)
    turn()
    compare(captureSpy.count, 0)
    fakeEngine.state = stateWith(0)
    flow.startCapture()
    compare(captureSpy.count, 1)
    flow.startCapture()
    compare(captureSpy.count, 1)
    compare(recordSpy.count, 0)
  }

  function test_capture_starts_on_the_next_turn_when_the_state_is_there() {
    var flow = makeFlow()
    fakeEngine.state = stateWith(2)
    flow.begin({ capture: true })
    tryCompare(captureSpy, "count", 1)
  }

  function test_record_and_capture_both_pending() {
    var flow = makeFlow()
    flow.begin({ record: true, capture: true })
    turn()
    fakeEngine.state = stateWith(1)
    flow.startRecord()
    flow.startCapture()
    compare(recordSpy.count, 1)
    compare(captureSpy.count, 1)
  }

  function test_only_a_true_record_or_capture_counts() {
    var flow = makeFlow()
    flow.begin({ record: "yes", capture: 1 })
    verify(!flow.pendingRecord)
    verify(!flow.pendingCapture)
    verify(flow.pendingTab)
  }

  function test_nothing_starts_while_the_panel_is_closed() {
    var flow = makeFlow()
    flow.begin({ record: true, capture: true })
    flow.opened = false
    fakeEngine.state = stateWith(1)
    turn()
    flow.startRecord()
    flow.startCapture()
    compare(recordSpy.count, 0)
    compare(captureSpy.count, 0)
    verify(flow.pendingRecord, "still owed until the panel says it closed")
  }

  function test_nothing_starts_without_an_engine() {
    var flow = makeFlow({ engine: null })
    compare(flow.begin({}), testCase.assignment)
    flow.begin({ record: true })
    turn()
    flow.startRecord()
    flow.settleTab()
    compare(recordSpy.count, 0)
    compare(tabSpy.count, 0)
    verify(flow.pendingRecord)
  }

  function test_closing_drops_what_is_owed() {
    var flow = makeFlow()
    flow.begin({ record: true })
    flow.begin({ capture: true })
    flow.begin({})
    verify(flow.pendingRecord && flow.pendingCapture && flow.pendingTab)
    flow.end()
    verify(!flow.pendingRecord && !flow.pendingCapture && !flow.pendingTab)
    fakeEngine.state = stateWith(1)
    flow.startRecord()
    flow.startCapture()
    flow.settleTab()
    compare(recordSpy.count + captureSpy.count + tabSpy.count, 0)
  }

  function test_reopening_without_record_keeps_one_still_owed() {
    // Open again (an IPC open while open) before the state: the first
    // payload's Record is still owed, as before the panel had OpenFlow.
    var flow = makeFlow()
    flow.begin({ record: true })
    flow.begin({})
    verify(flow.pendingRecord)
    fakeEngine.state = stateWith(1)
    flow.startRecord()
    compare(recordSpy.count, 1)
  }
}
