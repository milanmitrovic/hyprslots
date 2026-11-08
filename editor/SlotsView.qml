pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Slots.js" as Slots
import "Prompts.js" as Prompts

// The global slots (aerolayout's logical slots): defined once for every
// desk, each with its description, the trees that place it and the desks
// that say which app fills it (set from the Assignment view's `a`). ↑/↓
// select; a adds a slot, r renames it (every tree, every desk's spec, the
// assignments follow), e describes it, d deletes it after y/n naming every
// tree and desk it goes from; Ctrl+S (the panel's) saves. Edits stay in
// memory until saved (the header says "unsaved edits"); the engine
// validates each by re-running config.lua, and a refusal shows in the
// prompt it answered, which opens again. The model is Slots.js; the calls
// are the api's add_slot, rename_slot, describe_slot and remove_slot
// (docs/design.md §9).
Item {
  id: root

  property var engine: null
  property int focusedWorkspace: -1

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null
  readonly property var rows: Slots.rows(state)
  // The selection follows the slot by name through every re-read.
  property string selectedSlot: ""
  readonly property int selected: indexOfSlot(selectedSlot)
  readonly property var selectedRow: selected >= 0 && selected < rows.length ? rows[selected] : null
  readonly property string readOnly: Slots.readOnlyReason(state)

  property var prompt: null
  property var _answer: null // what to do with the prompt's answer
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false

  readonly property string helpText: prompting ? Prompts.help(prompt)
    : "↑/↓ select   ·   Slot: a add  r rename  e describe  d delete   ·   which app fills it: Assignment view, a"
      + "   ·   Ctrl+S save   ·   Tab switch view  q close"

  function indexOfSlot(name) {
    for (var i = 0; i < rows.length; i++) if (rows[i].slot === name) return i
    return rows.length > 0 ? 0 : -1
  }

  function select(index) {
    if (rows.length === 0) return
    var i = Math.max(0, Math.min(rows.length - 1, index))
    selectedSlot = rows[i].slot
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
    selectedSlot = ""
  }

  // Open a prompt; answer(value) runs on its answer.
  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  // Run an api call; on success say ok(reply), on failure reopen `again`
  // (a prompt) with the error, or just say it.
  function run(name, args, ok, again, answer) {
    if (!engine) return
    engine.call(name, args, function(reply) {
      if (reply.ok) {
        say(ok(reply), false)
      } else if (again) {
        ask(Prompts.withError(again, reply.error), answer)
      } else {
        say(reply.error, true)
      }
    })
  }

  function editable() {
    if (readOnly === "") return true
    say(readOnly, true)
    return false
  }

  function needRow() {
    if (selectedRow) return true
    say("There are no slots yet; a adds one.", true)
    return false
  }

  function startAdd(values) {
    if (!editable()) return
    values = values || { name: "", description: "", error: "" }
    var namePrompt = Prompts.withError(Prompts.text("New slot name (every desk's trees may place it) [Enter] next  [Esc] cancel: ",
      { value: values.name, required: true }), values.error)
    ask(namePrompt, function(name) {
      ask(Prompts.text("Description [Enter] add  [Esc] cancel: ", { value: values.description }), function(description) {
        engine.call("add_slot", { slot: name.trim(), description: description }, function(reply) {
          if (reply.ok) {
            selectedSlot = reply.slot
            say("Added slot '" + reply.slot + "'. Place it in the Layout view (a), fill it in the Assignment view (a).",
              false)
          } else {
            startAdd({ name: name, description: description, error: reply.error })
          }
        })
      })
    })
  }

  function startRename() {
    if (!needRow() || !editable()) return
    var old = selectedRow.slot
    var label = "Rename '" + old + "' to [Enter] save  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      if (to === old) return
      run("rename_slot", { slot: old, to: to }, function(reply) {
        selectedSlot = reply.to
        var specs = reply.specs || []
        return "Renamed '" + old + "' to '" + reply.to + "'."
          + (reply.trees > 0 ? " Rewrote " + reply.trees + (reply.trees === 1 ? " tree." : " trees.") : "")
          + (specs.length ? " Moved the specs of desk" + (specs.length > 1 ? "s " : " ") + specs.join(", ") + "." : "")
      }, Prompts.text(label, { value: to, required: true }), answer)
    }
    ask(Prompts.text(label, { required: true }), answer)
  }

  function startDescribe() {
    if (!needRow() || !editable()) return
    var slot = selectedRow.slot
    ask(Prompts.text("Description for '" + slot + "' [Enter] save  [Esc] cancel: ", { value: selectedRow.description }),
      function(text) {
        run("describe_slot", { slot: slot, description: text }, function() {
          return text === "" ? "Cleared the description of '" + slot + "'." : "Updated the description of '" + slot + "'."
        })
      })
  }

  function startDelete() {
    if (!needRow() || !editable()) return
    var row = selectedRow
    ask(Prompts.confirm(Slots.deleteQuestion(row)), function(yes) {
      if (!yes) {
        message = ""
        return
      }
      run("remove_slot", { slot: row.slot, force: Slots.inUse(row) }, function() {
        return "Deleted slot '" + row.slot + "'."
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
    return true // the prompt owns the keyboard
  }

  function handleKey(key, text, modifiers) {
    if (prompting) return handlePrompt(key, text, modifiers)
    if (key === Qt.Key_Up || text === "k") select(selected - 1)
    else if (key === Qt.Key_Down || text === "j") select(selected + 1)
    else if (text === "a") startAdd(null)
    else if (text === "r" || key === Qt.Key_Return || key === Qt.Key_Enter) startRename()
    else if (text === "e") startDescribe()
    else if (text === "d") startDelete()
    else return false
    return true
  }

  // Columns: Slot Description Placed-by Filled-on, by share of the width.
  readonly property real slotWidth: width * 0.14
  readonly property real descriptionWidth: width * 0.24
  readonly property real placesWidth: width * 0.3
  readonly property real specsWidth: width - slotWidth - descriptionWidth - placesWidth
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

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
          return "Slots (every desk)   [" + arrangement + "]"
            + (root.readOnly !== "" ? "   (set in config.lua)" : "") + (s && s.dirty ? "   unsaved edits" : "")
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
        text: root.rows.length + (root.rows.length === 1 ? " slot" : " slots")
        color: root.foreground
        opacity: 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
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

    Row {
      id: titles
      width: parent.width
      Repeater {
        model: [
          { text: "Slot", width: root.slotWidth },
          { text: "Description", width: root.descriptionWidth },
          { text: "Placed by", width: root.placesWidth },
          { text: "Filled on desk", width: root.specsWidth },
        ]
        delegate: Text {
          required property var modelData
          width: modelData.width
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
        - places.height - footerText.height - parent.spacing * 4
      clip: true
      model: root.rows
      boundsBehavior: Flickable.StopAtBounds
      currentIndex: root.selected

      delegate: Rectangle {
        id: rowItem
        required property var modelData
        required property int index
        readonly property bool current: index === root.selected
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
            width: root.slotWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: rowItem.modelData.slot
            color: rowItem.current ? root.selectedText : Commons.Color.accent
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
            elide: Text.ElideRight
          }
          Text {
            width: root.descriptionWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: rowItem.modelData.description
            color: rowItem.ink
            opacity: 0.8
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: root.placesWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: Slots.placesText(rowItem.modelData)
            color: rowItem.ink
            opacity: rowItem.modelData.places.length ? 0.8 : 0.5
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
          Text {
            width: root.specsWidth
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Style.spacing.md
            rightPadding: Style.spacing.md
            textFormat: Text.PlainText
            text: Slots.specsText(rowItem.modelData)
            color: rowItem.ink
            opacity: rowItem.modelData.specs.length ? 1 : 0.5
            font.family: "monospace"
            font.pixelSize: Style.font.body
            elide: Text.ElideRight
          }
        }
      }

      Text {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        textFormat: Text.PlainText
        text: root.state ? "No slots yet — press a to add one (left, main, right…)"
          : (root.engine && root.engine.error === "" ? "Reading hyprslots…" : "")
        color: root.foreground
        opacity: 0.55
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }

    // Where the selected slot is placed, in every arrangement.
    Text {
      id: places
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.selectedRow ? root.selectedRow.slot + " is filled on: " + Slots.specsText(root.selectedRow) : " "
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // The prompt (with the engine's refusal under it), or the last outcome.
    Text {
      id: footerText
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
}
