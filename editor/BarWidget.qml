pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "BarStatus.js" as BarStatus
import "Services.js" as Services

// The hyprslots bar widget (docs/design.md §9): a grid glyph and
// the active layout's name, a dot
// while edits are unsaved, red with the error in the tooltip when the engine
// has a config error, refused to run, is not loaded, or the plugin's service
// is missing. The state is the service's (Engine.qml): the widget only asks
// it to follow events (watch / unwatch), it never polls of its own.
//
// Left click toggles the editor panel; right click opens a menu: Re-apply
// layout, Record workspace (the panel's Layout tab, R), Save (with unsaved edits),
// Reload config. The model is BarStatus.js.
BarWidget {
  id: root
  moduleName: "milan.hyprslots"

  readonly property string pluginId: "milan.hyprslots"

  // The plugin's service: from the bar's facade (Omarchy's own bar), else
  // where the service registered itself (a replacement bar's facade has no
  // serviceFor; Services.js). Services can come up after the bar's
  // widgets, so a missing one is asked for again; a destroyed one (a
  // plugin reload) reads as null.
  property var engine: null
  property var watched: null

  function lookUpEngine() {
    var shell = root.bar ? root.bar.shell : null
    var found = shell && typeof shell.serviceFor === "function" ? shell.serviceFor(root.pluginId) : null
    if (!found) found = Services.engine()
    if (found === root.engine) return
    if (root.watched) {
      try {
        root.watched.unwatch()
      } catch (e) {
        if (!(e instanceof TypeError)) throw e // destroyed with its plugin's reload
      }
    }
    root.engine = found
    root.watched = found
    if (found) found.watch()
  }

  onBarChanged: lookUpEngine()
  Component.onCompleted: lookUpEngine()
  Component.onDestruction: if (root.watched) root.watched.unwatch()

  // Also while one is found: after a plugin reload the service is a new
  // object, and the old one going away notifies nothing here.
  Timer {
    interval: 2000
    repeat: true
    running: true
    onTriggered: root.lookUpEngine()
  }

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property int workspaceId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1

  readonly property var input: ({
    engine: root.engine !== null,
    error: root.engine ? root.engine.error : "",
    state: root.engine ? root.engine.state : null,
    workspaceId: root.workspaceId,
  })
  readonly property var status: BarStatus.view(input)
  readonly property var menuItems: BarStatus.menu(input)

  property bool menuOpen: false

  // For the e2e smoke and scripts: what the widget shows.
  readonly property string labelText: status.label
  readonly property string statusText: status.status

  // A click as if on the button (Qt.LeftButton / Qt.RightButton): for the
  // e2e smoke.
  function press(mouseButton) {
    button.triggerPress(mouseButton)
  }

  function toggleEditor() {
    var shell = root.bar ? root.bar.shell : null
    if (shell && typeof shell.toggle === "function") shell.toggle(root.pluginId, "{}")
  }

  function close() {
    root.menuOpen = false
  }

  function notify(text, urgent) {
    if (!root.bar) return
    root.bar.run("notify-send -a Hyprslots" + (urgent ? " -u critical" : "") + " Hyprslots " + Util.shellQuote(text))
  }

  function choose(id) {
    root.menuOpen = false
    var shell = root.bar ? root.bar.shell : null
    if (id === "record") {
      if (shell && typeof shell.summon === "function") shell.summon(root.pluginId, JSON.stringify({ record: true }))
      return
    }
    if (!root.engine) return
    var workspace = root.status.workspace
    var steps = BarStatus.calls(id, workspace)
    var run = function(i) {
      root.engine.call(steps[i].name, steps[i].args, function(reply) {
        if (reply.ok && i + 1 < steps.length) {
          run(i + 1)
          return
        }
        root.notify(BarStatus.outcome(id, workspace, reply), !reply.ok)
      })
    }
    if (steps.length > 0) run(0)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.status.label
    active: root.status.status === "error"
    tooltipText: root.status.tooltip
    horizontalMargin: 6
    fixedHeight: root.vertical ? -1 : root.barSize
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.RightButton) root.menuOpen = !root.menuOpen
      else if (mouseButton === Qt.LeftButton) {
        root.menuOpen = false
        root.toggleEditor()
      }
    }
  }

  PopupCard {
    id: menuPopup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.menuOpen
    padding: Style.space(8)
    contentWidth: menuPopup.fittedContentWidth(Style.space(232))
    contentHeight: menuPopup.fittedContentHeight(menuColumn.implicitHeight)

    readonly property color foreground: root.bar ? root.bar.foreground : Commons.Color.foreground
    readonly property string fontFamily: root.bar && root.bar.fontFamily !== "" ? root.bar.fontFamily : Style.font.family

    Column {
      id: menuColumn
      width: parent.width
      spacing: 0

      Repeater {
        model: root.menuItems

        delegate: Item {
          id: row
          required property var modelData
          width: menuColumn.width
          implicitHeight: Style.space(30)
          opacity: modelData.enabled ? 1 : 0.45

          Rectangle {
            anchors.fill: parent
            radius: Math.max(2, Style.cornerRadius)
            color: rowMouse.containsMouse && row.modelData.enabled
              ? Style.hoverFillFor(menuPopup.foreground, menuPopup.foreground) : "transparent"
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: Style.space(10)
            anchors.right: parent.right
            anchors.rightMargin: Style.space(10)
            textFormat: Text.PlainText
            text: row.modelData.label
            color: menuPopup.foreground
            font.family: menuPopup.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }

          MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: row.modelData.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.choose(row.modelData.id)
          }
        }
      }
    }
  }
}
