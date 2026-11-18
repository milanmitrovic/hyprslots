pragma Singleton
import QtQuick

// Every stub Process made since the last reset(), oldest first, as
// { command: [argv], proc, stopped }: `proc` is the Process (gone once its
// owner destroys it), `stopped` whether its owner set running false.
QtObject {
  id: log

  property var entries: []

  function reset() {
    log.entries = []
  }

  function add(proc) {
    log.entries = log.entries.concat([{ command: (proc.command || []).slice(), proc: proc, stopped: false }])
  }

  function stopped(proc) {
    for (var i = 0; i < log.entries.length; i++) {
      if (log.entries[i].proc === proc) log.entries[i].stopped = true
    }
  }

  function count() {
    return log.entries.length
  }

  function last() {
    return log.entries.length ? log.entries[log.entries.length - 1] : null
  }

  // Answer the process logged at `index`: its stdout (and stderr, where it
  // has one) finish with these texts, then it exits with `code`.
  function finish(index, out, code, err) {
    var proc = log.entries[index].proc
    proc.stdout.text = out || ""
    proc.stdout.streamFinished()
    if (proc.stderr) {
      proc.stderr.text = err || ""
      proc.stderr.streamFinished()
    }
    proc.exited(code === undefined ? 0 : code, 0)
  }
}
