import QtQuick
import QtTest
import Quickshell.Io
import Quickshell.Hyprland
import "../.."
import "../../Protocol.js" as Protocol
import "../../Services.js" as Services

// Engine.qml (the editor's service) against stub Quickshell modules
// (stubs/): its one-at-a-time command queue, the debounced state read, the
// watchdog, events, and Enable. Nothing runs: each command is a stub
// Process the test answers through ProcessLog.
TestCase {
  id: testCase
  name: "Engine"
  when: windowShown

  Component {
    id: engineComponent
    Engine {}
  }

  SignalSpy {
    id: repliedSpy
    signalName: "replied"
  }

  SignalSpy {
    id: stateReadSpy
    signalName: "stateRead"
  }

  // Wide enough that a busy machine still runs the debounce and the
  // watchdog in time: assertions wait with tryCompare, never a fixed sleep
  // shorter than these.
  readonly property int debounceMs: 40
  readonly property int timeoutMs: 400

  function makeEngine(props) {
    var p = { debounceMs: testCase.debounceMs, timeoutMs: testCase.timeoutMs }
    for (var k in props || {}) p[k] = props[k]
    var engine = createTemporaryObject(engineComponent, testCase, p)
    verify(engine !== null, "Engine is created")
    repliedSpy.clear()
    repliedSpy.target = engine
    stateReadSpy.clear()
    stateReadSpy.target = engine
    return engine
  }

  function init() {
    ProcessLog.reset()
  }

  function stateJson(extra) {
    var s = { ok: true, seq: 1 }
    for (var k in extra || {}) s[k] = extra[k]
    return JSON.stringify(s)
  }

  function isState(entry) {
    return JSON.stringify(entry.command) === JSON.stringify(Protocol.stateCommand())
  }

  // Wait until `n` processes have been made.
  function waitForProcesses(n) {
    tryVerify(function() { return ProcessLog.count() === n }, 5000, "expected " + n + " processes")
  }

  // Wait out a debounce (no read may start from it), then a margin.
  function settleDebounce() {
    wait(testCase.debounceMs * 3)
  }

  function test_call_runs_its_command_and_hands_back_the_reply() {
    var engine = makeEngine()
    var got = null
    engine.call("save", { force: true }, function(reply) { got = reply })
    compare(ProcessLog.count(), 1)
    compare(ProcessLog.last().command, Protocol.callCommand("save", { force: true }))
    verify(engine.busy)
    ProcessLog.finish(0, '{"ok":true,"saved":2}', 0)
    verify(got !== null, "done ran")
    compare(got.ok, true)
    compare(got.saved, 2)
    compare(repliedSpy.count, 1)
    compare(repliedSpy.signalArguments[0][0], "save")
    compare(engine.lastError, "")
  }

  function test_a_call_without_args_or_done_sends_an_empty_object() {
    var engine = makeEngine()
    engine.call("reload")
    compare(ProcessLog.last().command, Protocol.callCommand("reload", {}))
    ProcessLog.finish(0, '{"ok":true}', 0)
    compare(repliedSpy.count, 1)
  }

  function test_an_ok_call_reads_state_after_the_debounce() {
    var engine = makeEngine()
    engine.call("save", {}, null)
    ProcessLog.finish(0, '{"ok":true}', 0)
    // The re-read is pending (debounced): busy until it lands.
    verify(engine.busy)
    waitForProcesses(2)
    verify(isState(ProcessLog.last()), "the second command reads state")
    ProcessLog.finish(1, stateJson({ seq: 7 }), 0)
    compare(engine.state.seq, 7)
    compare(engine.error, "")
    compare(stateReadSpy.count, 1)
    compare(stateReadSpy.signalArguments[0][0], true)
    tryCompare(engine, "busy", false)
  }

  function test_a_failed_call_keeps_its_error_and_reads_no_state() {
    var engine = makeEngine()
    var got = null
    engine.call("assign", { app: "x" }, function(reply) { got = reply })
    ProcessLog.finish(0, '{"ok":false,"error":"no such slot"}', 0)
    compare(got.ok, false)
    compare(got.error, "no such slot")
    compare(engine.lastError, "no such slot")
    settleDebounce()
    compare(ProcessLog.count(), 1, "no state read after a failed call")
    compare(engine.busy, false)
  }

  function test_hyprctl_exit_code_is_a_failure() {
    var engine = makeEngine()
    var got = null
    engine.call("save", {}, function(reply) { got = reply })
    ProcessLog.finish(0, "Couldn't connect", 1)
    compare(got.ok, false)
    verify(got.error.indexOf("hyprctl exited 1") === 0, got.error)
    compare(engine.lastError, got.error)
  }

  function test_commands_run_one_at_a_time_in_order() {
    var engine = makeEngine()
    var order = []
    engine.call("a", {}, function() { order.push("a") })
    engine.call("b", {}, function() { order.push("b") })
    engine.call("c", {}, function() { order.push("c") })
    compare(ProcessLog.count(), 1, "only the first runs")
    compare(engine._queue.length, 2)
    ProcessLog.finish(0, '{"ok":false,"error":"x"}', 0)
    // The next one starts once the event loop turns (Qt.callLater).
    waitForProcesses(2)
    compare(ProcessLog.last().command, Protocol.callCommand("b", {}))
    ProcessLog.finish(1, '{"ok":false,"error":"x"}', 0)
    waitForProcesses(3)
    compare(ProcessLog.last().command, Protocol.callCommand("c", {}))
    ProcessLog.finish(2, '{"ok":false,"error":"x"}', 0)
    compare(order, ["a", "b", "c"])
    tryCompare(engine, "busy", false)
  }

  function test_a_reply_settles_only_on_both_output_and_exit() {
    var engine = makeEngine()
    var got = null
    engine.call("save", {}, function(reply) { got = reply })
    var proc = ProcessLog.last().proc
    proc.exited(0, 0)
    compare(got, null, "exit alone does not settle")
    proc.stdout.text = '{"ok":true}'
    proc.stdout.streamFinished()
    verify(got !== null && got.ok, "settles once the output is in too")
  }

  function test_output_before_exit_settles_too() {
    var engine = makeEngine()
    var got = null
    engine.call("save", {}, function(reply) { got = reply })
    var proc = ProcessLog.last().proc
    proc.stdout.text = '{"ok":true}'
    proc.stdout.streamFinished()
    compare(got, null, "output alone does not settle")
    proc.exited(0, 0)
    verify(got !== null && got.ok)
  }

  function test_refresh_bursts_are_one_read() {
    var engine = makeEngine()
    engine.refresh()
    engine.refresh()
    engine.refresh()
    verify(engine.busy, "busy while a read is pending")
    waitForProcesses(1)
    verify(isState(ProcessLog.last()))
    settleDebounce()
    compare(ProcessLog.count(), 1, "one read for the burst")
    ProcessLog.finish(0, stateJson(), 0)
    settleDebounce()
    compare(ProcessLog.count(), 1, "no second read is left behind it")
    compare(engine.busy, false)
  }

  function test_one_state_read_waits_behind_a_call() {
    var engine = makeEngine()
    engine.call("slow", {}, null)
    // Two debounced reads land while the call runs: one read is queued.
    engine.refresh()
    tryVerify(function() { return engine._queue.length === 1 })
    engine.refresh()
    settleDebounce()
    compare(engine._queue.length, 1, "a second read is not queued")
    compare(engine._queue[0].kind, "state")
  }

  function test_a_failed_state_read_keeps_the_last_state() {
    var engine = makeEngine()
    engine.refresh()
    waitForProcesses(1)
    ProcessLog.finish(0, stateJson({ seq: 3 }), 0)
    compare(engine.state.seq, 3)
    engine.refresh()
    waitForProcesses(2)
    ProcessLog.finish(1, "garbage", 0)
    compare(engine.state.seq, 3, "the views keep the last good state")
    verify(engine.error.indexOf("did not answer") >= 0, engine.error)
    compare(stateReadSpy.count, 2)
    compare(stateReadSpy.signalArguments[1][0], false)
    compare(engine.lastError, "", "a state read is no call")
    compare(repliedSpy.count, 0)
  }

  function test_an_absent_engine_is_said_with_its_load_error() {
    var engine = makeEngine()
    engine.refresh()
    waitForProcesses(1)
    ProcessLog.finish(0, Protocol.ABSENT + " config.lua:3: boom", 0)
    compare(engine.absent, true)
    compare(engine.loadError, "config.lua:3: boom")
    compare(engine.state, null)
    // The engine comes back: absent and its error clear.
    engine.refresh()
    waitForProcesses(2)
    ProcessLog.finish(1, stateJson(), 0)
    compare(engine.absent, false)
    compare(engine.loadError, "")
    compare(engine.error, "")
  }

  function test_absent_with_no_load_error() {
    var engine = makeEngine()
    engine.refresh()
    waitForProcesses(1)
    ProcessLog.finish(0, Protocol.ABSENT + " ", 0)
    compare(engine.absent, true)
    compare(engine.loadError, "")
    compare(engine.error, "the hyprslots engine is not running")
  }

  function test_the_watchdog_fails_a_wedged_command_and_moves_on() {
    var engine = makeEngine()
    var got = null
    engine.call("wedged", {}, function(reply) { got = reply })
    engine.call("next", {}, null)
    var wedged = ProcessLog.entries[0]
    tryVerify(function() { return got !== null }, testCase.timeoutMs * 10)
    compare(got.ok, false)
    compare(got.error, "hyprctl did not answer within " + testCase.timeoutMs + " ms")
    compare(engine.lastError, got.error)
    verify(wedged.stopped, "the wedged process is stopped")
    waitForProcesses(2)
    compare(ProcessLog.last().command, Protocol.callCommand("next", {}))
  }

  function test_the_watchdog_is_reset_by_each_command() {
    var engine = makeEngine()
    var got = []
    engine.call("a", {}, function(reply) { got.push(reply) })
    engine.call("b", {}, function(reply) { got.push(reply) })
    // a answers just before its timeout; b gets a full timeout of its own.
    wait(testCase.timeoutMs * 0.6)
    ProcessLog.finish(0, '{"ok":false,"error":"x"}', 0)
    waitForProcesses(2)
    wait(testCase.timeoutMs * 0.6)
    compare(got.length, 1, "b has not timed out on a's clock")
    ProcessLog.finish(1, '{"ok":false,"error":"y"}', 0)
    compare(got[1].error, "y")
  }

  function test_a_throwing_reply_handler_does_not_stop_the_queue() {
    var engine = makeEngine()
    ignoreWarning(/reply handler for boom failed/)
    engine.call("boom", {}, function() { throw new Error("oops") })
    engine.call("after", {}, null)
    ProcessLog.finish(0, '{"ok":false,"error":"x"}', 0)
    compare(repliedSpy.count, 1, "replied still fires")
    waitForProcesses(2)
    compare(ProcessLog.last().command, Protocol.callCommand("after", {}))
  }

  function test_events_are_followed_only_while_someone_looks() {
    var engine = makeEngine()
    Hyprland.rawEvent({ name: "custom", data: "hyprslots changed 4" })
    settleDebounce()
    compare(ProcessLog.count(), 0, "nobody looks: no read")
    engine.watch()
    // Following starts with a read of its own.
    waitForProcesses(1)
    ProcessLog.finish(0, stateJson(), 0)
    Hyprland.rawEvent({ name: "custom", data: "hyprslots changed 5" })
    waitForProcesses(2)
    ProcessLog.finish(1, stateJson(), 0)
    Hyprland.rawEvent({ name: "workspace", data: "3" })
    Hyprland.rawEvent({ name: "custom", data: "something else" })
    settleDebounce()
    compare(ProcessLog.count(), 2, "unrelated events read nothing")
    Hyprland.rawEvent({ name: "openwindow", data: "abc,1,foot,foot" })
    waitForProcesses(3)
    ProcessLog.finish(2, stateJson(), 0)
    engine.unwatch()
    compare(engine.following, false)
    Hyprland.rawEvent({ name: "custom", data: "hyprslots changed 6" })
    settleDebounce()
    compare(ProcessLog.count(), 3, "no reads once nobody looks")
  }

  function test_watchers_count_and_never_go_below_zero() {
    var engine = makeEngine()
    engine.unwatch()
    compare(engine.watchers, 0)
    engine.watch()
    engine.watch()
    engine.unwatch()
    compare(engine.watchers, 1)
    verify(engine.following)
    engine.unwatch()
    engine.unwatch()
    compare(engine.watchers, 0)
    verify(!engine.following)
  }

  function test_opening_the_panel_reads_even_while_a_widget_follows() {
    var engine = makeEngine()
    engine.watch()
    waitForProcesses(1)
    ProcessLog.finish(0, stateJson(), 0)
    engine.active = true
    waitForProcesses(2)
    verify(isState(ProcessLog.last()))
  }

  function test_null_and_dataless_events_are_ignored_or_read() {
    var engine = makeEngine({ active: true })
    waitForProcesses(1)
    ProcessLog.finish(0, stateJson(), 0)
    Hyprland.rawEvent(null)
    settleDebounce()
    compare(ProcessLog.count(), 1)
    Hyprland.rawEvent({ name: "configreloaded" })
    waitForProcesses(2)
  }

  function test_the_service_registers_and_a_panel_owned_engine_does_not() {
    var service = makeEngine()
    compare(Services.engine(), service)
    var own = makeEngine({ panelOwned: true })
    compare(Services.engine(), service, "the panel's own engine is not for widgets")
    own.destroy()
    service.destroy()
    wait(0)
    compare(Services.engine(), null)
  }

  function test_enable_runs_the_script_with_the_chosen_options() {
    var engine = makeEngine()
    var got = null
    engine.enable(function(result) { got = result }, { keys: true, menu: false })
    verify(engine.enabling)
    compare(ProcessLog.count(), 1)
    var argv = ProcessLog.last().command
    compare(argv[0], "bash")
    verify(/\/tools\/install-engine\.sh$/.test(argv[1]), argv[1])
    compare(argv.slice(2), ["--keys"])
    // A second Enable while one runs does nothing.
    engine.enable(null, {})
    compare(ProcessLog.count(), 1)
    ProcessLog.finish(0, "Bound Super+Ctrl+Y\nThe hyprslots engine is running.", 0, "")
    compare(engine.enabling, false)
    compare(engine.enableError, "")
    compare(got.ok, true)
    verify(got.message.indexOf("running") >= 0, got.message)
    // Enabled: the state is read again.
    waitForProcesses(2)
    verify(isState(ProcessLog.last()))
  }

  function test_enable_defaults_to_the_install_defaults() {
    var engine = makeEngine()
    engine.enable()
    compare(ProcessLog.last().command.slice(2), ["--menu"])
    ProcessLog.finish(0, "", 0, "")
    compare(engine.enabling, false)
  }

  function test_enable_waits_for_output_errors_and_exit() {
    var engine = makeEngine()
    var got = null
    engine.enable(function(result) { got = result })
    var proc = ProcessLog.last().proc
    proc.stdout.text = ""
    proc.stdout.streamFinished()
    proc.exited(1, 0)
    compare(got, null, "stderr is not in yet")
    verify(engine.enabling)
    proc.stderr.text = "install-engine.sh: no workspace-layouts folder\n"
    proc.stderr.streamFinished()
    compare(got.ok, false)
    compare(got.message, "no workspace-layouts folder")
    compare(engine.enableError, "no workspace-layouts folder")
    compare(engine.enabling, false)
  }

  function test_enable_times_out() {
    var engine = makeEngine({ enableTimeoutMs: testCase.timeoutMs })
    var got = null
    engine.enable(function(result) { got = result })
    var entry = ProcessLog.last()
    tryVerify(function() { return got !== null }, testCase.timeoutMs * 10)
    compare(got.ok, false)
    compare(got.message, "tools/install-engine.sh did not finish within " + testCase.timeoutMs / 1000 + " s")
    compare(engine.enableError, got.message)
    compare(engine.enabling, false)
    verify(entry.stopped, "the script is stopped")
    // Enable can be tried again.
    engine.enable(null)
    verify(engine.enabling)
  }

  function test_a_throwing_enable_handler_still_finishes() {
    var engine = makeEngine()
    ignoreWarning(/enable handler failed/)
    engine.enable(function() { throw new Error("oops") })
    ProcessLog.finish(0, "ok", 0, "")
    compare(engine.enabling, false)
  }
}
