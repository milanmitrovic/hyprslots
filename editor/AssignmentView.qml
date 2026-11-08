pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Assignment.js" as Assignment
import "Prompts.js" as Prompts

// Which live window fills which slot (aerolayout's AssignmentView). A table
// of the windows on a desk with the screen, slot, app and title of each,
// plus a "Missing" row for every slot whose window is not running, then the
// windows overflowing on the desk and any others on its workspaces. ←/→ page
// through every window and each desk; ↑/↓ select. `a` puts the selected
// window into one of the global slots on the desk (one key per slot, as the
// TUI prompts) and makes the window's spec the desk's for that slot, as
// aerolayout's `a` did; `c` clears the desk's spec for the selected slot;
// `u` takes a window out. Spec edits stay in memory until Ctrl+S (the
// header says "unsaved edits"). The model is Assignment.js; the calls are
// the api's take_spec, clear_spec and unassign (docs/design.md §9).
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
  readonly property var rows: Assignment.rows(state, currentPage.desk)
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

  readonly property bool showScreen: {
    var seen = {}
    var count = 0
    for (var i = 0; i < rows.length; i++) {
      var role = rows[i].role || ""
      if (!seen[role]) {
        seen[role] = true
        count++
      }
    }
    return count > 1
  }
  readonly property bool showDesk: currentPage.desk === null

  readonly property string helpText: prompting ? Prompts.help(prompt)
    : "↑/↓ select  ←/→ prev/next desk   ·   a assign + take spec  c clear spec  u unassign   ·   Ctrl+S save"
      + "   ·   Tab switch view  q close"

  function keyOf(row) {
    if (!row) return ""
    return row.address ? row.address : "missing:" + row.desk + "/" + row.slot
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

  function say(text, isError) {
    message = text
    messageIsError = !!isError
  }

  // Back to the opening page: the focused workspace's desk.
  function reset() {
    prompt = null
    _answer = null
    message = ""
    page = Assignment.initialPage(state, focusedWorkspace)
    selectedKey = ""
  }

  // Open on the focused desk once the first state arrives.
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
    if (row.kind === "missing") {
      say("Cannot assign a missing window. Unassign or start the app.", true)
      return
    }
    var focusedDesk = Assignment.deskOfWorkspace(state, focusedWorkspace)
    var desk = Assignment.assignDesk(state, currentPage.desk, row, focusedDesk)
    if (desk === null) {
      say(row.cls + " is on no desk: page to a desk (←/→) to assign it there.", true)
      return
    }
    var options = Assignment.slotOptions(state, currentPage.desk, row, focusedDesk)
    if (options.length === 0) {
      say("There are no slots yet: add them in the Slots view.", true)
      return
    }
    ask(Prompts.choice(Assignment.assignTitle(desk), Assignment.promptOptions(options)), function(option) {
      root.assign(row, option)
    })
  }

  // Open a prompt; answer(value) runs on its answer.
  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  // The window takes the slot, and its spec becomes the desk's for it.
  function assign(row, option) {
    if (!engine) return
    say("Assigning " + row.cls + " to " + option.slot + "…", false)
    engine.call("take_spec", { address: row.address, desk: option.desk, slot: option.slot }, function(reply) {
      if (!reply.ok) {
        say(reply.error, true)
        return
      }
      var text = "Assigned " + row.cls + " to " + reply.slot + " (desk " + reply.desk + "): its spec is " + reply.spec
      if (reply.replaced && reply.replaced !== reply.spec) text += " (was " + reply.replaced + ")"
      if (reply.displaced) text += "; " + classOf(reply.displaced) + " gave it up"
      say(text + ". Ctrl+S saves.", false)
      selectedKey = row.address
    })
  }

  function startClear() {
    var target = Assignment.clearTarget(state, currentPage.desk, selectedRow)
    if (target.error) {
      say(target.error, true)
      return
    }
    ask(Prompts.confirm("Clear desk " + target.desk + "'s spec for " + target.slot + " (" + target.spec + ")?"),
      function(yes) {
        if (!yes) {
          root.message = ""
          return
        }
        root.engine.call("clear_spec", { desk: target.desk, slot: target.slot }, function(reply) {
          if (!reply.ok) root.say(reply.error, true)
          else root.say("Desk " + reply.desk + " no longer says what fills " + reply.slot + ". Ctrl+S saves.", false)
        })
      })
  }

  function classOf(address) {
    var windows = state && state.windows ? state.windows : []
    for (var i = 0; i < windows.length; i++) if (windows[i].address === address) return windows[i].class
    return address
  }

  function startUnassign() {
    var row = selectedRow
    if (!row) return
    if (row.kind === "missing") {
      say("No window in " + row.slot + " to unassign.", true)
      return
    }
    if (row.status !== "slot" && row.status !== "manual" && row.status !== "overflow") {
      say(row.cls + " is in no slot.", true)
      return
    }
    ask(Prompts.confirm(row.status === "overflow" ? "Take " + row.cls + " out of the overflow of " + row.slot + "?"
      : "Unassign " + row.cls + " from " + row.slot + " slot?"), function(yes) {
      if (yes) root.unassign(row)
      else root.message = ""
    })
  }

  function unassign(row) {
    if (!engine) return
    engine.call("unassign", { address: row.address }, function(reply) {
      if (!reply.ok) say(reply.error, true)
      else say(reply.slot ? "Unassigned " + row.cls + " from " + reply.slot + "." : "Took " + row.cls + " out of the overflow.", false)
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
    else if (key === Qt.Key_Left || text === "h" || text === "p") turnPage(-1)
    else if (key === Qt.Key_Right || text === "l") turnPage(1)
    else if (text === "a") startAssign()
    else if (text === "u") startUnassign()
    else if (text === "c") startClear()
    else return false
    return true
  }

  // Columns: [Desk] [Screen] Slot App Title, sized by share of the width.
  readonly property real deskWidth: showDesk ? width * 0.07 : 0
  readonly property real screenWidth: showScreen ? width * 0.1 : 0
  readonly property real slotWidth: width * 0.18
  readonly property real appWidth: width * 0.18
  readonly property real titleWidth: width - deskWidth - screenWidth - slotWidth - appWidth
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: what this page is, and what the screens run.
    Rectangle {
      id: headerBox
      width: parent.width
      height: headerText.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: Commons.Util.alpha(Commons.Color.accent, 0.12)
      border.color: Commons.Util.alpha(Commons.Color.accent, 0.5)
      border.width: 1
      Text {
        id: headerText
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: {
          var s = root.state
          var arrangement = s && s.arrangement ? s.arrangement : "no arrangement"
          return root.currentPage.label + "   [" + arrangement + "]" + (s && s.dirty ? "   unsaved edits" : "")
        }
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: (root.page + 1) + " / " + root.pageList.length
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
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
          { text: "Desk", width: root.deskWidth },
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
        - footerText.height - parent.spacing * 3
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selected

      delegate: Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool current: index === root.selected
        readonly property bool missing: modelData.kind === "missing"
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
            width: root.deskWidth
            visible: root.showDesk
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: rowItem.modelData.desk !== null && rowItem.modelData.desk !== undefined ? String(rowItem.modelData.desk) : ""
            color: rowItem.ink
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: root.screenWidth
            visible: root.showScreen
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: rowItem.modelData.role || ""
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
            opacity: rowItem.missing || rowItem.modelData.status === "none" ? 0.55 : 1
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
            text: rowItem.missing ? "Missing" : (rowItem.modelData.title || "No Title")
            color: rowItem.missing && !rowItem.current ? Commons.Color.urgent : rowItem.ink
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

    // The prompt, or the last call's outcome.
    Text {
      id: footerText
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: root.prompting ? Prompts.display(root.prompt) : (root.message !== "" ? root.message : " ")
      color: root.prompting ? Commons.Color.accent : (root.messageIsError ? Commons.Color.urgent : root.foreground)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.bold: root.prompting
    }
  }
}
