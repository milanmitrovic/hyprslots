pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Protocol.js" as Protocol

// The editor's link to the running hyprslots engine (docs/design.md §9), as
// the plugin's service. It talks to the engine only through Hyprland:
//
//   read   hyprctl repl 'return hyprslots.api.state()'
//   write  hyprctl repl 'return hyprslots.api.call(name, json)'
//   push   custom>>hyprslots changed <seq> on socket2 (Hyprland.rawEvent)
//
// Any change event means "read state again" (seq restarts when Hyprland
// reloads its config, so it orders nothing); reads are debounced, so a burst
// of events (a two-axis resize, a re-route moving several windows) is one
// read. Commands run one at a time, in order, each in its own process with
// a timeout. A failure is kept visible: `error` for the last state read,
// `lastError` for the last call, and every call's reply is handed back.
Item {
  id: root

  // Injected by the shell after creation (null in Component.onCompleted).
  property var shell: null
  property var manifest: null

  // Whether anyone is looking (the panel is open). Events are only followed
  // while active, so a closed panel costs nothing.
  property bool active: false

  property var state: null // the last state reply that read fine
  property string error: "" // why the last state read failed, "" when it worked
  property string lastError: "" // the last failed call's error
  property bool busy: _current !== null || _queue.length > 0

  property int debounceMs: 60
  property int timeoutMs: 3000

  // Every reply to a call, ok or not.
  signal replied(string name, var reply)
  // After every state read, whether it worked or not.
  signal stateRead(bool ok)

  property var _queue: []
  property var _current: null

  // Read state soon (debounced).
  function refresh() {
    debounce.restart()
  }

  // Run an api call; `done(reply)` gets {ok:true,...} or {ok:false,error}.
  function call(name, args, done) {
    _enqueue({ kind: "call", name: name, args: args || {}, done: done || null })
  }

  function _enqueue(job) {
    var queue = _queue.slice()
    queue.push(job)
    _queue = queue
    _pump()
  }

  function _readNow() {
    for (var i = 0; i < _queue.length; i++) {
      if (_queue[i].kind === "state") return // one read waiting is enough
    }
    _enqueue({ kind: "state" })
  }

  function _pump() {
    if (_current !== null || _queue.length === 0) return
    var queue = _queue.slice()
    var job = queue.shift()
    _queue = queue
    var command = job.kind === "state" ? Protocol.stateCommand() : Protocol.callCommand(job.name, job.args)
    // It starts as it is created; its output and exit arrive later, from
    // the event loop, so _current is set in time.
    _current = jobComponent.createObject(root, { job: job, command: command, running: true })
    watchdog.restart()
  }

  // A job's process reports twice (its output, its exit); settle on both.
  function _settle(proc) {
    if (!proc.outDone || !proc.exited || proc !== _current) return
    _complete(proc, Protocol.parseReply(proc.out, proc.code))
  }

  function _complete(proc, reply) {
    watchdog.stop()
    var job = proc.job
    _current = null
    proc.destroy()
    if (job.kind === "state") {
      if (reply.ok) {
        state = reply
        error = ""
      } else {
        error = reply.error
      }
      stateRead(reply.ok)
    } else {
      if (!reply.ok) lastError = reply.error
      if (job.done) {
        try {
          job.done(reply)
        } catch (e) {
          console.warn("hyprslots: reply handler for " + job.name + " failed: " + e)
        }
      }
      replied(job.name, reply)
      // The engine announces the change too; the read is debounced, so the
      // two become one.
      if (reply.ok) refresh()
    }
    Qt.callLater(_pump)
  }

  Component {
    id: jobComponent

    Process {
      id: proc

      property var job: null
      property string out: ""
      property bool outDone: false
      property bool exited: false
      property int code: -1

      stdout: StdioCollector {
        onStreamFinished: {
          proc.out = text
          proc.outDone = true
          root._settle(proc)
        }
      }
      onExited: function(exitCode, exitStatus) {
        proc.code = exitCode
        proc.exited = true
        root._settle(proc)
      }
    }
  }

  Timer {
    id: debounce
    interval: root.debounceMs
    onTriggered: root._readNow()
  }

  // A command that never finishes (hyprctl wedged, Hyprland gone) fails
  // instead of blocking every later one.
  Timer {
    id: watchdog
    interval: root.timeoutMs
    onTriggered: {
      var proc = root._current
      if (proc === null) return
      proc.running = false
      root._complete(proc, { ok: false, error: "hyprctl did not answer within " + root.timeoutMs + " ms" })
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (root.active && event && Protocol.meansReread(String(event.name), String(event.data || ""))) root.refresh()
    }
  }

  onActiveChanged: if (active) refresh()
}
