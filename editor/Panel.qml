pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The hyprslots editor panel (docs/design.md §9): aerolayout's `edit` TUI as
// an Omarchy shell panel. Four tabs, cycled with Tab / Shift+Tab as in the
// TUI: Assignment (which window fills which slot), Layout, Slots and
// Arrangements (the last three arrive in later slices). Esc or q closes it.
//
//   omarchy-shell shell toggle milan.hyprslots
//   omarchy-shell shell call milan.hyprslots press a   (a key, for scripts and tests)
Item {
  id: root

  // Injected by the shell after creation.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  property var service: null // the plugin's Engine.qml

  // The host's toggle reads this.
  property bool opened: false

  readonly property string pluginId: manifest && manifest.id ? manifest.id : "milan.hyprslots"
  // The service, or an engine of the panel's own when it runs without one.
  readonly property var engine: service ? service : (ownEngine.item ? ownEngine.item : null)

  readonly property var tabs: ["Assignment", "Layout", "Slots", "Arrangements"]
  property int tab: 0

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int cardWidth: Math.min(Style.space(1100), window.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), window.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    if (root.engine) {
      root.engine.active = true
      root.engine.refresh()
    }
    var monitor = Hyprland.focusedMonitor
    assignmentView.focusedWorkspace = monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    assignmentView.reset()
    layoutView.focusedWorkspace = assignmentView.focusedWorkspace
    layoutView.reset()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    if (root.engine) root.engine.active = false
  }

  // User-initiated close: keep the host's open state in step.
  function dismiss() {
    root.close()
    if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  // One key press, from the keyboard or from press(). Returns whether the
  // panel used it.
  function handleKey(key, text, modifiers) {
    if (assignmentView.prompting && root.tab === 0) return assignmentView.handleKey(key, text, modifiers)
    if (layoutView.prompting && root.tab === 1) return layoutView.handleKey(key, text, modifiers)
    if (key === Qt.Key_Backtab || (key === Qt.Key_Tab && (modifiers & Qt.ShiftModifier))) {
      root.tab = (root.tab + root.tabs.length - 1) % root.tabs.length
      return true
    }
    if (key === Qt.Key_Tab) {
      root.tab = (root.tab + 1) % root.tabs.length
      return true
    }
    if (key === Qt.Key_Escape || text === "q") {
      root.dismiss()
      return true
    }
    if (root.tab === 0) return assignmentView.handleKey(key, text, modifiers)
    if (root.tab === 1) return layoutView.handleKey(key, text, modifiers)
    return false
  }

  // A key by name ("a", "Tab", "Escape", "Down", ...), as if pressed: for
  // `omarchy-shell shell call milan.hyprslots press <key>` and the e2e smoke.
  function press(name) {
    var named = {
      Tab: Qt.Key_Tab, Backtab: Qt.Key_Backtab, Escape: Qt.Key_Escape, Return: Qt.Key_Return,
      Up: Qt.Key_Up, Down: Qt.Key_Down, Left: Qt.Key_Left, Right: Qt.Key_Right,
      BackSpace: Qt.Key_Backspace, Backspace: Qt.Key_Backspace,
    }
    var s = String(name)
    var key = named[s]
    var text = ""
    if (key === undefined) {
      if (s.length !== 1) return "unknown key " + s
      text = s
      key = s.toUpperCase().charCodeAt(0) // Qt.Key_A..Key_Z and Key_0..Key_9 are their ASCII codes
    }
    return root.handleKey(key, text, 0) ? "ok" : "ignored"
  }

  // What the Assignment view has selected, "<status> <slot> <class>", and
  // its message or prompt line: for scripts and the e2e smoke.
  function selectionText() {
    if (root.tab === 1) return layoutView.selectionText()
    var row = assignmentView.selectedRow
    return row ? row.status + " " + (row.slot || "-") + " " + (row.cls || row.spec) : ""
  }

  // The Layout view's draft trees, "big: h[a, b]; side: c" (edited ones
  // marked *): for the e2e smoke.
  function layoutText() {
    return layoutView.draftText()
  }

  function messageText() {
    if (root.tab === 1) return layoutView.messageText()
    return assignmentView.prompting ? assignmentView.prompt.text : assignmentView.message
  }

  Loader {
    id: ownEngine
    active: !root.service
    source: "Engine.qml"
  }

  OverlayWindow {
    id: window
    shown: root.opened
    WlrLayershell.namespace: "milan-hyprslots"

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.handleKey(event.key, event.text, event.modifiers)) event.accepted = true
        }
      }

      Column {
        id: layout
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.md

        // The tab bar, as the TUI draws it: the current tab reversed.
        Row {
          id: tabBar
          spacing: Style.spacing.sm
          Repeater {
            model: root.tabs
            delegate: Rectangle {
              required property string modelData
              required property int index
              readonly property bool current: index === root.tab
              width: label.implicitWidth + Style.spacing.lg * 2
              height: label.implicitHeight + Style.spacing.sm * 2
              radius: Style.cornerRadius
              color: current ? root.selectedBackground : "transparent"
              Text {
                id: label
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: parent.modelData
                color: parent.current ? root.selectedText : root.foreground
                opacity: parent.current ? 1 : 0.6
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: parent.current
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.tab = parent.index
              }
            }
          }
        }

        Item {
          id: body
          width: parent.width
          height: parent.height - tabBar.height - help.height - layout.spacing * 2

          AssignmentView {
            id: assignmentView
            anchors.fill: parent
            visible: root.tab === 0
            engine: root.engine
            foreground: root.foreground
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
          }

          LayoutView {
            id: layoutView
            anchors.fill: parent
            visible: root.tab === 1
            engine: root.engine
            foreground: root.foreground
            selectedBackground: root.selectedBackground
            selectedText: root.selectedText
            fontFamily: root.fontFamily
          }

          PlaceholderView {
            anchors.fill: parent
            visible: root.tab > 1
            view: root.tabs[root.tab]
            engine: root.engine
            foreground: root.foreground
            fontFamily: root.fontFamily
          }
        }

        // The controls strip: what the keys of the current view do.
        Text {
          id: help
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          text: root.tab === 0 ? assignmentView.helpText
            : root.tab === 1 ? layoutView.helpText
            : "Tab switch view   ·   q close"
          color: root.foreground
          opacity: 0.7
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
