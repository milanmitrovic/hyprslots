import QtQuick

// Quickshell.Io's StdioCollector, for editor/tests/qml: a test sets `text`
// and fires streamFinished() (FakeProcess.finish does both).
QtObject {
  property string text: ""
  signal streamFinished()
}
