pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Layout.js" as Layout
import "Prompts.js" as Prompts

// One desk's trees, edited (aerolayout's LayoutView). A pane per screen role
// of the arrangement, each a scale model of its screen: boxes proportional
// to the weights, nested containers titled with their kind and ratio,
// accordions as tabs over the open member, then the tree text and ratio
// string. Edits go to a draft; `w` applies it (api set_trees), Ctrl+S (the
// panel's) applies it and saves (api save), `d` puts a screen's tree back
// to what slots.lua holds (api reset), `R` records the windows on screen
// (api record, previewed). The model is Layout.js; the calls are in
// docs/design.md §9.
Item {
  id: root

  property var engine: null
  property int focusedWorkspace: -1

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null

  // What is being edited: an arrangement's desk, and the selected leaf in
  // the pane of one screen role.
  property string arrangement: ""
  property int desk: 0
  property string role: ""
  property string selectedKey: ""

  readonly property var paneList: Layout.panes(state, arrangement, desk)
  // The same, computed now: a handler running on a state change can see the
  // binding above before it has caught up.
  function currentPanes() {
    return Layout.panes(state, arrangement, desk)
  }
  // role -> { node (the draft, null when the screen has no tree), base (the
  // tree text in force it started from), memory (a parked overflow leaf) }
  property var drafts: ({})
  readonly property string block: Layout.editBlock(state, arrangement)
  readonly property bool isActive: state !== null && state.arrangement === arrangement

  // A Prompts.js prompt and what to do with its answer, as in the Slots and
  // Arrangements views.
  property var prompt: null
  property var _answer: null
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false

  readonly property var activeDraft: drafts[role] || null
  readonly property var activeNode: activeDraft ? activeDraft.node : null

  readonly property string helpText: {
    if (prompting) return Prompts.help(prompt)
    return "arrows select   ·   Tree: hjkl move  HJKL force move  / flip  t " + toggleLabel
      + "  r ratios  o overflow   ·   Layout: w apply  Ctrl+S apply+save  d default  R record   ·   g desk  c arrangement"
      + "   ·   Tab switch view  q close"
  }

  readonly property string toggleLabel: {
    if (!activeNode) return "accordion"
    var path = Layout.pathTo(activeNode, selectedKey)
    return path && path.length >= 2 && path[path.length - 2].node.kind === "a" ? "tiles" : "accordion"
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
  }

  function edited(r) {
    var d = drafts[r]
    if (!d) return false
    var text = d.node ? Layout.format(d.node) : null
    return text !== d.base
  }

  function editedRoles() {
    return currentPanes().filter(function(p) { return root.edited(p.role) }).map(function(p) { return p.role })
  }

  // Back to the opening target: the focused workspace's desk and screen.
  function reset() {
    prompt = null
    _answer = null
    message = ""
    drafts = ({})
    selectedKey = ""
    if (state) {
      var t = Layout.initialTarget(state, focusedWorkspace)
      arrangement = t.arrangement || ""
      desk = t.desk
      role = t.role || ""
    }
    sync()
  }

  property bool _placed: false
  onStateChanged: {
    if (!_placed && state) {
      _placed = true
      reset()
    } else {
      sync()
    }
  }

  // Follow the trees in force: a pane whose draft is unedited takes the new
  // tree; an edited one keeps the edit. Keep the selection on a leaf. When
  // the arrangement being edited is gone (renamed or deleted in the
  // Arrangements view), move to the running one.
  function sync() {
    var moved = Layout.retarget(state, { arrangement: arrangement, desk: desk, role: role })
    if (moved) {
      var was = arrangement
      arrangement = moved.arrangement
      desk = moved.desk
      role = moved.role
      drafts = ({})
      selectedKey = ""
      if (was !== "") say("Arrangement '" + was + "' is gone; editing desk " + desk + " of "
        + (arrangement !== "" ? arrangement : "nothing") + ".", false)
    }
    var next = {}
    var list = currentPanes()
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      var d = drafts[p.role]
      if (d && edited(p.role)) {
        next[p.role] = { node: d.node, base: p.tree, memory: d.memory }
      } else {
        var parsed = p.tree !== null ? Layout.parse(p.tree) : { node: null }
        next[p.role] = { node: parsed.node || null, base: p.tree, memory: d && d.base === p.tree ? d.memory : null }
      }
    }
    drafts = next
    keepSelection()
  }

  function keepSelection() {
    var list = currentPanes()
    if (role === "" || !drafts[role]) role = list.length ? list[0].role : ""
    var draft = drafts[role]
    var node = draft ? draft.node : null
    if (node && Layout.leaves(node).indexOf(selectedKey) >= 0) return
    if (!node) {
      // the selection is on a screen with no tree: move to one that has one
      for (var i = 0; i < list.length; i++) {
        var d = drafts[list[i].role]
        if (d && d.node) {
          role = list[i].role
          node = d.node
          break
        }
      }
    }
    selectedKey = node ? Layout.leaves(node)[0] : ""
  }

  function setDraft(r, node, memory) {
    var next = Object.assign({}, drafts)
    var old = drafts[r] || { base: null }
    next[r] = { node: node, base: old.base, memory: memory === undefined ? old.memory : memory }
    drafts = next
  }

  function draftNote() {
    return " Not applied: w applies, Ctrl+S applies and saves."
  }

  // --- keys -----------------------------------------------------------------

  function arrowOf(key) {
    if (key === Qt.Key_Left) return "left"
    if (key === Qt.Key_Right) return "right"
    if (key === Qt.Key_Up) return "up"
    if (key === Qt.Key_Down) return "down"
    return ""
  }

  readonly property var moveKeys: ({ h: "left", l: "right", k: "up", j: "down" })
  readonly property var forceKeys: ({ H: "left", L: "right", K: "up", J: "down" })

  function paneIndex(r) {
    var list = currentPanes()
    for (var i = 0; i < list.length; i++) if (list[i].role === r) return i
    return -1
  }

  // The pane beyond the active one's left or right edge, or null.
  function neighbourPane(direction) {
    if (direction !== "left" && direction !== "right") return null
    var list = currentPanes()
    var i = paneIndex(role) + (direction === "right" ? 1 : -1)
    return i >= 0 && i < list.length ? list[i] : null
  }

  function select(direction) {
    if (!activeNode) return
    var next = Layout.navigate(activeNode, selectedKey, direction)
    if (next !== null) {
      selectedKey = next
      return
    }
    var other = neighbourPane(direction)
    if (!other || !drafts[other.role] || !drafts[other.role].node) return
    var keys = Layout.leaves(drafts[other.role].node)
    role = other.role
    selectedKey = direction === "right" ? keys[0] : keys[keys.length - 1]
  }

  function refuseEdit() {
    if (block === "") return false
    say("Cannot edit: " + block + ".", true)
    return true
  }

  function moveSelected(direction, forced) {
    if (!activeNode || refuseEdit()) return
    var result = forced ? Layout.forceMove(activeNode, selectedKey, direction) : Layout.move(activeNode, selectedKey, direction)
    if (result.error) {
      say(result.error, true)
      return
    }
    if (result.changed) {
      setDraft(role, result.node)
      say("Moved " + selectedKey + "." + draftNote(), false)
      return
    }
    // Nothing moved here: off this screen's edge is the next screen.
    var other = neighbourPane(direction)
    if (!other) return
    var target = drafts[other.role] ? drafts[other.role].node : null
    var crossed = Layout.crossMove(activeNode, target, selectedKey, direction)
    if (crossed.error) {
      say(crossed.error, true)
      return
    }
    var next = Object.assign({}, drafts)
    next[role] = { node: crossed.source, base: drafts[role].base, memory: drafts[role].memory }
    var old = drafts[other.role] || { base: null, memory: null }
    next[other.role] = { node: crossed.target, base: old.base, memory: old.memory }
    drafts = next
    role = other.role
    say("Moved " + selectedKey + " to " + other.role + "." + draftNote(), false)
  }

  function edit(fn, what) {
    if (!activeNode || refuseEdit()) return
    var result = fn(activeNode)
    if (result.error) {
      say(result.error, true)
      return
    }
    setDraft(role, result.node, result.memory)
    say(what + draftNote(), false)
    keepSelection()
  }

  function handleKey(key, text, modifiers) {
    if (prompting) return handlePrompt(key, text, modifiers)
    var arrow = arrowOf(key)
    if (arrow !== "") select(arrow)
    else if (moveKeys[text]) moveSelected(moveKeys[text], false)
    else if (forceKeys[text]) moveSelected(forceKeys[text], true)
    else if (text === "/") edit(function(n) { return { node: Layout.flip(n) } }, "Flipped every split.")
    else if (text === "t") edit(function(n) { return Layout.toggleAccordion(n, root.selectedKey) },
      "Stacked as " + (toggleLabel === "tiles" ? "tiles" : "an accordion") + ".")
    else if (text === "o") toggleOverflow()
    else if (text === "r") startRatio()
    else if (text === "w") apply(null)
    else if (text === "d") startReset()
    else if (text === "R") startRecord()
    else if (text === "g") startPick("desk")
    else if (text === "c") startPick("arrangement")
    else return false
    return true
  }

  function toggleOverflow() {
    if (!activeNode || refuseEdit()) return
    var memory = activeDraft.memory
    var result = Layout.toggleOverflow(activeNode, memory)
    if (result.error) {
      say(result.error, true)
      return
    }
    setDraft(role, result.node, result.memory)
    if (!result.parked) selectedKey = "*"
    keepSelection()
    say((result.parked ? "Overflow leaf parked — windows with no slot get a column at the right."
      : "Overflow leaf back — move it like any node to choose where they go.") + draftNote(), false)
  }

  // Open a prompt; answer(value) runs on its answer.
  function ask(p, answer) {
    prompt = p
    _answer = answer
    message = ""
  }

  function startRatio() {
    if (!activeNode || refuseEdit()) return
    var p = Layout.ratioPrompt(activeNode)
    if (p.error) {
      say(p.error, true)
      return
    }
    ask(Prompts.text(p.text), submitRatio)
  }

  // A ratio the grammar refuses opens the prompt again, the entry kept and
  // the refusal under it.
  function submitRatio(input) {
    var entry = input.trim()
    if (entry === "" || entry.toLowerCase() === "clear") {
      setDraft(role, Layout.clearRatios(activeNode))
      say("Ratios cleared — equal shares everywhere." + draftNote(), false)
      return
    }
    var result = Layout.applyRatio(activeNode, entry)
    if (result.error) {
      ask(Prompts.withError(Prompts.text(Layout.ratioPrompt(activeNode).text, { value: input }), result.error), submitRatio)
      return
    }
    setDraft(role, result.node)
    say("Set ratios " + Layout.ratio(result.node) + "." + draftNote(), false)
  }

  // A y/n question; action() runs on y.
  function confirm(text, action) {
    ask(Prompts.confirm(text), function(yes) {
      if (yes) action()
      else root.message = ""
    })
  }

  function startPick(what) {
    if (!state) return
    var names = what === "desk" ? (state.desks || []).map(String) : Object.keys(state.arrangements || {}).sort()
    if (names.length === 0) return
    ask(Prompts.choice(what === "desk" ? "Edit desk" : "Edit arrangement", Prompts.options(names)), function(name) {
      root.pick(what, name)
    })
  }

  function pick(what, name) {
    var dropped = editedRoles()
    if (what === "desk") desk = parseInt(name, 10)
    else arrangement = name
    drafts = ({})
    role = ""
    selectedKey = ""
    sync()
    var where = "desk " + desk + " of " + arrangement
    say("Editing " + where + "." + (dropped.length ? " Unapplied edits dropped (" + dropped.join(", ") + ")." : ""),
      dropped.length > 0)
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

  // --- engine calls ---------------------------------------------------------

  // w: every edited pane of the desk in one set_trees. `then` runs after it
  // worked (Ctrl+S's save, through applyThen).
  function apply(then) {
    if (refuseEdit()) return
    var roles = editedRoles()
    if (roles.length === 0) {
      if (then) then()
      else say("Nothing to apply: the trees are what the engine runs.", false)
      return
    }
    var trees = {}
    for (var i = 0; i < roles.length; i++) {
      var d = drafts[roles[i]]
      if (!d.node) {
        say(roles[i] + " has no tree left; the engine cannot drop a screen's tree.", true)
        return
      }
      trees[roles[i]] = Layout.format(d.node)
    }
    if (!engine) return
    say("Applying " + roles.join(", ") + "…", false)
    var target = { arrangement: arrangement, desk: desk }
    engine.call("set_trees", { arrangement: target.arrangement, desk: target.desk, trees: trees }, function(reply) {
      if (!reply.ok) {
        root.say(reply.error, true)
        return
      }
      if (reply.arrangement === root.arrangement && reply.desk === root.desk) {
        var next = Object.assign({}, root.drafts)
        for (var r in reply.trees) {
          var parsed = Layout.parse(reply.trees[r].tree)
          next[r] = { node: parsed.node, base: reply.trees[r].tree, memory: next[r] ? next[r].memory : null }
        }
        root.drafts = next
        root.keepSelection()
      }
      var parts = []
      for (var r2 in reply.trees) parts.push(r2 + " " + reply.trees[r2].tree)
      root.say("Applied desk " + reply.desk + ": " + parts.join(", ") + (then ? "" : ". Ctrl+S saves."), false)
      if (then) then()
    })
  }

  // Ctrl+S (the panel's): apply the edited panes first, then `then()`
  // saves. With nothing edited it saves straight away.
  function applyThen(then) {
    if (editedRoles().length === 0) then()
    else apply(then)
  }

  function startReset() {
    if (refuseEdit()) return
    var r = role
    confirm("Put desk " + desk + " on " + r + " back to the tree slots.lua holds?", function() {
      root.engine.call("reset", { arrangement: root.arrangement, desk: root.desk, role: r }, function(reply) {
        if (!reply.ok) {
          root.say(reply.error, true)
          return
        }
        var next = Object.assign({}, root.drafts)
        next[r] = { node: reply.tree ? Layout.parse(reply.tree).node : null, base: reply.tree || null, memory: null }
        root.drafts = next
        root.keepSelection()
        root.say("Desk " + reply.desk + " on " + r + " is back to " + (reply.tree || "no tree") + ".", false)
      })
    })
  }

  function workspaceOf(d, r) {
    var ws = state && state.workspaces ? state.workspaces : {}
    for (var id in ws) if (ws[id].desk === d && ws[id].role === r) return parseInt(id, 10)
    return -1
  }

  // R: measure the windows on the screen, show the tree it makes and what
  // it would drop, apply only when confirmed.
  function startRecord() {
    if (refuseEdit()) return
    if (!isActive) {
      say("Record measures the screens, which run '" + (state && state.arrangement ? state.arrangement : "nothing")
        + "': press c and pick it.", true)
      return
    }
    var id = workspaceOf(desk, role)
    if (id < 0) {
      say("Desk " + desk + " has no workspace on " + role + ".", true)
      return
    }
    var r = role
    say("Recording workspace " + id + "…", false)
    engine.call("record", { workspace: id, apply: false }, function(reply) {
      if (!reply.ok) {
        root.say(reply.error, true)
        return
      }
      var missing = reply.missing || []
      var text = "Recorded " + reply.tree + " (" + reply.ratio + ") from workspace " + reply.workspace
        + (missing.length ? "; missing " + missing.join(", ") + ": applying drops " + (missing.length === 1 ? "it" : "them")
          + " from the tree" : "") + ". Apply it?"
      root.confirm(text, function() {
        var trees = {}
        trees[r] = reply.tree
        root.engine.call("set_trees", { arrangement: reply.arrangement, desk: reply.desk, trees: trees }, function(set) {
          if (!set.ok) {
            root.say(set.error, true)
            return
          }
          var next = Object.assign({}, root.drafts)
          next[r] = { node: Layout.parse(set.trees[r].tree).node, base: set.trees[r].tree, memory: null }
          root.drafts = next
          root.keepSelection()
          root.say("Applied the recorded tree " + set.trees[r].tree + ". Ctrl+S saves.", false)
        })
      })
    })
  }

  // --- for scripts and the e2e smoke ----------------------------------------

  function selectionText() {
    return role + " " + selectedKey
  }

  // The draft trees, "big: h[a, b]; side: c" (edited ones marked *).
  function draftText() {
    return currentPanes().map(function(p) {
      var d = root.drafts[p.role]
      return p.role + ": " + (d && d.node ? Layout.format(d.node) : "-") + (root.edited(p.role) ? " *" : "")
    }).join("; ")
  }

  // --- drawing --------------------------------------------------------------

  function aspectOf(screen) {
    var list = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      if (m && m.name === screen && m.width > 0 && m.height > 0) return m.width / m.height
    }
    return 16 / 9
  }

  readonly property int gap: Style.spacing.md
  readonly property color accordionColor: Commons.Color.accent
  readonly property color overflowColor: Commons.Color.urgent

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: what is being edited.
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
        text: "Desk " + root.desk + "   [" + (root.arrangement || "no arrangement") + "]"
          + (root.state && root.state.arrangement && !root.isActive ? "   these screens run '" + root.state.arrangement + "'" : "")
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
        readonly property int pending: root.editedRoles().length
        text: (pending > 0 ? "edited, not applied (w)   " : "")
          + (root.state && root.state.dirty ? "● unsaved (Ctrl+S)" : "saved")
        color: root.state && root.state.dirty || pending > 0 ? Commons.Color.urgent : root.foreground
        opacity: root.state && root.state.dirty || pending > 0 ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.state && root.state.dirty
      }
    }

    // Why the trees cannot be edited, or the engine cannot be reached.
    Text {
      id: problem
      width: parent.width
      visible: text !== ""
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: {
        if (!root.engine) return "No engine service."
        if (root.engine.error !== "") return root.engine.error
        if (root.state && root.state.config_error) return "config error: " + root.state.config_error
        return root.state && root.block !== "" ? "Read only: " + root.block + "." : ""
      }
      color: Commons.Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    // The panes, side by side: a scale model of each screen.
    Row {
      id: paneRow
      width: parent.width
      height: parent.height - headerBox.height - (problem.visible ? problem.height + parent.spacing : 0)
        - orderText.height - footerText.height - parent.spacing * 4
      spacing: root.gap

      Repeater {
        model: root.paneList
        delegate: Column {
          id: pane
          required property var modelData
          required property int index
          readonly property var draft: root.drafts[modelData.role] || null
          readonly property var node: draft ? draft.node : null
          readonly property bool active: modelData.role === root.role
          readonly property bool changed: root.edited(modelData.role)
          width: (paneRow.width - root.gap * (root.paneList.length - 1)) / Math.max(1, root.paneList.length)
          height: paneRow.height
          spacing: Style.spacing.sm

          Text {
            id: paneTitle
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: pane.modelData.role + (pane.modelData.screen ? "  (" + pane.modelData.screen + ")" : "")
              + (pane.changed ? "   edited" : "") + (pane.modelData.resized && !pane.changed ? "   keyboard-resized" : "")
            color: pane.active ? Commons.Color.accent : root.foreground
            opacity: pane.active ? 1 : 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: pane.active
          }

          // The picture, fitted to the screen's aspect.
          Item {
            id: frame
            width: parent.width
            height: parent.height - paneTitle.height - treeText.height - ratioText.height - parent.spacing * 3
            readonly property real aspect: root.aspectOf(pane.modelData.screen)
            readonly property int boxW: Math.floor(Math.min(width, height * aspect))
            readonly property int boxH: Math.floor(Math.min(height, width / aspect))

            Rectangle {
              id: screenBox
              x: Math.floor((frame.width - frame.boxW) / 2)
              width: frame.boxW
              height: frame.boxH
              radius: Style.cornerRadius
              color: "transparent"
              border.width: pane.active ? 2 : 1
              border.color: pane.active ? Commons.Color.accent : Commons.Util.alpha(root.foreground, 0.35)

              Text {
                anchors.centerIn: parent
                visible: pane.node === null
                textFormat: Text.PlainText
                text: "No tree for desk " + root.desk + " here"
                color: root.foreground
                opacity: 0.5
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.italic: true
              }

              Repeater {
                model: pane.node ? Layout.rects(pane.node, { x: 0, y: 0, w: screenBox.width - 8, h: screenBox.height - 8 }, {
                  pad: 5,
                  title: Style.font.bodySmall + 6,
                  tab: Style.font.bodySmall + 10,
                  selected: pane.active ? root.selectedKey : "",
                  titles: Layout.titles(root.state, root.desk, pane.modelData.role),
                }) : []
                delegate: Rectangle {
                  id: cell
                  required property var modelData
                  readonly property bool isLeaf: modelData.kind === "slot" || modelData.kind === "overflow"
                  readonly property bool isTab: modelData.kind === "tab"
                  readonly property bool isContainer: !isLeaf && !isTab
                  readonly property bool picked: !!modelData.selected
                  x: 4 + modelData.x + 2
                  y: 4 + modelData.y + 2
                  width: Math.max(0, modelData.w - 4)
                  height: Math.max(0, modelData.h - 4)
                  radius: Style.cornerRadius
                  color: picked && isLeaf ? root.selectedBackground
                    : isTab ? Commons.Util.alpha(root.accordionColor, modelData.open ? 0.3 : 0.1)
                    : isLeaf ? Commons.Util.alpha(modelData.kind === "overflow" ? root.overflowColor : root.foreground, 0.06)
                    : "transparent"
                  border.width: picked ? 2 : 1
                  border.color: picked ? Commons.Color.accent
                    : modelData.kind === "a" || isTab ? root.accordionColor
                    : modelData.kind === "overflow" ? Commons.Util.alpha(root.overflowColor, 0.8)
                    : isContainer ? Commons.Util.alpha(root.foreground, 0.3)
                    : Commons.Util.alpha(root.foreground, 0.5)

                  // a container's kind and ratio, top left
                  Text {
                    visible: cell.isContainer
                    x: Style.spacing.sm
                    y: 2
                    width: parent.width - Style.spacing.sm * 2
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: cell.modelData.label
                    color: cell.modelData.kind === "a" ? root.accordionColor : root.foreground
                    opacity: 0.75
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.italic: true
                  }

                  Text {
                    visible: cell.isTab
                    anchors.centerIn: parent
                    width: parent.width - 4
                    horizontalAlignment: Text.AlignHCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: cell.modelData.label
                    color: cell.picked ? Commons.Color.accent : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: !!cell.modelData.open
                  }

                  Column {
                    visible: cell.isLeaf
                    anchors.centerIn: parent
                    width: parent.width - Style.spacing.sm * 2
                    Text {
                      width: parent.width
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: cell.modelData.label
                      color: cell.picked ? root.selectedText
                        : cell.modelData.kind === "overflow" ? root.overflowColor : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      width: parent.width
                      visible: !!cell.modelData.title
                      horizontalAlignment: Text.AlignHCenter
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      text: cell.modelData.title || ""
                      color: root.foreground
                      opacity: 0.55
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: !cell.isContainer
                    onClicked: {
                      root.role = pane.modelData.role
                      root.selectedKey = cell.modelData.key
                    }
                  }
                }
              }
            }
          }

          Text {
            id: treeText
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "tree   " + (pane.node ? Layout.format(pane.node) : "—")
            color: root.foreground
            font.family: "monospace"
            font.pixelSize: Style.font.body
          }
          Text {
            id: ratioText
            width: parent.width
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: "ratio  " + (pane.node && Layout.ratio(pane.node) !== "" ? Layout.ratio(pane.node) : "—")
              + (pane.node && Layout.leaves(pane.node).indexOf("*") < 0 ? "   overflow parked (a column at the right)" : "")
            color: root.foreground
            opacity: 0.75
            font.family: "monospace"
            font.pixelSize: Style.font.body
          }
        }
      }
    }

    // The order the active tree holds its leaves in, once it nests.
    Text {
      id: orderText
      width: parent.width
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.activeNode && Layout.order(root.activeNode) !== "" ? "order  " + Layout.order(root.activeNode) : " "
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // The prompt (with the refusal under it), or the last outcome.
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
