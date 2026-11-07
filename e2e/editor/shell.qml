pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "editor" as Editor

// A minimal Quickshell config that runs the editor plugin's service and panel
// standalone, for e2e/editor_smoke.sh. It stands in for the Omarchy shell:
// it injects the service and manifest the way the shell's loader does, and
// adds an IPC target the smoke drives with `qs ipc -p <dir> call smoke ...`.
// `editor`, `Commons` and `Ui` next to this file are links the smoke makes
// to the plugin and to Omarchy's shell modules (qs.Commons is the config
// root's Commons/).
ShellRoot {
  id: root

  Editor.Engine {
    id: engine
  }

  Editor.Panel {
    id: panel
    service: engine
    manifest: ({ id: "milan.hyprslots" })
  }

  IpcHandler {
    target: "smoke"

    function open(): string {
      panel.open("{}")
      return "ok"
    }

    // Whether the panel is up and has read the engine's state.
    function ready(): string {
      return panel.opened && engine.state !== null ? "yes" : "no"
    }

    // The selected row of the Assignment view: "<status> <slot> <class>".
    function selection(): string {
      return panel.selectionText()
    }

    // The Assignment view's message or prompt line.
    function message(): string {
      return panel.messageText()
    }

    function press(key: string): string {
      return panel.press(key)
    }

    // The engine's last error (state read or call), "" when fine.
    function errors(): string {
      return engine.error + (engine.lastError !== "" ? " | " + engine.lastError : "")
    }

    function busy(): string {
      return engine.busy ? "yes" : "no"
    }
  }
}
