pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Assignment.js" as Assignment
import "Workspaces.js" as Workspaces
import "Prompts.js" as Prompts
import "Help.js" as Help
import "Guide.js" as Guide
import "Launch.js" as Launch
import "Layout.js" as Layout
import "ui"

// Which live window fills which slot (aerolayout's AssignmentView). A table
// of the windows on a workspace with the screen, slot, app and title of each,
// plus a "Missing" row for every slot whose window is not running (a slot
// the workspace has no spec for and no window in is an empty row); every
// global slot is a row (every tree has every slot); then
// the windows overflowing on the workspace and any others on it, on any
// screen. ←/→ (or [ ]) page through workspaces 1 to N (the managed ones), the
// digits jump to a workspace's page (0 is workspace 10); ↑/↓ select. `a` puts
// the selected window into one of the global slots on the workspace (one key
// per slot, as the TUI prompts) and makes the window's spec the workspace's
// for that slot, as aerolayout's `a` did; `u` takes a window out of its slot
// and clears the workspace's spec for it (the slot is left empty, not
// Missing), and on a Missing row (a spec whose window is not open) clears
// that spec. Spec edits stay in memory until Ctrl+S (the header says
// "unsaved edits"). The model is Assignment.js; the calls are the api's
// take_spec, clear_spec and unassign (docs/design.md §9).
//
// By mouse: a click selects a row, a double-click is a; a row with a window
// drags (past Assignment.DRAG_THRESHOLD px): let go on a slot row it is a
// with that slot (assign, the same handler), on the other windows or the
// list's empty space below them u (unassign, without its question: the drop
// is the answer), anywhere else, or on Esc, nothing (Assignment.dropAction).
// Each slot row leads with a mini-map of its screen's tree, the slot lit
// (ui/MiniMap).
//
// c captures the page's workspace (the Layout tab's capture flow, there).
// Under the header, quietly, the page's launch setting (Launch.js): m
// cycles it (never, on demand, at login; api set_launch), L launches the
// apps its empty slots wait for (api launch_missing); while it is not
// never, a Launch column says what each slot's app launches with, or why it
// can't.
Item {
  id: root

  property var engine: null
  property int focusedWorkspace: -1

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null
  readonly property var pageList: Assignment.pages(state)
  property int page: 0
  readonly property var currentPage: pageList[Math.min(page, pageList.length - 1)]
  readonly property var rows: Assignment.rows(state, currentPage.workspace)
  // The selection follows the row (by window address, or a missing slot's
  // name) through every re-read, not the index.
  property string selectedKey: ""
  readonly property int selected: indexOfKey(selectedKey)
  readonly property var selectedRow: selected >= 0 && selected < rows.length ? rows[selected] : null

  // The prompt in progress (Prompts.js's, as in the other views) and what
  // to do with its answer.
  property var prompt: null
  property var _answer: null
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false
  // Counts say(): the panel's message band knows a message by it.
  property int messageSeq: 0

  // A row being dragged: { source (the row, as it was when the drag
  // began), key (keyOf it), x, y (the pointer, in the view), lx, ly (the
  // pointer, in the list's box), target (dropTargetAt), action
  // (Assignment.dropAction: what letting go does) }, null when none is.
  property var drag: null
  readonly property bool dragging: drag !== null

  // Zero slots: the Layout tab comes first (Guide.assignmentEmpty, its
  // button the Tab key); a workspace with nothing assigned says how
  // (Guide.assignmentHint).
  readonly property var empty: Guide.assignmentEmpty(state)
  readonly property string hint: Guide.assignmentHint(state, rows, currentPage.workspace)

  readonly property bool showScreen: {
    var seen = {}
    var count = 0
    for (var i = 0; i < rows.length; i++) {
      var screen = String(rows[i].screen || "")
      if (!seen[screen]) {
        seen[screen] = true
        count++
      }
    }
    return count > 1
  }

  // The controls strip: its groups (Help.js; the panel draws them as a
  // toolbar, what the view would refuse now dimmed) and the same as
  // StyledText (each trigger key highlighted).
  readonly property string accent: String(Commons.Color.accent)
  readonly property int pageWorkspace: currentPage ? currentPage.workspace : 0
  readonly property bool captures: !!state && !state.config_error && Layout.editBlock(state, state.layout || "") === ""
  readonly property var helpGroups: Assignment.helpGroups(state, selectedRow, Workspaces.jumpKeys(Workspaces.count(state)),
    { capture: captures, launch: Launch.helpItems(state, pageWorkspace) })
  // The page's launch setting, and whether its slots show their commands.
  readonly property string launchLine: state ? Launch.line(state, pageWorkspace) : ""
  readonly property bool showLaunch: !!state && Launch.shows(state, pageWorkspace)
  readonly property string helpText: prompting ? Help.escape(Prompts.help(prompt)) : Help.row(helpGroups, accent)

  // A key by name, for the panel to feed as if pressed (Panel.press): a
  // double-click on a row runs the view's primary action, a.
  signal pressKey(string name)
  // c: capture workspace n, in the Layout tab (the panel switches to it).
  signal captureWorkspace(int n)

  function keyOf(row) {
    if (!row) return ""
    return row.address ? row.address : "missing:" + row.workspace + "/" + row.slot
  }

  function indexOfKey(key) {
    for (var i = 0; i < rows.length; i++) if (keyOf(rows[i]) === key) return i
    return rows.length > 0 ? 0 : -1
  }

  function select(index) {
    if (rows.length === 0) return
    var i = Math.max(0, Math.min(rows.length - 1, index))
    selectedKey = keyOf(rows[i])
    list.positionViewAtIndex(i, ListView.Contain)
  }

  function turnPage(delta) {
    var n = pageList.length
    page = ((page + delta) % n + n) % n
    selectedKey = ""
    select(0)
  }

  // A digit: workspace n's page.
  function goWorkspace(n) {
    var i = Assignment.pageOfWorkspace(state, n)
    if (i < 0) return
    page = i
    selectedKey = ""
    select(0)
    message = ""
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
    messageSeq++
  }

  // Back to the opening page: the focused workspace's, else workspace 1's.
  function reset() {
    prompt = null
    _answer = null
    message = ""
    page = Assignment.initialPage(state, focusedWorkspace)
    selectedKey = ""
  }

  // Open on the focused workspace once the first state arrives.
  property bool _placed: false
  onStateChanged: {
    if (!_placed && state) {
      _placed = true
      page = Assignment.initialPage(state, focusedWorkspace)
    }
  }

  function startAssign() {
    var row = selectedRow
    if (!row) return
    if (row.kind !== "window") {
      say("No window in " + row.slot + ": select a window, then a puts it there.", true)
      return
    }
    var workspace = currentPage.workspace
    var options = Assignment.slotOptions(state, workspace)
    if (options.length === 0) {
      say("There are no slots yet: make them in the Layout tab's slot list (s, then a).", true)
      return
    }
    ask(Prompts.choice(Assignment.assignTitle(workspace, row.cls), Assignment.promptOptions(options)), function(option) {
      root.assign(row, option)
    })
  }

  // Open a prompt; answer(value) runs on its answer.
  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  // The window takes the slot, and its spec becomes the workspace's for it.
  function assign(row, option) {
    if (!engine) return
    say("Assigning " + row.cls + " to " + option.slot + "…", false)
    engine.call("take_spec", { address: row.address, workspace: option.workspace, slot: option.slot }, function(reply) {
      if (!reply.ok) {
        say(reply.error, true)
        return
      }
      say(Assignment.assignedText(state, row.cls, reply), false)
      selectedKey = row.address
    })
  }

  // u: the window out of its slot, and (Assignment.unassignPlan) the
  // workspace's spec for the slot with it, so the slot is left empty; on a
  // Missing row, only the spec.
  function startUnassign() {
    var row = selectedRow
    var plan = Assignment.unassignPlan(state, row)
    if (plan.error) {
      if (row) say(plan.error, true)
      return
    }
    ask(Prompts.confirm(plan.question), function(yes) {
      if (!yes) root.message = ""
      else if (plan.clear) root.clearSpec(plan.clear)
      else root.unassign(row, plan)
    })
  }

  // m: the page's launch setting, the next of never, on demand, at login.
  function cycleLaunch() {
    if (!engine || !state) return
    var n = pageWorkspace
    if (Launch.readOnly(state, n)) {
      say("Workspace " + n + "'s launch setting is set in your config: change it there.", true)
      return
    }
    engine.call("set_launch", { workspace: n, mode: Launch.next(Launch.mode(state, n)) }, function(reply) {
      if (!reply.ok) root.say(reply.error, true)
      else root.say(Launch.setText(reply), false)
    })
  }

  // L: launch the apps the page's empty slots wait for.
  function launchMissing() {
    if (!engine || !state) return
    var n = pageWorkspace
    if (!Launch.canLaunch(state, n)) {
      say("Workspace " + n + " launches no apps: press m to launch them on demand or at login.", true)
      return
    }
    say("Launching the missing apps of workspace " + n + "…", false)
    engine.call("launch_missing", { workspace: n }, function(reply) {
      if (!reply.ok) {
        root.say(reply.error, true)
        return
      }
      var said = Launch.missingText(reply)
      root.say(said.text, said.error)
    })
  }

  // The launch line and each slot row's status, for the e2e smoke.
  function launchText() {
    if (!state) return ""
    var cells = []
    if (showLaunch) {
      for (var i = 0; i < rows.length; i++) {
        if (!Assignment.isSlotRow(rows[i])) continue
        var st = Launch.status(state, pageWorkspace, rows[i].slot)
        if (st) cells.push(rows[i].slot + ": " + (st.urgent ? "! " : "") + st.text)
      }
    }
    return launchLine + (cells.length ? " | " + cells.join("; ") : "")
  }

  function clearSpec(target) {
    if (!engine) return
    engine.call("clear_spec", { workspace: target.workspace, slot: target.slot }, function(reply) {
      if (!reply.ok) root.say(reply.error, true)
      else root.say("Unassigned " + reply.spec + " from " + reply.slot + " on workspace " + reply.workspace
        + ": the slot is empty. Ctrl+S saves.", false)
    })
  }

  function unassign(row, plan) {
    if (!engine) return
    engine.call("unassign", { address: plan.address, clear_spec: plan.clearSpec }, function(reply) {
      if (!reply.ok) say(reply.error, true)
      else if (reply.spec) {
        say("Unassigned " + row.cls + " from " + reply.slot + " on workspace " + reply.workspace
          + ": the slot is empty. Ctrl+S saves.", false)
      } else {
        say(reply.slot ? "Unassigned " + row.cls + " from " + reply.slot + "." : "Unassigned " + row.cls + ".", false)
      }
    })
  }

  // --- drag and drop ---------------------------------------------------------

  // What is under the pointer at lx, ly in the list's box: { row, index }
  // (a row), { others: true } (the list's empty space below its rows) or
  // null (outside the list).
  function dropTargetAt(lx, ly) {
    if (lx < 0 || ly < 0 || lx >= listBox.width || ly >= listBox.height) return null
    var i = list.indexAt(lx + list.contentX, ly + list.contentY)
    if (i >= 0 && i < rows.length) return { row: rows[i], index: i }
    return { others: true }
  }

  // The first row of the other windows (overflowing, or in no slot): where
  // the unassign target's outline starts; rows.length when there is none.
  readonly property int firstOtherIndex: {
    for (var i = 0; i < rows.length; i++) if (!Assignment.isSlotRow(rows[i])) return i
    return rows.length
  }

  // A press on row `index` moved past the threshold: the drag begins
  // (false when that row does not drag, or a prompt is open).
  function dragStart(index, x, y, lx, ly) {
    if (prompting || index < 0 || index >= rows.length || !Assignment.canDrag(rows[index])) return false
    var source = rows[index]
    selectedKey = keyOf(source)
    message = ""
    drag = { source: source, key: keyOf(source), x: x, y: y, lx: lx, ly: ly, target: null, action: { kind: "none" } }
    dragTo(x, y, lx, ly)
    return true
  }

  // The source row as it is now (rows are re-read under the drag), null
  // when its window has gone.
  function dragSource() {
    if (!drag) return null
    for (var i = 0; i < rows.length; i++) if (keyOf(rows[i]) === drag.key) return rows[i]
    return null
  }

  function dragTo(x, y, lx, ly) {
    if (!drag) return
    var source = dragSource() || drag.source
    var target = dropTargetAt(lx, ly)
    drag = { source: source, key: drag.key, x: x, y: y, lx: lx, ly: ly, target: target,
      action: Assignment.dropAction(state, currentPage.workspace, source, target) }
  }

  // The rows changed under a held drag: what it would land on, again.
  function dragRetarget() {
    if (drag) dragTo(drag.x, drag.y, drag.lx, drag.ly)
  }
  onRowsChanged: Qt.callLater(dragRetarget)

  // Let go: what dropAction says, through a's and u's own handlers.
  function dragDrop() {
    if (!drag) return
    var source = dragSource()
    var target = dropTargetAt(drag.lx, drag.ly)
    drag = null
    if (!source) return
    var action = Assignment.dropAction(state, currentPage.workspace, source, target)
    selectedKey = keyOf(source)
    if (action.kind === "assign") assign(source, action.option)
    else if (action.kind === "unassign") unassign(source, action.plan)
  }

  function dragCancel() {
    drag = null
  }

  function handlePrompt(key, text, modifiers) {
    var out = Prompts.key(prompt, Prompts.keyName(key, modifiers, Qt), Prompts.typed(text))
    var answer = _answer
    prompt = out.prompt
    if (!out.result) return true
    _answer = null
    if (out.result.cancel) say("Cancelled.", false)
    else if (answer) answer(out.result.value)
    return true // the prompt owns the keyboard
  }

  function handleKey(key, text, modifiers) {
    // a held drag owns the keyboard: Esc cancels it, the rest waits
    if (dragging) {
      if (key === Qt.Key_Escape) dragCancel()
      return true
    }
    if (prompting) return handlePrompt(key, text, modifiers)
    if (key === Qt.Key_Up || text === "k") select(selected - 1)
    else if (key === Qt.Key_Down || text === "j") select(selected + 1)
    else if (key === Qt.Key_Left || text === "h" || text === "p" || text === "[") turnPage(-1)
    else if (key === Qt.Key_Right || text === "l" || text === "]") turnPage(1)
    else if (Workspaces.ofDigit(text, Workspaces.count(state)) !== null) goWorkspace(Workspaces.ofDigit(text, Workspaces.count(state)))
    else if (text === "a") startAssign()
    else if (text === "u") startUnassign()
    else if (text === "c") {
      if (captures) captureWorkspace(pageWorkspace)
      else say("Capture needs a layout the editor may change: see the Layout tab.", true)
    }
    else if (text === "m") cycleLaunch()
    else if (text === "L") launchMissing()
    else return false
    return true
  }

  // Columns: the selection's stripe, the mini-map, then [Screen] Slot App
  // Title, sized by share of the width.
  readonly property real miniMapColumn: Tokens.miniMapWidth + Tokens.cellPadding
  readonly property real screenWidth: showScreen ? width * 0.1 : 0
  readonly property real slotWidth: width * (showLaunch ? 0.16 : 0.18)
  readonly property real appWidth: width * (showLaunch ? 0.16 : 0.18)
  readonly property real launchWidth: showLaunch ? width * 0.26 : 0
  readonly property real titleWidth: width - Tokens.stripeWidth - miniMapColumn - screenWidth - slotWidth - appWidth - launchWidth

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: the workspace switcher (the Layout tab's, without All
    // workspaces), the page's workspace lit.
    WorkspaceSwitcher {
      id: headerBox
      x: Tokens.textInset
      entries: Workspaces.numbers(root.state, root.currentPage.workspace)
      onPicked: function(workspace) { root.goWorkspace(workspace) }
    }

    // Why the editor cannot see the engine, or why the engine is off.
    ProblemText {
      id: problem
      width: parent.width
      text: {
        if (!root.engine) return "No engine service."
        if (root.engine.error !== "") return root.engine.error
        var s = root.state
        if (s && s.refused) return "hyprslots is off: " + s.refused
        if (s && s.config_error) return "config error: " + s.config_error
        return ""
      }
    }

    // The page's launch setting, quietly (m cycles it, L launches).
    InfoText {
      id: launchNote
      objectName: "launch:line"
      width: parent.width
      leftPadding: Tokens.textInset
      visible: root.launchLine !== "" && !root.empty
      elide: Text.ElideRight
      text: root.launchLine
    }

    // What to do next on a workspace with nothing assigned.
    InfoText {
      id: hintLine
      width: parent.width
      leftPadding: Tokens.textInset
      visible: root.hint !== "" && !root.empty
      elide: Text.ElideRight
      text: root.hint
    }

    // Column titles.
    TableHeader {
      id: titles
      visible: !root.empty
      width: parent.width
      columns: [
        { text: "", width: Tokens.stripeWidth },
        { text: "", width: root.miniMapColumn },
        { text: "Screen", width: root.screenWidth },
        { text: "Slot", width: root.slotWidth },
        { text: "App", width: root.appWidth },
        { text: "Title", width: root.titleWidth },
        { text: "Launch", width: root.launchWidth },
      ]
    }

    // The table's rows, and over them the one MouseArea that clicks,
    // double-clicks and drags them (rowMouse: it outlives the rows, which
    // every state read makes anew).
    Item {
      id: listBox
      objectName: "assignment:list"
      width: parent.width
      height: parent.height - headerBox.height - (titles.visible ? titles.height + parent.spacing : 0)
        - (problem.visible ? problem.height + parent.spacing : 0)
        - (hintLine.visible ? hintLine.height + parent.spacing : 0)
        - (launchNote.visible ? launchNote.height + parent.spacing : 0) - parent.spacing

      ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: root.selected

        delegate: TableRow {
          id: rowItem
          required property var modelData
          required property int index
          readonly property bool current: index === root.selected
          // no window in the slot: Missing (the workspace's spec waits for one) or
          // empty (nothing says what fills it)
          readonly property bool missing: modelData.kind === "missing" || modelData.kind === "empty"
          readonly property bool empty: modelData.kind === "empty"
          readonly property bool slotRow: Assignment.isSlotRow(modelData)
          readonly property color ink: current ? root.selectedText : root.foreground
          // the drag's: this row is dragged (dimmed), or where it would land
          readonly property bool dragged: !!root.drag && root.drag.key === root.keyOf(modelData)
          readonly property bool landing: !!root.drag && root.drag.action.kind === "assign"
            && !!root.drag.target && root.drag.target.index === index
          readonly property var miniMap: slotRow ? Assignment.miniMapSource(root.state, root.currentPage.workspace, modelData.slot) : null
          width: ListView.view.width
          height: Tokens.miniMapRowHeight
          objectName: "row:" + rowItem.index
          selected: current
          interactive: false // rowMouse has the pointer
          dropTarget: landing
          opacity: dragged ? Tokens.dim : 1

          Row {
            anchors.fill: parent
            // the slot's place on its screen; nothing for the other windows
            Item {
              width: root.miniMapColumn
              height: parent.height
              MiniMap {
                objectName: rowItem.miniMap ? "minimap:" + rowItem.modelData.slot : ""
                x: Tokens.cellPadding
                anchors.verticalCenter: parent.verticalCenter
                width: Tokens.miniMapWidth
                height: Tokens.miniMapHeight
                tree: rowItem.miniMap ? rowItem.miniMap.tree || "" : ""
                slot: rowItem.slotRow ? rowItem.modelData.slot : ""
                connector: rowItem.miniMap ? rowItem.miniMap.connector : ""
                targeted: rowItem.landing
              }
            }
            TableCell {
              width: root.screenWidth
              visible: root.showScreen
              text: Assignment.screenText(root.state, rowItem.modelData)
              color: rowItem.ink
              opacity: 0.7
            }
            TableCell {
              width: root.slotWidth
              text: Assignment.slotText(rowItem.modelData)
              color: rowItem.current ? root.selectedText
                : rowItem.modelData.status === "overflow" || rowItem.modelData.status === "unassigned" ? Commons.Color.urgent
                : Commons.Color.accent
              opacity: rowItem.empty ? Tokens.faint : rowItem.missing || rowItem.modelData.status === "none" ? Tokens.dim : 1
              font.bold: !rowItem.missing
            }
            TableCell {
              width: root.appWidth
              text: rowItem.missing ? Assignment.specText(rowItem.modelData) : (rowItem.modelData.cls || "Unknown")
              color: rowItem.ink
              opacity: rowItem.missing ? Tokens.dim : 1
              font.bold: rowItem.modelData.status === "slot" || rowItem.modelData.status === "manual"
            }
            TableCell {
              width: root.titleWidth
              rightPadding: Tokens.cellPadding
              text: Assignment.titleText(rowItem.modelData)
              color: rowItem.missing && !rowItem.empty && !rowItem.current ? Commons.Color.urgent : rowItem.ink
              opacity: rowItem.empty ? Tokens.faint : 1
              font.italic: rowItem.missing
            }
            // What the slot's app launches with (from your config, said so),
            // or why it can't, in the urgent colour; while the page launches.
            TableCell {
              readonly property var launch: root.showLaunch && rowItem.slotRow
                ? Launch.status(root.state, root.pageWorkspace, rowItem.modelData.slot) : null
              width: root.launchWidth
              visible: root.showLaunch
              rightPadding: Tokens.cellPadding
              text: launch ? launch.text : ""
              color: launch && launch.urgent && !rowItem.current ? Commons.Color.urgent : rowItem.ink
              opacity: launch && !launch.urgent ? 0.8 : 1
            }
          }
        }

        Placeholder {
          anchors.centerIn: parent
          width: parent.width
          visible: root.rows.length === 0 && !root.empty
          text: root.state ? "No windows" : (root.engine && root.engine.error === "" ? "Reading hyprslots…" : "")
        }

        // No slots yet: nothing can be assigned until the Layout tab makes one.
        Column {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.spacing.xxl * 2, Style.space(520))
          visible: !!root.empty
          spacing: Style.spacing.lg
          Placeholder {
            width: parent.width
            text: root.empty ? root.empty.text : ""
          }
          Item {
            width: parent.width
            height: layoutButton.height
            ActionButton {
              id: layoutButton
              objectName: root.empty ? "empty:layout" : ""
              anchors.horizontalCenter: parent.horizontalCenter
              accented: true
              keyText: root.empty ? root.empty.action.key : ""
              text: root.empty ? root.empty.action.label : ""
              pixelSize: Style.font.body
              padX: Style.spacing.xl
              padY: Style.spacing.sm
              onClicked: root.pressKey(root.empty.action.key)
            }
          }
        }
      }

      // Where letting go unassigns: the other windows and the empty space
      // below them, outlined while a dragged window in a slot is over it.
      Rectangle {
        id: othersZone
        objectName: "dropzone:others"
        readonly property real zoneTop: Math.max(0, root.firstOtherIndex * Tokens.miniMapRowHeight - list.contentY)
        visible: !!root.drag && root.drag.action.kind === "unassign" && zoneTop < listBox.height
        y: zoneTop
        width: listBox.width
        height: listBox.height - zoneTop
        radius: Tokens.radius
        color: Tokens.dropFill
        border.width: Tokens.dropLine
        border.color: Tokens.dropOutline
      }

      // The pointer on the rows: a click selects, a double-click is a, a
      // press on a window's row moved past the threshold drags it
      // (dragStart, dragTo, dragDrop; Esc cancels: handleKey).
      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true // a drag is the row's, not the list's flick
        enabled: !root.empty
        property int pressIndex: -1
        property real pressX: 0
        property real pressY: 0
        // this press made a drag (held, let go or cancelled): no click
        property bool dragMade: false
        property int hoverIndex: -1
        cursorShape: root.drag ? Qt.ClosedHandCursor
          : hoverIndex >= 0 && Assignment.canDrag(root.rows[hoverIndex]) ? Qt.OpenHandCursor : Qt.ArrowCursor

        function rowAt(mx, my) {
          var i = list.indexAt(mx + list.contentX, my + list.contentY)
          return i >= 0 && i < root.rows.length ? i : -1
        }
        function follow(mouse) {
          var p = mapToItem(root, mouse.x, mouse.y)
          root.dragTo(p.x, p.y, mouse.x, mouse.y)
        }

        onPressed: (mouse) => {
          pressIndex = rowAt(mouse.x, mouse.y)
          pressX = mouse.x
          pressY = mouse.y
          dragMade = false
        }
        onPositionChanged: (mouse) => {
          hoverIndex = rowAt(mouse.x, mouse.y)
          if (!pressed) return
          if (dragMade) {
            if (root.drag) follow(mouse)
            return
          }
          if (pressIndex < 0 || !Assignment.dragBegins(pressX, pressY, mouse.x, mouse.y)) return
          var p = mapToItem(root, mouse.x, mouse.y)
          dragMade = root.dragStart(pressIndex, p.x, p.y, mouse.x, mouse.y)
          if (!dragMade) pressIndex = -1 // no drag from this row: the press is a click
        }
        onReleased: (mouse) => {
          if (root.drag) {
            follow(mouse)
            root.dragDrop()
          }
        }
        onClicked: (mouse) => {
          if (dragMade) return
          var i = rowAt(mouse.x, mouse.y)
          if (i >= 0) root.select(i)
        }
        // the primary action, as its key: put the window into a slot
        onDoubleClicked: (mouse) => {
          if (dragMade) return
          var i = rowAt(mouse.x, mouse.y)
          if (i < 0) return
          root.select(i)
          root.pressKey("a")
        }
        onCanceled: root.dragCancel()
        onExited: hoverIndex = -1
      }

      // Near the list's top or bottom edge a held drag scrolls it.
      Timer {
        interval: 30
        repeat: true
        running: !!root.drag && (root.drag.ly < Tokens.rowHeight || root.drag.ly > listBox.height - Tokens.rowHeight)
        onTriggered: {
          var step = Math.max(2, Math.round(Tokens.rowHeight / 4))
          var most = Math.max(0, list.contentHeight - list.height)
          var y = root.drag.ly < Tokens.rowHeight ? list.contentY - step : list.contentY + step
          list.contentY = Math.max(0, Math.min(most, y))
          root.dragRetarget()
        }
      }
    }
  }

  // The dragged row's ghost by the pointer, and what letting go does there.
  DragGhost {
    id: ghost
    objectName: "dragGhost"
    visible: root.dragging
    z: 10
    title: root.drag ? root.drag.source.cls || "Unknown" : ""
    subtitle: root.drag ? Assignment.titleText(root.drag.source) : ""
    label: root.drag && root.drag.action.kind !== "none" ? root.drag.action.label : ""
    x: root.drag ? Math.max(0, Math.min(root.width - width, root.drag.x + Style.spacing.lg)) : 0
    y: root.drag ? Math.max(0, Math.min(root.height - height, root.drag.y + Style.spacing.md)) : 0
  }
}
