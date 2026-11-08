pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Arrangements.js" as Arrangements
import "Prompts.js" as Prompts

// The arrangements, and which one these monitors run (aerolayout's monitors
// view). The list of arrangements holds the cursor (↑/↓); below it, the
// highlighted one's screens and the connected monitors. hyprslots runs the
// arrangement whose screens are exactly the connected monitors (§8), so
// where aerolayout's [a] mapped these monitors to the row, here it points
// the row's screen roles at them. n makes a new arrangement from these
// monitors (a role name for each, then its trees: the default, none, or
// another arrangement's), r renames, x deletes (saying when these monitors
// will run nothing), e edits a screen (role name, selector), + adds one,
// - removes one, p pins or unpins a role, c copies trees from another
// arrangement or the default; Ctrl+S (the panel's) saves. Edits stay in
// memory until saved.
// The model is Arrangements.js; the calls are the api's arrangement edits
// (docs/design.md §9).
Item {
  id: root

  property var engine: null

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null
  readonly property var rows: Arrangements.rows(state)
  readonly property var monitors: state && state.monitors ? state.monitors : []
  // The cursor holds an arrangement by name, so a rename, creation or
  // delete cannot leave it on a row that moved; it opens on the running one.
  property string cursor: ""
  readonly property int selected: indexOfName(cursor)
  readonly property var selectedRow: selected >= 0 && selected < rows.length ? rows[selected] : null

  property var prompt: null
  property var _answer: null
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false

  readonly property string helpText: prompting ? Prompts.help(prompt)
    : "↑/↓ select   ·   a use on these monitors  n new  r rename  x delete   ·   Screens: e edit  + add  - remove  p pin"
      + "   ·   c copy trees   ·   Ctrl+S save   ·   Tab switch view  q close"

  function indexOfName(name) {
    for (var i = 0; i < rows.length; i++) if (rows[i].name === name) return i
    for (var j = 0; j < rows.length; j++) if (rows[j].active) return j
    return rows.length > 0 ? 0 : -1
  }

  function select(index) {
    if (rows.length === 0) return
    var i = Math.max(0, Math.min(rows.length - 1, index))
    cursor = rows[i].name
    list.positionViewAtIndex(i, ListView.Contain)
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
  }

  function reset() {
    prompt = null
    _answer = null
    message = ""
    cursor = state && state.arrangement ? state.arrangement : ""
  }

  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  function run(name, args, ok, again, answer) {
    if (!engine) return
    engine.call(name, args, function(reply) {
      if (reply.ok) say(ok(reply), false)
      else if (again) ask(Prompts.withError(again, reply.error), answer)
      else say(reply.error, true)
    })
  }

  // What these monitors run after a call that may have changed it.
  function running(reply, name) {
    if (reply.active === name) return " These monitors run '" + name + "'."
    if (reply.active) return " These monitors run '" + reply.active + "' (the first by name that names them)."
    return " These monitors run nothing."
  }

  function needRow(editing) {
    if (!selectedRow) {
      say("No arrangements yet — press n to make one.", true)
      return false
    }
    if (editing && selectedRow.readOnly) {
      say("'" + selectedRow.name + "' is set by code in config.lua; edit it there.", true)
      return false
    }
    return true
  }

  function screensOf(row) {
    var out = {}
    for (var i = 0; i < row.screens.length; i++) out[row.screens[i].role] = row.screens[i].selector
    return out
  }

  function monitorOptions(exclude) {
    var items = []
    for (var i = 0; i < monitors.length; i++) {
      if (exclude && exclude.indexOf(monitors[i].name) >= 0) continue
      var m = monitors[i]
      items.push({ label: m.name + (m.description || m.serial ? " (" + (m.description || m.serial) + ")" : ""), value: m })
    }
    return Prompts.numbered(items)
  }

  function roleOptions(row) {
    return Prompts.options(row.screens.map(function(s) { return s.role }))
  }

  // a: point the highlighted arrangement's roles at these monitors.
  function startUse() {
    if (!needRow(true)) return
    var row = selectedRow
    if (row.screens.length !== monitors.length) {
      say("'" + row.name + "' has " + row.screens.length + (row.screens.length === 1 ? " screen" : " screens") + " and "
        + monitors.length + (monitors.length === 1 ? " monitor is" : " monitors are") + " connected.", true)
      return
    }
    var screens = {}
    var taken = []
    var next = function(i) {
      if (i === row.screens.length) {
        run("set_screens", { arrangement: row.name, screens: screens }, function(reply) {
          return "'" + row.name + "' now names these monitors." + running(reply, row.name)
        })
        return
      }
      var role = row.screens[i].role
      ask(Prompts.choice("Which monitor is '" + role + "'", monitorOptions(taken)), function(m) {
        screens[role] = Arrangements.selectorFor(m)
        taken.push(m.name)
        next(i + 1)
      })
    }
    next(0)
  }

  // n: a new arrangement for these monitors.
  function startNew(values) {
    if (monitors.length === 0) {
      say("No monitors connected — there is nothing to make an arrangement for.", true)
      return
    }
    values = values || { name: "", roles: [], error: "" }
    ask(Prompts.withError(Prompts.text("Name the new arrangement for these monitors [Enter] next  [Esc] cancel: ",
      { value: values.name, required: true }), values.error), function(name) {
      name = name.trim()
      var roles = []
      var nextRole = function(i) {
        if (i === monitors.length) {
          askTrees(name, roles, function(source) {
            var screens = {}
            for (var r = 0; r < roles.length; r++) screens[roles[r]] = Arrangements.selectorFor(monitors[r])
            var args = { name: name, screens: screens }
            if (source.default) args.default = true
            if (source.from) {
              args.from = source.from
              args.roles = source.roles
            }
            engine.call("add_arrangement", args, function(reply) {
              if (reply.ok) {
                cursor = name
                say("Created '" + name + "'." + running(reply, name), false)
              } else {
                startNew({ name: name, roles: roles, error: reply.error })
              }
            })
          })
          return
        }
        var m = monitors[i]
        var suggested = values.roles[i] || Arrangements.suggestedRole(state, m, i, roles)
        ask(Prompts.text("Role for " + m.name + (m.description ? " (" + m.description + ")" : "") + " [Enter] next  [Esc] cancel: ",
          { value: suggested, required: true }), function(role) {
          roles.push(role.trim())
          nextRole(i + 1)
        })
      }
      nextRole(0)
    })
  }

  // Ask where `name`'s trees come from ({ default } | { from, roles } | {});
  // roles of another name are asked one by one.
  function askTrees(name, targetRoles, done) {
    var items = [{ label: "default", value: { default: true } }, { label: "empty", value: {} }]
    var sources = Arrangements.copySources(state, name)
    for (var i = 1; i < sources.length; i++) items.push(sources[i])
    ask(Prompts.choice("Trees for '" + name + "' from", Prompts.options(items)), function(source) {
      if (!source.from) {
        done(source)
        return
      }
      mapRoles(source.from, targetRoles, function(roles) { done({ from: source.from, roles: roles }) })
    })
  }

  function mapRoles(from, targetRoles, done) {
    var sourceRow = null
    for (var i = 0; i < rows.length; i++) if (rows[i].name === from) sourceRow = rows[i]
    var sourceRoles = sourceRow ? sourceRow.screens.map(function(s) { return s.role }) : []
    var mapping = Arrangements.roleMapping(sourceRoles, targetRoles)
    var map = mapping.map
    var next = function(k) {
      if (k === mapping.ask.length) {
        done(map)
        return
      }
      var role = mapping.ask[k]
      var items = sourceRoles.map(function(r) { return { label: r, value: r } })
      items.push({ label: "none", value: "" })
      ask(Prompts.choice("Trees for '" + role + "' from '" + from + "'", Prompts.options(items)), function(sourceRole) {
        if (sourceRole !== "") map[role] = sourceRole
        next(k + 1)
      })
    }
    next(0)
  }

  function startRename() {
    if (!needRow(true)) return
    var old = selectedRow.name
    var label = "Rename arrangement '" + old + "' to [Enter] save  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      if (to === old) return
      run("rename_arrangement", { arrangement: old, to: to }, function() {
        cursor = to
        return "Arrangement '" + old + "' is now '" + to + "'."
      }, Prompts.text(label, { value: to, required: true }), answer)
    }
    ask(Prompts.text(label, { required: true }), answer)
  }

  function startDelete() {
    if (!needRow(true)) return
    var row = selectedRow
    ask(Prompts.confirm(Arrangements.deleteQuestion(row)), function(yes) {
      if (!yes) {
        message = ""
        return
      }
      run("delete_arrangement", { arrangement: row.name }, function(reply) {
        cursor = reply.active || ""
        return "Deleted arrangement '" + row.name + "'." + (row.active ? running(reply, "") : "")
      })
    })
  }

  // e: a screen's role name and selector.
  function startEdit() {
    if (!needRow(true)) return
    var row = selectedRow
    ask(Prompts.choice("Edit which screen of '" + row.name + "'", roleOptions(row)), function(role) {
      var current = screensOf(row)
      ask(Prompts.text("Role name for '" + role + "' [Enter] next  [Esc] cancel: ", { value: role, required: true }),
        function(newRole) {
          newRole = newRole.trim()
          var label = "Selector for '" + newRole + "' (description, serial or connector) [Enter] save  [Esc] cancel: "
          var suggestions = Arrangements.selectorSuggestions(monitors)
          var answer = function(selector) {
            var screens = {}
            for (var r in current) if (r !== role) screens[r] = current[r]
            screens[newRole] = selector.trim()
            var renames = {}
            if (newRole !== role) renames[role] = newRole
            run("set_screens", { arrangement: row.name, screens: screens, renames: renames }, function(reply) {
              return "Screen '" + newRole + "' of '" + row.name + "' selects " + selector.trim() + "." + running(reply, row.name)
            }, Prompts.text(label, { value: selector, required: true, suggestions: suggestions }), answer)
          }
          ask(Prompts.text(label, { value: current[role], required: true, suggestions: suggestions }), answer)
        })
    })
  }

  // +: another screen role.
  function startAddScreen() {
    if (!needRow(true)) return
    var row = selectedRow
    var current = screensOf(row)
    var used = row.screens.map(function(s) { return s.monitor })
    var free = monitors.filter(function(m) { return used.indexOf(m.name) < 0 })
    var taken = row.screens.map(function(s) { return s.role })
    var suggestedRole = free.length ? Arrangements.suggestedRole(state, free[0], row.screens.length, taken) : ""
    ask(Prompts.text("New screen role of '" + row.name + "' [Enter] next  [Esc] cancel: ", { value: suggestedRole, required: true }),
      function(role) {
        role = role.trim()
        var label = "Selector for '" + role + "' [Enter] add  [Esc] cancel: "
        var suggestions = Arrangements.selectorSuggestions(monitors)
        var answer = function(selector) {
          var screens = {}
          for (var r in current) screens[r] = current[r]
          screens[role] = selector.trim()
          run("set_screens", { arrangement: row.name, screens: screens }, function(reply) {
            return "Added screen '" + role + "' to '" + row.name + "'." + running(reply, row.name)
          }, Prompts.text(label, { value: selector, required: true, suggestions: suggestions }), answer)
        }
        ask(Prompts.text(label, { value: free.length ? Arrangements.selectorFor(free[0]) : "", required: true,
          suggestions: suggestions }), answer)
      })
  }

  // -: drop a screen role and its trees.
  function startRemoveScreen() {
    if (!needRow(true)) return
    var row = selectedRow
    if (row.screens.length < 2) {
      say("'" + row.name + "' has one screen; delete the arrangement instead (x).", true)
      return
    }
    ask(Prompts.choice("Remove which screen of '" + row.name + "'", roleOptions(row)), function(role) {
      ask(Prompts.confirm("Remove screen '" + role + "' from '" + row.name + "'? Its trees go."), function(yes) {
        if (!yes) {
          message = ""
          return
        }
        var screens = screensOf(row)
        delete screens[role]
        run("set_screens", { arrangement: row.name, screens: screens }, function(reply) {
          return "Removed screen '" + role + "' from '" + row.name + "'." + running(reply, row.name)
        })
      })
    })
  }

  // p: pin or unpin a role (pinned roles are kept out of workspace switching, in
  // every arrangement).
  function startPin() {
    if (!needRow(false)) return
    var row = selectedRow
    var pinned = state && Array.isArray(state.pinned) ? state.pinned.slice() : []
    var items = row.screens.map(function(s) { return { label: s.role + (s.pinned ? " (pinned)" : ""), value: s.role } })
    ask(Prompts.choice("Pin or unpin which screen", Prompts.options(items)), function(role) {
      var at = pinned.indexOf(role)
      if (at >= 0) pinned.splice(at, 1)
      else pinned.push(role)
      run("set_pinned", { pinned: pinned }, function() {
        return at >= 0 ? "'" + role + "' is no longer pinned: workspace switches move it again."
          : "'" + role + "' is pinned: workspace switches leave it alone."
      })
    })
  }

  // c: replace the highlighted arrangement's trees.
  function startCopy() {
    if (!needRow(true)) return
    var row = selectedRow
    var targetRoles = row.screens.map(function(s) { return s.role })
    ask(Prompts.choice("Copy trees into '" + row.name + "' from", Prompts.options(Arrangements.copySources(state, row.name))),
      function(source) {
        var go = function(args, what) {
          ask(Prompts.confirm("Replace every tree of '" + row.name + "' with " + what + "?"), function(yes) {
            if (!yes) {
              message = ""
              return
            }
            args.arrangement = row.name
            run("copy_trees", args, function() { return "'" + row.name + "' now has " + what + "." })
          })
        }
        if (source.default) go({ default: true }, "the default trees")
        else mapRoles(source.from, targetRoles, function(roles) {
          go({ from: source.from, roles: roles }, "the trees of '" + source.from + "'")
        })
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
    else if (text === "a") startUse()
    else if (text === "n") startNew(null)
    else if (text === "r") startRename()
    else if (text === "x") startDelete()
    else if (text === "e") startEdit()
    else if (text === "+") startAddScreen()
    else if (text === "-") startRemoveScreen()
    else if (text === "p") startPin()
    else if (text === "c") startCopy()
    else return false
    return true
  }

  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)
  readonly property real roleWidth: width * 0.16
  readonly property real selectorWidth: width * 0.38
  readonly property real monitorWidth: width * 0.24

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    Rectangle {
      id: headerBox
      width: parent.width
      height: headerColumn.implicitHeight + Style.spacing.md * 2
      radius: Style.cornerRadius
      color: Commons.Util.alpha(Commons.Color.accent, 0.12)
      border.color: Commons.Util.alpha(Commons.Color.accent, 0.5)
      border.width: 1
      Column {
        id: headerColumn
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.lg
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        Repeater {
          model: Arrangements.header(root.state)
          delegate: Text {
            required property string modelData
            required property int index
            width: headerColumn.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: modelData + (index === 1 && root.state && root.state.dirty ? "   unsaved edits" : "")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: index === 0 ? Style.font.body : Style.font.title
            font.bold: index === 1
          }
        }
      }
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
      height: Math.min(Math.max(1, root.rows.length), 6) * root.rowHeight
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selected

      delegate: Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool current: index === root.selected
        width: ListView.view.width
        height: root.rowHeight
        radius: Style.cornerRadius
        color: current ? root.selectedBackground : "transparent"

        MouseArea {
          anchors.fill: parent
          onClicked: root.select(rowItem.index)
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.md
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Arrangements.rowText(rowItem.modelData)
          color: rowItem.current ? root.selectedText : (rowItem.modelData.active ? Commons.Color.accent : root.foreground)
          // Dim, as in the TUI, when these monitors could not run it.
          opacity: rowItem.modelData.fits || rowItem.current ? 1 : 0.55
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: rowItem.modelData.active
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        textFormat: Text.PlainText
        text: root.state ? "No arrangements yet — press n to make one for these monitors"
          : (root.engine && root.engine.error === "" ? "Reading hyprslots…" : "")
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    // The highlighted arrangement's screens.
    Text {
      id: screensTitle
      width: parent.width
      textFormat: Text.PlainText
      text: root.selectedRow ? "Screens of '" + root.selectedRow.name + "'" : " "
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Column {
      id: screensTable
      width: parent.width
      Repeater {
        model: root.selectedRow ? root.selectedRow.screens : []
        delegate: Row {
          id: screenRow
          required property var modelData
          width: screensTable.width
          height: root.rowHeight
          Text {
            width: root.roleWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: screenRow.modelData.role
            color: Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: root.selectorWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: screenRow.modelData.selector
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: root.monitorWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: screenRow.modelData.monitor ? "→ " + screenRow.modelData.monitor : "not connected"
            color: screenRow.modelData.monitor ? root.foreground : Commons.Color.urgent
            opacity: screenRow.modelData.monitor ? 0.8 : 1
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.italic: !screenRow.modelData.monitor
            elide: Text.ElideRight
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: screenRow.modelData.pinned ? "pinned" : ""
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    Text {
      id: monitorsTitle
      width: parent.width
      textFormat: Text.PlainText
      text: "Connected monitors (what a screen's selector can name)"
      color: root.foreground
      opacity: 0.55
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    Column {
      width: parent.width
      Repeater {
        model: root.monitors
        delegate: Text {
          required property var modelData
          width: parent ? parent.width : 0
          leftPadding: Style.spacing.md
          textFormat: Text.PlainText
          elide: Text.ElideRight
          text: modelData.name + "   description: " + (modelData.description || "—") + "   serial: " + (modelData.serial || "—")
          color: root.foreground
          opacity: 0.7
          font.family: "monospace"
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }

  Text {
    id: footerText
    anchors.bottom: parent.bottom
    width: parent.width
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    text: root.prompting
      ? Prompts.display(root.prompt) + (root.prompt.error ? "\n" + root.prompt.error : "")
      : (root.message !== "" ? root.message : " ")
    color: root.prompting ? (root.prompt.error ? Commons.Color.urgent : Commons.Color.accent)
      : (root.messageIsError ? Commons.Color.urgent : root.foreground)
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    font.bold: root.prompting
  }
}
