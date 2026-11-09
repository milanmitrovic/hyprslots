pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "editor" as Editor

// A minimal Quickshell config that runs the editor plugin's service and panel
// standalone, for e2e/editor_smoke.sh. It stands in for the Omarchy shell:
// it injects the service and manifest the way the shell's loader does, and
// adds an IPC target the smoke drives with `qs ipc -p <dir> call smoke ...`.
// `editor`, `Commons` and `Ui` next to this file are links the smoke makes
// to the plugin and to Omarchy's shell modules (qs.Commons is the config
// root's Commons/). The bar widget is loaded on demand (`smoke bar`), in a
// strip at the top standing in for Omarchy's bar: a PluginBarApi like the
// one the bar hands an installed widget, whose shell toggles the panel as
// a replacement bar's entry facade does (no serviceFor).
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

  // The shell's facade for the plugin's bar entry as a replacement bar (a
  // `kind: bar` plugin such as a clone of omarchy.bar) gets it: it toggles
  // and summons the plugin's own panel but has no serviceFor (only the
  // built-in bar's facade does), so the widget finds the service the way it
  // must there.
  QtObject {
    id: fakeShell
    function toggle(id, payloadJson) {
      if (id !== "milan.hyprslots") return false
      if (panel.opened) panel.close()
      else panel.open(payloadJson || "{}")
      return true
    }
    function summon(id, payloadJson) {
      if (id !== "milan.hyprslots") return false
      panel.open(payloadJson || "{}")
      return true
    }
    function hide(id) {
      if (id !== "milan.hyprslots") return false
      panel.close()
      return true
    }
  }

  // What the widget asked the bar to run (notify-send): logged, not run, so
  // the smoke never reaches the desktop's notification daemon.
  property string lastRun: ""

  PluginBarApi {
    id: fakeBar
    pluginId: "milan.hyprslots"
    moduleName: "milan.hyprslots"
    shell: fakeShell
    foreground: Commons.Color.bar.text
    barForeground: Commons.Color.bar.text
    background: Commons.Color.bar.background
    urgent: Commons.Color.bar.active
    fontFamily: Style.font.family
    position: "top"
    barSize: Style.bar.sizeHorizontal
    _run: function(command) {
      console.log("smoke bar run: " + command)
      root.lastRun = command
    }
  }

  Loader {
    id: barLoader
    active: false
    sourceComponent: PanelWindow {
      id: strip
      property alias widget: widget
      anchors.top: true
      anchors.left: true
      anchors.right: true
      implicitHeight: fakeBar.barSize
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "hyprslots-smoke-bar"
      color: Commons.Color.bar.background

      Editor.BarWidget {
        id: widget
        bar: fakeBar
        anchors.left: parent.left
        anchors.leftMargin: Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }
    }
  }

  readonly property var widget: barLoader.item ? barLoader.item.widget : null

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

    // The Assignment view's rows ("<slot>|<app>|<title>; ...").
    function rows(): string {
      return panel.assignmentRowsText()
    }

    // The Assignment view's message or prompt line.
    function message(): string {
      return panel.messageText()
    }

    // The Layout view's draft trees.
    function layout(): string {
      return panel.layoutText()
    }

    // The panel's tabs, and the current one: "Assignment Layout Desk | Layout".
    function tabs(): string {
      return panel.tabs.join(" ") + " | " + panel.tabs[panel.tab]
    }

    // The header line every tab shows ("Desk: … · Layout: …").
    function header(): string {
      return panel.headerText()
    }

    // The Assignment view's page: "Workspace 3".
    function assignmentPage(): string {
      return panel.assignmentPageText()
    }

    // The current view's help row, as the StyledText it draws (each trigger
    // key in <b><font color=accent>).
    function help(): string {
      return panel.helpText
    }

    // The Layout tab's pane titles, " | " between them, and its header line.
    function panes(): string {
      return panel.layoutPanesText()
    }

    function layoutHeader(): string {
      return panel.layoutHeaderText()
    }

    // The Layout tab's workspace strip, the current one in brackets.
    function layoutStrip(): string {
      return panel.layoutStripText()
    }

    // The Layout tab's warning on a shared layout.
    function sharedNote(): string {
      return panel.layoutSharedNote()
    }

    // The Desk tab's column titles over the desks.
    function deskColumns(): string {
      return panel.deskColumnsText()
    }

    // How many lines the help row wraps to.
    function helpLines(): string {
      return String(panel.helpLines())
    }

    function layoutMode(): string {
      return panel.layoutModeText()
    }

    function press(key: string): string {
      return panel.press(key)
    }

    // The engine's last error (state read or call), "" when fine.
    function errors(): string {
      return engine.error + (engine.lastError !== "" ? " | " + engine.lastError : "")
    }

    // Load the bar widget.
    function bar(): string {
      barLoader.active = true
      return "ok"
    }

    // The widget's label, "<status> <label>" (normal, dirty or error).
    function barLabel(): string {
      return root.widget ? root.widget.statusText + " " + root.widget.labelText : "no widget"
    }

    function barTooltip(): string {
      return root.widget ? root.widget.status.tooltip : "no widget"
    }

    // A click on the widget: "left" or "right".
    function barClick(button: string): string {
      if (!root.widget) return "no widget"
      root.widget.press(button === "right" ? Qt.RightButton : Qt.LeftButton)
      return "ok"
    }

    // The right-click menu, "id on|off label" per entry, and whether it is open.
    function barMenu(): string {
      if (!root.widget) return "no widget"
      return (root.widget.menuOpen ? "open" : "closed") + ": " + root.widget.menuItems.map(function(item) {
        return item.id + " " + (item.enabled ? "on" : "off")
      }).join(", ")
    }

    function barChoose(id: string): string {
      if (!root.widget) return "no widget"
      root.widget.choose(id)
      return "ok"
    }

    function barRun(): string {
      return root.lastRun
    }

    function busy(): string {
      return engine.busy ? "yes" : "no"
    }
  }
}
