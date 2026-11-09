pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "DesksLayouts.js" as DesksLayouts
import "Prompts.js" as Prompts
import "Help.js" as Help

// The desks and the layouts (docs/design.md §9). A desk is a monitor setup:
// the monitors it is made of (● connected) and the layout it uses; the desk
// whose monitors are exactly the connected ones is
// active, and every edit in the other tabs goes to its layout. A layout is a
// logical arrangement for N screens; any desk with N monitors may use it, and
// several desks may share one. One selection runs through both lists (↑/↓,
// k/j). a applies a layout (on a layout row: to the active desk; on a desk
// row: one picked among those with its screen count), f forks the selected
// layout (or the desk's) under a new name and points the active desk at the
// copy, n makes a layout (name, screen count, empty or the default trees), r
// renames, x deletes (a layout desks use moves them to another first). Edits
// stay in memory until Ctrl+S (the
// panel's). The model is DesksLayouts.js; the calls are the api's desk and
// layout edits.
Item {
  id: root

  property var engine: null

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null
  readonly property var rows: DesksLayouts.rows(state)
  // The cursor holds a row by key ("desk:laptop", "layout:docked"), so a
  // rename, creation or delete cannot leave it on a row that moved; it opens
  // on the active desk.
  property string cursor: ""
  readonly property int selected: indexOfKey(cursor)
  readonly property var selectedRow: selected >= 0 && selected < rows.length ? rows[selected] : null

  property var prompt: null
  property var _answer: null
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false
  // Counts say(): the panel's message band knows a message by it.
  property int messageSeq: 0

  readonly property string accent: String(Commons.Color.accent)
  readonly property string helpText: prompting ? Help.escape(Prompts.help(prompt)) : Help.row([
    [{ key: "↑/↓", label: "select" }],
    { title: selectedRow ? (selectedRow.kind === "desk" ? "Desk" : "Layout") : "", items: DesksLayouts.actions(selectedRow) },
    [{ key: "Ctrl+S", label: "save" }],
    [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
  ], accent)

  function indexOfKey(key) {
    for (var i = 0; i < rows.length; i++) if (rows[i].key === key) return i
    for (var j = 0; j < rows.length; j++) if (rows[j].kind === "desk" && rows[j].active) return j
    return rows.length > 0 ? 0 : -1
  }

  function select(index) {
    if (rows.length === 0) return
    var i = Math.max(0, Math.min(rows.length - 1, index))
    cursor = rows[i].key
    list.positionViewAtIndex(i, ListView.Contain)
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
    messageSeq++
  }

  function reset() {
    prompt = null
    _answer = null
    message = ""
    cursor = state && state.desk ? "desk:" + state.desk : ""
  }

  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  // A call; ok(reply) says what it did. A refusal reopens `again` (with the
  // answer kept) when given, else it is the message.
  function run(name, args, ok, again, answer) {
    if (!engine) return
    engine.call(name, args, function(reply) {
      if (reply.ok) root.say(ok(reply), false)
      else if (again) root.ask(Prompts.withError(again, reply.error), answer)
      else root.say(reply.error, true)
    })
  }

  function confirm(text, action) {
    ask(Prompts.confirm(text), function(yes) {
      if (yes) action()
      else root.message = ""
    })
  }

  function needRow(editing) {
    if (!selectedRow) {
      say(state ? "No desks or layouts yet — n makes a layout." : "No state from hyprslots yet.", true)
      return false
    }
    var refusal = editing ? DesksLayouts.readOnlyError(selectedRow) : ""
    if (refusal !== "") {
      say(refusal, true)
      return false
    }
    return true
  }

  // a: on a layout row, that layout on the active desk; on a desk row, a
  // layout for that desk among those with its screen count.
  function startApply() {
    if (!needRow(false)) return
    var row = selectedRow
    if (row.kind === "layout") {
      var block = DesksLayouts.applyBlock(state, row.name)
      if (block !== "") {
        say(block, true)
        return
      }
      if (state.layout === row.name) {
        say("Desk '" + state.desk + "' uses '" + row.name + "' already.", false)
        return
      }
      run("apply_layout", { layout: row.name }, function(reply) {
        return "Desk '" + reply.desk + "' uses layout '" + reply.layout + "' now. Ctrl+S saves."
      })
      return
    }
    if (!needRow(true)) return
    var names = DesksLayouts.layoutsFor(state, row.name)
    if (names.length === 0) {
      say("No layout has " + row.screens + (row.screens === 1 ? " screen" : " screens")
        + " for desk '" + row.name + "': n makes one.", true)
      return
    }
    var items = names.map(function(n) { return { label: n + (n === row.layout ? " (in use)" : ""), value: n } })
    ask(Prompts.choice("Layout for desk '" + row.name + "'", Prompts.options(items)), function(layout) {
      if (layout === row.layout) {
        root.say("Desk '" + row.name + "' uses '" + layout + "' already.", false)
        return
      }
      root.run("apply_layout", { desk: row.name, layout: layout }, function(reply) {
        return "Desk '" + reply.desk + "' uses layout '" + reply.layout + "' now. Ctrl+S saves."
      })
    })
  }

  // f: a copy of the selected layout (or the selected desk's) under a new
  // name; the active desk then uses the copy when its screen count matches.
  function startFork() {
    if (!needRow(false)) return
    var source = DesksLayouts.forkSource(selectedRow)
    var label = "Fork layout '" + source + "' as [Enter] fork  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      root.engine.call("fork_layout", { layout: source, to: to }, function(reply) {
        if (!reply.ok) {
          root.ask(Prompts.withError(Prompts.text(label, { value: to, required: true }), reply.error), answer)
          return
        }
        root.cursor = "layout:" + reply.to
        root.say(DesksLayouts.forkMessage(reply), false)
      })
    }
    ask(Prompts.text(label, { value: DesksLayouts.forkName(state, source), required: true }), answer)
  }

  // n: a new layout: its name, its screen count (the active desk's
  // suggested), then empty or the default trees.
  function startNew(values) {
    values = values || { name: "", screens: "", error: "" }
    ask(Prompts.withError(Prompts.text("Name the new layout [Enter] next  [Esc] cancel: ",
      { value: values.name, required: true }), values.error), function(name) {
      name = name.trim()
      root.askScreens(name, values.screens !== "" ? values.screens : String(DesksLayouts.suggestedScreens(root.state)), "")
    })
  }

  function askScreens(name, value, error) {
    ask(Prompts.withError(Prompts.text("Screens of '" + name + "' [Enter] next  [Esc] cancel: ", { value: value, required: true }),
      error), function(text) {
      var parsed = DesksLayouts.parseScreens(text)
      if (parsed.error) {
        root.askScreens(name, text, parsed.error)
        return
      }
      root.ask(Prompts.choice("Start '" + name + "'", [
        { key: "d", label: "default trees", value: true },
        { key: "e", label: "empty", value: false },
      ]), function(withDefault) {
        root.engine.call("add_layout", { name: name, screens: parsed.screens, default: withDefault }, function(reply) {
          if (!reply.ok) {
            root.startNew({ name: name, screens: String(parsed.screens), error: reply.error })
            return
          }
          root.cursor = "layout:" + reply.layout
          root.say("Created layout '" + reply.layout + "' (" + reply.screens + (reply.screens === 1 ? " screen" : " screens")
            + (withDefault ? ", the default trees" : ", empty") + "). a applies it to the active desk. Ctrl+S saves.", false)
        })
      })
    })
  }

  // r: rename the selected desk or layout (desks using a layout follow it).
  function startRename() {
    if (!needRow(true)) return
    var row = selectedRow
    var desk = row.kind === "desk"
    var label = "Rename " + (desk ? "desk" : "layout") + " '" + row.name + "' to [Enter] save  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      if (to === row.name) return
      var args = desk ? { desk: row.name, to: to } : { layout: row.name, to: to }
      root.run(desk ? "rename_desk" : "rename_layout", args, function(reply) {
        root.cursor = row.kind + ":" + reply.to
        return (desk ? "Desk '" : "Layout '") + row.name + "' is now '" + reply.to + "'. Ctrl+S saves."
      }, Prompts.text(label, { value: to, required: true }), answer)
    }
    ask(Prompts.text(label, { required: true }), answer)
  }

  // x: delete a desk after y/n; a layout desks use moves them to another of
  // the same screen count first (picked), else y/n (the engine says why it
  // will not, while desks use it).
  function startDelete() {
    if (!needRow(true)) return
    var row = selectedRow
    if (row.kind === "desk") {
      confirm(DesksLayouts.deleteDeskQuestion(row), function() {
        root.run("delete_desk", { desk: row.name }, function() {
          return "Deleted desk '" + row.name + "'." + (row.active ? " These monitors get a new desk in a second." : "")
            + " Ctrl+S saves."
        })
      })
      return
    }
    var plan = DesksLayouts.deleteLayoutPlan(state, row)
    var done = function(reply) {
      var moved = reply.desks && reply.desks.length
        ? " " + (reply.desks.length === 1 ? "Desk " : "Desks ") + reply.desks.join(", ") + " use '" + reply.remap + "' now." : ""
      return "Deleted layout '" + row.name + "'." + moved + " Ctrl+S saves."
    }
    if (plan.remap.length > 0) {
      ask(Prompts.choice(plan.question, Prompts.options(plan.remap)), function(remap) {
        root.run("delete_layout", { layout: row.name, remap: remap }, done)
      })
      return
    }
    confirm(plan.question, function() {
      root.run("delete_layout", { layout: row.name }, done)
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
    return true
  }

  function handleKey(key, text, modifiers) {
    if (prompting) return handlePrompt(key, text, modifiers)
    if (key === Qt.Key_Up || text === "k") select(selected - 1)
    else if (key === Qt.Key_Down || text === "j") select(selected + 1)
    else if (text === "a") startApply()
    else if (text === "f") startFork()
    else if (text === "n") startNew(null)
    else if (text === "r") startRename()
    else if (text === "x") startDelete()
    else return false
    return true
  }

  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)
  readonly property real markWidth: width * 0.09
  readonly property real nameWidth: width * 0.2

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // What this tab is about, a quiet line over the lists.
    Text {
      id: headerBox
      width: parent.width
      leftPadding: Style.spacing.md
      rightPadding: Style.spacing.md
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "A desk is a monitor setup; it uses a layout with as many screens, and desks may share one."
        + " The other tabs edit the active desk's layout."
      color: Commons.Color.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

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
        if (s && s.config_error) return "config error: " + s.config_error
        return ""
      }
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    ListView {
      id: list
      width: parent.width
      height: parent.height - headerBox.height - (problem.visible ? problem.height + parent.spacing : 0)
        - parent.spacing
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selected

      delegate: Column {
        id: entry
        required property var modelData
        required property int index
        readonly property bool current: index === root.selected
        readonly property bool desk: modelData.kind === "desk"
        // the first row of its kind opens its section
        readonly property bool first: index === 0 || root.rows[index - 1].kind !== modelData.kind
        readonly property var cells: desk ? DesksLayouts.deskCells(modelData) : DesksLayouts.layoutCells(modelData)
        readonly property color ink: current ? root.selectedText : root.foreground
        width: ListView.view.width

        Text {
          visible: entry.first
          width: parent.width
          topPadding: entry.index === 0 ? 0 : Style.spacing.lg
          bottomPadding: Style.spacing.xs
          textFormat: Text.PlainText
          text: entry.desk ? "Desks — monitor setups (● connected, ○ not)" : "Layouts — logical arrangements for N screens"
          color: root.foreground
          opacity: 0.6
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.bold: true
        }

        // The section's column titles (a desk's layout column is the one it
        // uses: "Uses layout", each cell "→ <layout>").
        Row {
          visible: entry.first
          width: parent.width
          readonly property var titles: DesksLayouts.columnTitles(entry.modelData.kind)
          Repeater {
            model: entry.desk
              ? [{ text: "", width: root.markWidth }, { text: parent.titles.name, width: root.nameWidth },
                { text: parent.titles.monitors, width: root.width * 0.43 },
                { text: parent.titles.layout, width: root.width - root.markWidth - root.nameWidth - root.width * 0.43 }]
              : [{ text: "", width: root.markWidth }, { text: parent.titles.name, width: root.nameWidth },
                { text: parent.titles.screens, width: root.width * 0.14 },
                { text: parent.titles.usedBy, width: root.width - root.markWidth - root.nameWidth - root.width * 0.14 }]
            delegate: Text {
              required property var modelData
              width: modelData.width
              leftPadding: Style.spacing.md
              bottomPadding: Style.spacing.xs
              textFormat: Text.PlainText
              text: modelData.text
              color: root.foreground
              opacity: 0.45
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
        }

        Rectangle {
          width: parent.width
          height: root.rowHeight
          radius: Style.cornerRadius
          color: entry.current ? root.selectedBackground
            : entry.modelData.active ? Commons.Util.alpha(Commons.Color.accent, 0.1) : "transparent"
          border.width: entry.modelData.active ? 1 : 0
          border.color: Commons.Util.alpha(Commons.Color.accent, 0.6)

          MouseArea {
            anchors.fill: parent
            onClicked: root.select(entry.index)
          }

          Row {
            anchors.fill: parent
            Text {
              width: root.markWidth
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.md
              textFormat: Text.PlainText
              text: entry.cells.mark
              color: entry.current ? root.selectedText : Commons.Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            Text {
              width: root.nameWidth
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.md
              textFormat: Text.PlainText
              text: entry.cells.name
              color: entry.current ? root.selectedText : entry.modelData.active ? Commons.Color.accent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              elide: Text.ElideRight
            }
            // a desk: its monitors and its layout; a
            // layout: its screen count and the desks using it
            Text {
              width: entry.desk ? root.width * 0.43 : root.width * 0.14
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.md
              textFormat: Text.PlainText
              text: entry.desk ? entry.cells.monitors : entry.cells.screens
              color: entry.ink
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
            Text {
              width: root.width - root.markWidth - root.nameWidth - root.width * (entry.desk ? 0.43 : 0.14)
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.spacing.md
              textFormat: Text.PlainText
              text: entry.desk ? entry.cells.layout : entry.cells.usedBy
              color: entry.ink
              opacity: entry.desk || entry.modelData.usedBy.length ? 1 : 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        textFormat: Text.PlainText
        text: root.state ? "No desks or layouts yet — n makes a layout"
          : (root.engine && root.engine.error === "" ? "Reading hyprslots…" : "")
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
