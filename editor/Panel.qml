pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Prompts.js" as Prompts
import "DesksLayouts.js" as DesksLayouts
import "Assignment.js" as Assignment
import "Messages.js" as Messages

// The hyprslots editor panel (docs/design.md §9): aerolayout's `edit` TUI as
// an Omarchy shell panel. Three tabs, cycled with Tab / Shift+Tab as in the
// TUI: Assignment (which window fills which slot), Layout (one workspace's
// trees in the active desk's layout, with the global slots listed beside
// them, made and placed there) and Desk (the monitor setups and
// the logical layouts they use). A header on every tab names the active
// desk and its layout. Esc or q closes it (while a view's prompt is open, every key
// is the prompt's; in the Layout tab's slot list Esc goes back to the
// picture). Ctrl+S saves in every tab; in the Layout tab it applies the
// edited panes first.
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

  readonly property var tabs: ["Assignment", "Layout", "Desk"]
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
  // The chrome, all from the theme: the card is a recessed desk, the page
  // (and the current tab, one shape with it) the menu surface on it; the
  // other tabs and the controls strip sit back on the desk.
  readonly property int hairline: Math.max(1, Style.spacing.hairline)
  readonly property color deskColor: root.recess(root.background, 1)
  readonly property color tabRecessed: root.recess(root.background, 0.55)
  readonly property color tabRecessedBorder: Commons.Util.alpha(root.foreground, 0.07)
  readonly property color frameBorder: Commons.Util.alpha(root.foreground, 0.16)
  readonly property int tabRadius: Math.max(Style.cornerRadius, Style.spacing.sm)
  readonly property int tabHeight: Style.font.subtitle + Style.spacing.md * 2 + Style.spacing.xs * 2
  readonly property int tabInset: Style.spacing.lg
  readonly property int pagePadding: Style.spacing.xxl

  // A surface sunk below `c` by `amount` (0..1): darker on a light theme
  // and on a dark one; on a near-black one (nothing darker to go to), a
  // trace of the foreground instead.
  function recess(c, amount) {
    if (c.hslLightness < 0.06) return Qt.tint(c, Commons.Util.alpha(root.foreground, 0.035 * amount))
    return Qt.darker(c, 1 + (c.hslLightness > 0.5 ? 0.07 : 0.28) * amount)
  }

  property int cardWidth: Math.min(Style.space(1100), window.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(640), window.height - Style.gapsOut * 2)

  // `{"record": true}` (the bar widget's Record) opens on the Layout tab and
  // starts its record flow (R) once the state is read.
  property bool pendingRecord: false

  function open(payloadJson) {
    var payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}") || {}
    } catch (e) {
      console.warn("hyprslots: ignoring a payload that is no JSON: " + payloadJson)
    }
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
    desksView.reset()
    if (payload.record === true) {
      root.tab = 1
      root.pendingRecord = true
      Qt.callLater(root.startPendingRecord)
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function startPendingRecord() {
    if (!root.pendingRecord || !root.opened || !root.engine || root.engine.state === null) return
    root.pendingRecord = false
    if (!layoutView.prompting) layoutView.recordFocused()
  }

  function close() {
    root.opened = false
    root.pendingRecord = false
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
    if (Messages.dismissedByKey(root.bandKind)) root.dismissedKey = root.messageKey
    if (assignmentView.prompting && root.tab === 0) return assignmentView.handleKey(key, text, modifiers)
    if (layoutView.prompting && root.tab === 1) return layoutView.handleKey(key, text, modifiers)
    if (desksView.prompting && root.tab === 2) return desksView.handleKey(key, text, modifiers)
    if (key === Qt.Key_S && (modifiers & Qt.ControlModifier)) {
      root.save()
      return true
    }
    if (key === Qt.Key_Backtab || (key === Qt.Key_Tab && (modifiers & Qt.ShiftModifier))) {
      root.tab = (root.tab + root.tabs.length - 1) % root.tabs.length
      return true
    }
    if (key === Qt.Key_Tab) {
      root.tab = (root.tab + 1) % root.tabs.length
      return true
    }
    // Esc in the Layout tab's slot list goes back to its picture.
    if (key === Qt.Key_Escape && root.tab === 1 && layoutView.slotFocus) return layoutView.handleKey(key, text, modifiers)
    if (key === Qt.Key_Escape || text === "q") {
      root.dismiss()
      return true
    }
    if (root.tab === 0) return assignmentView.handleKey(key, text, modifiers)
    if (root.tab === 1) return layoutView.handleKey(key, text, modifiers)
    if (root.tab === 2) return desksView.handleKey(key, text, modifiers)
    return false
  }

  // Ctrl+S, one save for every view: the engine's `save`, said in the current
  // view; the Layout view applies its edited panes first.
  function save() {
    var view = [assignmentView, layoutView, desksView][root.tab]
    if (!root.engine) return
    var write = function() {
      root.engine.call("save", {}, function(reply) {
        if (reply.ok) view.say("Saved.", false)
        else view.say(reply.error, true)
      })
    }
    if (root.tab === 1) layoutView.applyThen(write)
    else write()
  }

  // A key by name ("a", "Tab", "Escape", "Down", ...), or with "Ctrl+" before
  // it ("Ctrl+s"), as if pressed: for `omarchy-shell shell call
  // milan.hyprslots press <key>` and the e2e smoke.
  function press(name) {
    var named = {
      Tab: Qt.Key_Tab, Backtab: Qt.Key_Backtab, Escape: Qt.Key_Escape, Return: Qt.Key_Return,
      Up: Qt.Key_Up, Down: Qt.Key_Down, Left: Qt.Key_Left, Right: Qt.Key_Right,
      BackSpace: Qt.Key_Backspace, Backspace: Qt.Key_Backspace, Delete: Qt.Key_Delete, Home: Qt.Key_Home, End: Qt.Key_End,
    }
    var s = String(name)
    var modifiers = 0
    if (s.length > 5 && s.slice(0, 5) === "Ctrl+") {
      modifiers = Qt.ControlModifier
      s = s.slice(5)
    }
    var key = named[s]
    var text = ""
    if (key === undefined) {
      if (s.length !== 1) return "unknown key " + name
      text = modifiers ? "" : s // Ctrl+<letter> types a control character, which nothing reads
      key = s.toUpperCase().charCodeAt(0) // Qt.Key_A..Key_Z and Key_0..Key_9 are their ASCII codes
    }
    return root.handleKey(key, text, modifiers) ? "ok" : "ignored"
  }

  // What the Assignment view has selected, "<status> <slot> <class>" (the
  // Layout view: "<screen> <leaf>"; Layouts: "desk:solo"), and
  // the current view's message or prompt line: for scripts and the e2e smoke.
  function selectionText() {
    if (root.tab === 1) return layoutView.selectionText()
    if (root.tab === 2) return desksView.selectedRow ? desksView.selectedRow.key : ""
    var row = assignmentView.selectedRow
    return row ? row.status + " " + (row.slot || "-") + " " + (row.cls || row.spec || "-") : ""
  }

  // The Assignment view's page label ("Workspace 3"): for the e2e smoke.
  function assignmentPageText() {
    return assignmentView.currentPage ? assignmentView.currentPage.label : ""
  }

  // The Assignment view's rows, "<slot>|<app>|<title>" joined by "; ", and
  // the line under its header: for the e2e smoke.
  function assignmentRowsText() {
    return assignmentView.rows.map(function(row) {
      var kept = row.kind !== "window"
      return Assignment.slotText(row) + "|" + (kept ? Assignment.specText(row) : row.cls) + "|"
        + (kept ? Assignment.titleText(row) : "window")
    }).join("; ")
  }

  // The Layout view's draft trees, "1: h[a, b]; 2: c" (edited ones marked
  // *): for the e2e smoke.
  function layoutText() {
    return layoutView.draftText()
  }

  // The Layout view's pane titles ("Screen 1 · HEADLESS-2 (...)" joined by
  // " | ") and its header line: for the e2e smoke.
  function layoutPanesText() {
    return layoutView.paneTitles()
  }

  function layoutHeaderText() {
    return layoutView.headerLine()
  }

  // The Layout view's workspace strip, "[All workspaces] · 1 2 3• ...".
  function layoutStripText() {
    return layoutView.stripText()
  }

  // The Layout tab's warning on a layout other desks share.
  function layoutSharedNote() {
    return DesksLayouts.sharedNote(layoutView.sharedWith)
  }

  // The Desk tab's column titles over the desks, " | " between them.
  function deskColumnsText() {
    var t = DesksLayouts.columnTitles("desk")
    return Object.keys(t).map(function(k) { return t[k] }).join(" | ")
  }

  // How many lines the help row takes (it should take one): for the e2e smoke.
  function helpLines() {
    return help.lineCount
  }

  // What each pane's tree is, "1: scroll · half".
  function layoutModeText() {
    return layoutView.modeText()
  }

  // A view's prompt as one line, the refusal after " | "; the view's
  // message when no prompt is open.
  function promptText(prompt, message) {
    if (!prompt) return message
    return Prompts.display(prompt) + (prompt.error ? " | " + prompt.error : "")
  }

  function messageText() {
    if (root.tab === 1) return root.promptText(layoutView.prompt, layoutView.message)
    if (root.tab === 2) return root.promptText(desksView.prompt, desksView.message)
    return root.promptText(assignmentView.prompt, assignmentView.message)
  }

  // The header line every tab shows: "Desk: docked · Layout: docked (also
  // used by: office)", and whether edits are unsaved.
  function headerText() {
    var s = root.engine ? root.engine.state : null
    return DesksLayouts.header(s) + (s && s.dirty ? "   ● unsaved edits (Ctrl+S)" : "")
  }

  // The message band (Messages.js): the current view's prompt, or its last
  // message until it fades (info, after Messages.HOLD_MS) or the next key
  // dismisses it (an error). A message is known by its view and its count
  // (the view's messageSeq), so the same text said again shows again.
  readonly property var views: [assignmentView, layoutView, desksView]
  readonly property var currentView: root.views[root.tab] || null
  readonly property string messageKey: root.currentView ? Messages.key(root.tab, root.currentView.messageSeq) : ""
  property string dismissedKey: ""
  readonly property string bandKind: root.currentView
    ? Messages.kind(root.currentView.prompting, root.currentView.message, root.currentView.messageIsError,
      root.messageKey === root.dismissedKey)
    : "none"

  function armBand() {
    var hold = Messages.holdMs(root.bandKind)
    if (hold > 0) {
      bandTimer.forKey = root.messageKey
      bandTimer.interval = hold
      bandTimer.restart()
    } else {
      bandTimer.stop()
    }
  }
  onMessageKeyChanged: Qt.callLater(root.armBand)
  onBandKindChanged: Qt.callLater(root.armBand)
  // A tab's old message is not news when it comes back into view.
  onTabChanged: {
    var view = root.views[root.tab]
    if (view) root.dismissedKey = Messages.key(root.tab, view.messageSeq)
  }

  Timer {
    id: bandTimer
    property string forKey: ""
    repeat: false
    onTriggered: if (root.messageKey === forKey) root.dismissedKey = forKey
  }

  // The current view's controls strip, as StyledText (its keys highlighted).
  readonly property string helpText: root.tab === 0 ? assignmentView.helpText
    : root.tab === 1 ? layoutView.helpText
    : desksView.helpText

  Connections {
    target: root.engine
    function onStateRead(ok) {
      if (ok) root.startPendingRecord()
    }
  }

  Loader {
    id: ownEngine
    active: !root.service
    sourceComponent: Component {
      Engine {
        panelOwned: true
      }
    }
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
      color: root.deskColor
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
        spacing: 0

        // The tab bar: folder tabs over the page. The current tab is the
        // page's own surface and opens into it (the page's top edge stops
        // under it); the others sit back on the recessed desk, dimmer and
        // apart. The active desk and its layout at the right, quietly.
        Item {
          id: tabBar
          z: 1 // over the page's top edge, which the current tab opens
          width: parent.width
          height: root.tabHeight
          Row {
            id: tabRow
            x: root.tabInset
            height: parent.height
            spacing: Style.spacing.xs
            Repeater {
              model: root.tabs
              delegate: Item {
                id: tabItem
                required property string modelData
                required property int index
                readonly property bool current: index === root.tab
                width: label.implicitWidth + Style.spacing.xl * 2
                height: parent.height
                Rectangle {
                  id: tabFace
                  y: tabItem.current ? 0 : Style.spacing.xs
                  width: parent.width
                  // the current one reaches over the page's top edge
                  height: parent.height - y + (tabItem.current ? root.hairline : 0)
                  topLeftRadius: root.tabRadius
                  topRightRadius: root.tabRadius
                  bottomLeftRadius: 0
                  bottomRightRadius: 0
                  color: tabItem.current ? root.background : root.tabRecessed
                  border.color: tabItem.current ? root.frameBorder : root.tabRecessedBorder
                  border.width: root.hairline
                }
                // The current tab's bottom: the page's surface, so the two
                // are one shape.
                Rectangle {
                  visible: tabItem.current
                  x: root.hairline
                  y: parent.height
                  width: parent.width - root.hairline * 2
                  height: root.hairline
                  color: root.background
                }
                Text {
                  id: label
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: tabFace.verticalCenter
                  anchors.verticalCenterOffset: tabItem.current ? 0 : -root.hairline
                  textFormat: Text.PlainText
                  text: tabItem.modelData
                  color: tabItem.current ? root.foreground : Commons.Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: tabItem.current
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.tab = tabItem.index
                }
              }
            }
          }
          // "Desk: solo · Layout: solo (also used by: beamer)", muted; the
          // unsaved mark after it in the urgent colour.
          Row {
            id: deskHeader
            anchors.right: parent.right
            anchors.rightMargin: root.tabInset
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Style.spacing.xs / 2
            spacing: Style.spacing.lg
            Text {
              width: Math.min(implicitWidth, tabBar.width - tabRow.x - tabRow.width - Style.spacing.lg * 3
                - (dirtyMark.visible ? dirtyMark.implicitWidth + parent.spacing : 0))
              elide: Text.ElideRight
              textFormat: Text.PlainText
              text: DesksLayouts.header(root.engine ? root.engine.state : null)
              color: Commons.Color.muted
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              id: dirtyMark
              visible: !!(root.engine && root.engine.state && root.engine.state.dirty)
              textFormat: Text.PlainText
              text: "● unsaved (Ctrl+S)"
              color: Commons.Color.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // The page: the current view, and the message band at its foot.
        Rectangle {
          id: page
          width: parent.width
          height: parent.height - tabBar.height - helpArea.height
          color: root.background
          border.color: root.frameBorder
          border.width: root.hairline
          radius: root.tabRadius

          Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.pagePadding
            anchors.bottomMargin: root.pagePadding + band.height + Style.spacing.md

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

            DesksLayoutsView {
              id: desksView
              anchors.fill: parent
              visible: root.tab === 2
              engine: root.engine
              foreground: root.foreground
              selectedBackground: root.selectedBackground
              selectedText: root.selectedText
              fontFamily: root.fontFamily
            }
          }

          // The prompt being answered, or the last call's outcome: a band of
          // its own over the page's foot, its space kept whether or not it
          // shows (a long line grows it upwards, over the view).
          MessageBand {
            id: band
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: root.pagePadding
            kind: root.bandKind
            message: root.currentView ? root.currentView.message : ""
            prompt: root.currentView ? root.currentView.prompt : null
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
          }
        }

        // The controls strip, under the page's bottom edge on the desk: what
        // the keys of the current view do, each trigger key in the accent
        // colour.
        Item {
          id: helpArea
          width: parent.width
          height: help.implicitHeight + Style.spacing.lg + Style.spacing.xs
          Text {
            id: help
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.pagePadding
            anchors.rightMargin: root.pagePadding
            anchors.bottom: parent.bottom
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            lineHeight: 1.15
            text: root.helpText
            color: Commons.Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
