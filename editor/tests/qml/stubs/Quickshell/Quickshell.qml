pragma Singleton
import QtQuick

// Quickshell's Quickshell singleton, for editor/tests/qml: env() reads
// nothing (the panel's OMARCHY_PATH).
QtObject {
  function env(name) {
    return ""
  }
}
