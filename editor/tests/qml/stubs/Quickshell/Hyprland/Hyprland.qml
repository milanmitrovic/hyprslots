pragma Singleton
import QtQuick

// Quickshell.Hyprland's Hyprland, for editor/tests/qml: a test fires
// rawEvent({ name, data }) as socket2 would.
QtObject {
  property var focusedMonitor: null
  signal rawEvent(var event)
}
