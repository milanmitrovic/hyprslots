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
import "Layout.js" as Layout
import "Assignment.js" as Assignment
import "Messages.js" as Messages
import "Help.js" as Help
import "Guide.js" as Guide
import "ui"

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
// Everything the keys do the mouse does too, through the same handler: the
// help row is a toolbar whose buttons feed their keys (press), a prompt's
// chips and answers are keys, a double-click on a row is its view's
// primary action's key; the tabs and the workspace switchers are clicked.
// The Assignment view's rows also drag: onto a slot (a), onto the other
// windows (u).
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
  // (and the current tab, one shape with it) the menu surface on it, with
  // no outline; the other tabs, a dimmer surface, and the controls strip
  // sit back on the desk. Corners are the theme's (Style.cornerRadius,
  // Hyprland's rounding): square when it is 0.
  readonly property color deskColor: root.recess(root.background, 1)
  readonly property color tabRecessed: root.recess(root.background, 0.5)
  readonly property int tabRadius: Style.cornerRadius
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
  // The tab it opens on is Guide.openingTab's: the Layout tab while there
  // are no slots, else Assignment; one the payload asks for wins. Chosen
  // again on the first state read after opening (the state it had may be
  // older), unless a tab was picked meanwhile.
  property bool pendingTab: false

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
    var opening = Guide.openingTab(root.engine ? root.engine.state : null, payload)
    root.tab = opening !== null ? opening : 0 // nothing read yet: Assignment, which says why
    root.pendingTab = !Guide.asksForTab(payload)
    if (payload.record === true) {
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

  // The first state read after opening settles the opening tab.
  function settleTab() {
    if (!root.pendingTab || !root.opened || !root.engine || root.engine.state === null) return
    root.pendingTab = false
    var opening = Guide.openingTab(root.engine.state, {})
    if (opening !== null) root.tab = opening
  }

  // A tab picked by key or click: the opening tab is settled.
  function pickTab(index) {
    root.pendingTab = false
    root.tab = index
  }

  function close() {
    root.opened = false
    root.pendingRecord = false
    root.pendingTab = false
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
    // a prompt, or a row or a screen held in a drag (Esc cancels it), owns the keyboard
    if ((assignmentView.prompting || assignmentView.dragging) && root.tab === 0) return assignmentView.handleKey(key, text, modifiers)
    if ((layoutView.prompting || layoutView.screenDragging) && root.tab === 1) return layoutView.handleKey(key, text, modifiers)
    if (desksView.prompting && root.tab === 2) return desksView.handleKey(key, text, modifiers)
    if (key === Qt.Key_S && (modifiers & Qt.ControlModifier)) {
      root.save()
      return true
    }
    if (key === Qt.Key_Backtab || (key === Qt.Key_Tab && (modifiers & Qt.ShiftModifier))) {
      root.pickTab((root.tab + root.tabs.length - 1) % root.tabs.length)
      return true
    }
    if (key === Qt.Key_Tab) {
      root.pickTab((root.tab + 1) % root.tabs.length)
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

  // A row being dragged in the Assignment view: "<class> -> <what letting
  // go does there>" ("t-stray -> Assign to main", "t-main -> Unassign",
  // "t-main -> none"), "" when none is: for the e2e smoke.
  function assignmentDragText() {
    var d = assignmentView.drag
    if (!d) return ""
    return (d.source.cls || "Unknown") + " -> " + (d.action.kind === "none" ? "none" : d.action.label)
  }

  // What stands in the current tab while there is nothing in it yet
  // (Guide.js), " | " between its parts, the action last as "[key] label";
  // "" when nothing does: for the e2e smoke.
  function emptyText() {
    var e = root.tab === 1 ? layoutView.welcome : root.tab === 0 ? assignmentView.empty : null
    if (!e) return ""
    var parts = e.title ? [e.title].concat(e.lines) : [e.text]
    return parts.concat(["[" + e.action.key + "] " + e.action.label]).join(" | ")
  }

  function deskIntroText() {
    return Guide.deskIntro()
  }

  // The current tab's line on what to do next (Guide.js), "" for none.
  function hintText() {
    if (root.tab === 1) return layoutView.nextHint
    if (root.tab === 0) return assignmentView.hint
    return ""
  }

  // The Layout view's draft trees, "1: h[a, b]; 2: c" (edited ones marked
  // *): for the e2e smoke.
  function layoutText() {
    return layoutView.draftText()
  }

  // A divider being dragged in the Layout view: "<screen> <tree as it
  // would be let go> | <its split's ratio>", "" when none is: for the e2e
  // smoke.
  function layoutDragText() {
    var d = layoutView.dragging
    return d ? d.screen + " " + Layout.format(d.node) + " | " + d.label : ""
  }

  // A screen's pane being dragged by its title in the Layout view: "1 ->
  // Swap with screen 2", "1 -> none" where letting go does nothing, "" for
  // none: for the e2e smoke.
  function layoutScreenDragText() {
    var d = layoutView.screenDrag
    return d ? d.from + " -> " + (d.action.kind === "none" ? "none" : d.action.label) : ""
  }

  // The Layout view's pane titles ("Screen 1 · Built-in" joined by
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

  // The Desk tab's desks, "<name>: <monitors cell>" joined by "; ": for
  // the e2e smoke.
  function deskMonitorsText() {
    return desksView.rows.filter(function(row) { return row.kind === "desk" }).map(function(row) {
      return row.name + ": " + DesksLayouts.deskCells(row).monitors
    }).join("; ")
  }

  // The Desk tab's desk maps as drawn (DesksLayouts.deskMap at the map's
  // size), "<desk>: <n> solid|outlined <x>,<y> <w>x<h>, ..." joined by "; ",
  // the active desk's name starred: for the e2e smoke.
  function deskMapsText() {
    return desksView.rows.filter(function(row) { return row.kind === "desk" }).map(function(row) {
      var map = DesksLayouts.deskMap(row, Tokens.deskMapWidth, Tokens.deskMapHeight)
      return row.name + (row.active ? "*" : "") + ": " + map.screens.map(function(s) {
        return s.screen + " " + (s.connected ? "solid" : "outlined") + " " + s.x + "," + s.y + " " + s.w + "x" + s.h
      }).join(", ")
    }).join("; ")
  }

  // How many lines the help row takes (it should take one): for the e2e smoke.
  function helpLines() {
    return root.currentView && root.currentView.prompting ? help.lineCount : toolbar.lineCount()
  }

  // A click on option `index` of the current view's choice prompt: the keys
  // that pick it (Prompts.pickPresses), fed as if pressed.
  function pickOption(index) {
    var presses = Prompts.pickPresses(root.currentView ? root.currentView.prompt : null, index)
    for (var i = 0; i < presses.length; i++) root.press(presses[i])
  }

  // Where to click the control named `name` (its objectName: "toolbar:a",
  // "chip:m", "prompt:yes", "tab:Layout", "row:2", "slot:main",
  // "workspace:3", "tile:1:main"), as "<x> <y>" on the screen, its centre;
  // "" when none shows. For the e2e smoke, which clicks there with a real
  // pointer.
  function clickPoint(name) {
    var found = root.findShown(window.contentItem, String(name))
    if (!found) return ""
    var p = found.mapToItem(null, found.width / 2, found.height / 2)
    var screen = window.screen
    return Math.round(p.x + (screen ? screen.x : 0)) + " " + Math.round(p.y + (screen ? screen.y : 0))
  }

  // Where the control named `name` shows, "<x> <y> <width> <height>" on
  // the screen; "" when none shows. For the e2e smoke, which drags the
  // Layout picture's dividers to a point measured from the tiles.
  function clickBounds(name) {
    var found = root.findShown(window.contentItem, String(name))
    if (!found) return ""
    var p = found.mapToItem(null, 0, 0)
    var screen = window.screen
    return Math.round(p.x + (screen ? screen.x : 0)) + " " + Math.round(p.y + (screen ? screen.y : 0)) + " "
      + Math.round(found.width) + " " + Math.round(found.height)
  }

  function findShown(item, name) {
    if (!item || !item.visible) return null
    if (item.objectName === name && item.width > 0 && item.height > 0) return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) {
      var hit = root.findShown(kids[i], name)
      if (hit) return hit
    }
    // a ListView's rows sit in its contentItem
    if (item.contentItem && item.contentItem !== item && kids.indexOf(item.contentItem) < 0) {
      return root.findShown(item.contentItem, name)
    }
    return null
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
      if (!ok) return
      root.settleTab()
      root.startPendingRecord()
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

        // The tab bar: folder tabs over the page, no outlines. The current
        // tab is the page's own surface flowing into it; the others sit
        // back on the recessed desk, a dimmer surface, a little lower. The
        // active desk and its layout at the right, quietly.
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
                  // down to the page's top edge: the current one is one
                  // surface with the page
                  height: parent.height - y
                  topLeftRadius: root.tabRadius
                  topRightRadius: root.tabRadius
                  bottomLeftRadius: 0
                  bottomRightRadius: 0
                  color: tabItem.current ? root.background : root.tabRecessed
                }
                Text {
                  id: label
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.verticalCenter: tabFace.verticalCenter
                  textFormat: Text.PlainText
                  text: tabItem.modelData
                  color: tabItem.current ? root.foreground : Commons.Color.muted
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: tabItem.current
                }
                MouseArea {
                  objectName: "tab:" + tabItem.modelData
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.pickTab(tabItem.index)
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
            InfoText {
              width: Math.min(implicitWidth, tabBar.width - tabRow.x - tabRow.width - Style.spacing.lg * 3
                - (dirtyMark.visible ? dirtyMark.implicitWidth + parent.spacing : 0))
              elide: Text.ElideRight
              text: DesksLayouts.header(root.engine ? root.engine.state : null)
            }
            InfoText {
              id: dirtyMark
              visible: !!(root.engine && root.engine.state && root.engine.state.dirty)
              urgent: true
              text: "● unsaved (Ctrl+S)"
            }
          }
        }

        // The page: the current view, and the message band at its foot.
        Rectangle {
          id: page
          width: parent.width
          height: parent.height - tabBar.height - helpArea.height
          color: root.background
          radius: Style.cornerRadius

          Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.pagePadding
            anchors.bottomMargin: root.pagePadding + band.height + Style.spacing.md

            AssignmentView {
              id: assignmentView
              anchors.fill: parent
              visible: root.tab === 0
              onPressKey: function(name) { root.press(name) }
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
              onPressKey: function(name) { root.press(name) }
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
              onPressKey: function(name) { root.press(name) }
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
            onPress: function(name) { root.press(name) }
            onChoose: function(index) { root.pickOption(index) }
          }
        }

        // The controls strip, under the page's bottom edge on the desk: a
        // toolbar of what the current view's keys do (Help.buttons), each
        // button its label with the trigger key in the accent colour, a
        // click feeding the key (press); while a prompt is open, its keys
        // as plain text (its controls are in the message band).
        Item {
          id: helpArea
          readonly property bool prompting: !!(root.currentView && root.currentView.prompting)
          width: parent.width
          height: (prompting ? help.implicitHeight : toolbar.implicitHeight) + Style.spacing.lg + Style.spacing.xs
          Text {
            id: help
            visible: helpArea.prompting
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.pagePadding
            anchors.rightMargin: root.pagePadding
            anchors.bottom: parent.bottom
            textFormat: Text.StyledText
            wrapMode: Text.WordWrap
            lineHeight: 1.15
            text: helpArea.prompting ? root.helpText : ""
            color: Commons.Util.alpha(root.foreground, 0.7)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Toolbar {
            id: toolbar
            visible: !helpArea.prompting
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: root.pagePadding - Style.spacing.md
            anchors.rightMargin: root.pagePadding
            anchors.bottom: parent.bottom
            anchors.bottomMargin: -Style.spacing.xxs
            cells: root.currentView ? Help.buttons(root.currentView.helpGroups, String(Commons.Color.accent)) : []
            onPressed: function(key) { root.press(key) }
          }
        }
      }
    }
  }
}
