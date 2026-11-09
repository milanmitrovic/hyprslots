pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Assignment.js" as Assignment
import "Workspaces.js" as Workspaces
import "Prompts.js" as Prompts
import "Help.js" as Help

// Which live window fills which slot (aerolayout's AssignmentView). A table
// of the windows on a workspace with the screen, slot, app and title of each,
// plus a "Missing" row for every slot whose window is not running (a slot
// the workspace has no spec for and no window in is an empty row); every
// global slot is a row, those no tree of the workspace places looking the
// same, and `a` into one places it in the active layout's tree; then
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
  readonly property string placeNoteText: Assignment.placeNote(state, rows)

  // The controls strip (StyledText: each trigger key highlighted, Help.js).
  readonly property string accent: String(Commons.Color.accent)
  readonly property string helpText: prompting ? Help.escape(Prompts.help(prompt)) : Help.row([
    [{ key: "↑/↓", label: "select" }],
    { title: "Workspace", items: [{ key: "←/→ [ ]", label: "prev/next" }, { key: Workspaces.jumpKeys(Workspaces.count(state)), label: "jump" }] },
    [{ key: "a", label: "assign" }, { key: "u", label: "unassign" }],
    [{ key: "Ctrl+S", label: "save" }],
    [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
  ], accent)

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
    engine.call("take_spec", { address: row.address, workspace: option.workspace, slot: option.slot, place: true }, function(reply) {
      if (!reply.ok) {
        say(reply.error, true)
        return
      }
      var text = "Assigned " + row.cls + " to " + reply.slot + " on workspace " + reply.workspace
      if (reply.replaced && reply.replaced !== reply.spec) text += " (instead of " + reply.replaced + ")"
      if (reply.displaced) text += "; " + classOf(reply.displaced) + " gave it up"
      var placed = Assignment.placedText(reply, state ? state.desk : "")
      if (placed !== "") text += "; " + placed
      say(text + ". Ctrl+S saves.", false)
      selectedKey = row.address
    })
  }

  function classOf(address) {
    var windows = state && state.windows ? state.windows : []
    for (var i = 0; i < windows.length; i++) if (windows[i].address === address) return windows[i].class
    return address
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
    if (prompting) return handlePrompt(key, text, modifiers)
    if (key === Qt.Key_Up || text === "k") select(selected - 1)
    else if (key === Qt.Key_Down || text === "j") select(selected + 1)
    else if (key === Qt.Key_Left || text === "h" || text === "p" || text === "[") turnPage(-1)
    else if (key === Qt.Key_Right || text === "l" || text === "]") turnPage(1)
    else if (Workspaces.ofDigit(text, Workspaces.count(state)) !== null) goWorkspace(Workspaces.ofDigit(text, Workspaces.count(state)))
    else if (text === "a") startAssign()
    else if (text === "u") startUnassign()
    else return false
    return true
  }

  // Columns: [Screen] Slot App Title, sized by share of the width.
  readonly property real screenWidth: showScreen ? width * 0.1 : 0
  readonly property real slotWidth: width * 0.18
  readonly property real appWidth: width * 0.18
  readonly property real titleWidth: width - screenWidth - slotWidth - appWidth
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: what this page is, a quiet line over the rows; the page's
    // number among them in the accent colour.
    Item {
      id: headerBox
      width: parent.width
      height: headerText.implicitHeight
      Text {
        id: headerText
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.md
        textFormat: Text.PlainText
        text: root.currentPage.label
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: headerText.verticalCenter
        textFormat: Text.StyledText
        text: '<font color="' + root.accent + '">' + (root.page + 1) + "</font> / " + root.pageList.length
        color: Commons.Color.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }

    // Slots no tree places, in a layout other desks share: a places them
    // there too.
    Text {
      id: placeNote
      width: parent.width
      leftPadding: Style.spacing.md
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.placeNoteText
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Why the editor cannot see the engine, or why the engine is off.
    Text {
      id: problem
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: {
        if (!root.engine) return "No engine service."
        if (root.engine.error !== "") return root.engine.error
        var s = root.state
        if (s && s.refused) return "hyprslots is off: " + s.refused
        if (s && s.config_error) return "config error: " + s.config_error
        return ""
      }
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    // Column titles.
    Row {
      id: titles
      width: parent.width
      Repeater {
        model: [
          { text: "Screen", width: root.screenWidth },
          { text: "Slot", width: root.slotWidth },
          { text: "App", width: root.appWidth },
          { text: "Title", width: root.titleWidth },
        ]
        delegate: Text {
          required property var modelData
          width: modelData.width
          visible: modelData.width > 0
          leftPadding: Style.spacing.md
          textFormat: Text.PlainText
          text: modelData.text
          color: root.foreground
          opacity: 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - headerBox.height - titles.height - (problem.visible ? problem.height + parent.spacing : 0)
        - (placeNote.visible ? placeNote.height + parent.spacing : 0)
        - parent.spacing * 2
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selected

      delegate: Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool current: index === root.selected
        // no window in the slot: Missing (the workspace's spec waits for one) or
        // empty (nothing says what fills it)
        readonly property bool missing: modelData.kind === "missing" || modelData.kind === "empty"
        readonly property bool empty: modelData.kind === "empty"
        readonly property color ink: current ? root.selectedText : root.foreground
        width: ListView.view.width
        height: root.rowHeight
        radius: Style.cornerRadius
        color: current ? root.selectedBackground : "transparent"

        MouseArea {
          anchors.fill: parent
          onClicked: root.select(rowItem.index)
        }

        Row {
          anchors.fill: parent
          Text {
            width: root.screenWidth
            visible: root.showScreen
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: Assignment.screenText(root.state, rowItem.modelData)
            color: rowItem.ink
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: root.slotWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: Assignment.slotText(rowItem.modelData)
            color: rowItem.current ? root.selectedText
              : rowItem.modelData.status === "overflow" || rowItem.modelData.status === "unassigned" ? Commons.Color.urgent
              : Commons.Color.accent
            opacity: rowItem.empty ? 0.4 : rowItem.missing || rowItem.modelData.status === "none" ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: !rowItem.missing
            elide: Text.ElideRight
          }
          Text {
            width: root.appWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: rowItem.missing ? Assignment.specText(rowItem.modelData) : (rowItem.modelData.cls || "Unknown")
            color: rowItem.ink
            opacity: rowItem.missing ? 0.55 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: rowItem.modelData.status === "slot" || rowItem.modelData.status === "manual"
            elide: Text.ElideRight
          }
          Text {
            width: root.titleWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            rightPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: Assignment.titleText(rowItem.modelData)
            color: rowItem.missing && !rowItem.empty && !rowItem.current ? Commons.Color.urgent : rowItem.ink
            opacity: rowItem.empty ? 0.4 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.italic: rowItem.missing
            elide: Text.ElideRight
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        textFormat: Text.PlainText
        text: root.state ? "No windows" : (root.engine && root.engine.error === "" ? "Reading hyprslots…" : "")
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
