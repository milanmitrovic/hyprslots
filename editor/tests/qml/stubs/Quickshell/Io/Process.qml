import QtQuick

// Quickshell.Io's Process, for editor/tests/qml: nothing runs. Each one is
// logged in ProcessLog as it is made, with the argv it was given; a test
// answers it through its collectors and exited() (ProcessLog.finish), and
// sees it stopped (`running` set false: killed) in its log entry.
QtObject {
  id: proc

  property var command: []
  property bool running: false
  property QtObject stdout: null
  property QtObject stderr: null

  signal exited(int exitCode, int exitStatus)

  Component.onCompleted: ProcessLog.add(proc)
  onRunningChanged: if (!running) ProcessLog.stopped(proc)
}
