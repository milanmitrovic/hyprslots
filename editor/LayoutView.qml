pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Workspaces.js" as Workspaces
import "Layout.js" as Layout
import "Prompts.js" as Prompts
import "Slots.js" as Slots
import "DesksLayouts.js" as DesksLayouts
import "Help.js" as Help
import "ui"

// One workspace's trees in the active desk's layout, edited (aerolayout's
// LayoutView). A pane per screen 1..N of the layout, labelled with the
// active desk's monitor at that position, each a scale model of it: tiles are
// boxes proportional to the weights, nested containers titled with their kind
// and ratio; a scroll tree is a filmstrip, its columns half or full screen
// width in slot order with the screen a viewport over them (Layout.filmstrip).
// Every tree has every global slot (the engine sees to it; an empty slot
// takes no room), so there is nothing to add to a tree or take out of it. t
// cycles a tree through tiles, scroll half and scroll full; r sets a tiled
// tree's ratios. Edits go to a draft; `w` applies it (api set_trees), Ctrl+S
// (the panel's) applies it and saves (api save), `d` reverts a screen's tree
// to how it was last saved (api reset), `R` records the windows on screen
// (api record, previewed). It opens on "All workspaces" (`-`): the layout's
// shared (default) trees, which every workspace with none of its own uses;
// [ ] and the digits change the workspace (Workspaces.js; a dot marks one
// with trees of its own). A workspace on the shared trees shows them, and
// its first edit asks whether it is for all workspaces (the shared trees)
// or only this one (w then gives it its own); `u` drops a workspace's own
// trees, back to the shared ones (api drop_override). Forking a layout
// other desks share is the Desk tab's.
//
// Beside the picture, the global slots (aerolayout's logical slots), their
// names and descriptions: `s` moves the keys to that list and back (Esc
// too), where a makes a slot (name, then an optional description; api
// add_slot: every tree gets it), Return selects the selected one in the
// picture, r renames it everywhere (rename_slot), e describes it
// (describe_slot), d deletes it after y/n naming the trees and workspaces it
// goes from (remove_slot). The models are Layout.js and Slots.js; the calls
// are in docs/design.md §9.
Item {
  id: root

  property var engine: null
  property int focusedWorkspace: -1

  property color foreground: Commons.Color.menu.text
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  property string fontFamily: Style.font.menuFamily

  readonly property var state: engine ? engine.state : null

  // What is being edited: a workspace (1..10, or "default" for the shared
  // trees, "All workspaces") of the active desk's layout, and the selected
  // leaf in the pane of one screen (its key: "1", "2"...).
  property string layout: ""
  property var workspace: 0
  // Whom the edits of a workspace on the shared trees are for, once asked:
  // "all" (the shared trees), "only" (this workspace: w gives it its own),
  // "" not asked yet. A workspace switch asks again.
  property string scope: ""
  property string screen: ""
  property string selectedKey: ""
  // A slot the slot list just made: edited drafts get it (appendSlots) on
  // the screen the engine's state shows it on, once a re-read has it.
  property string _newSlot: ""

  readonly property var paneList: Layout.panes(state, layout, workspace)
  // The same, computed now: a handler running on a state change can see the
  // binding above before it has caught up.
  function currentPanes() {
    return Layout.panes(state, layout, workspace)
  }
  // screen key -> { node (the draft, null when the screen has no tree), base
  // (the tree text in force it started from) }
  property var drafts: ({})
  readonly property string block: Layout.editBlock(state, layout)
  // The other desks using this layout: every edit changes it for them too.
  readonly property var sharedWith: state ? DesksLayouts.sharedWith(state, layout, state.desk) : []

  // A Prompts.js prompt and what to do with its answer, as in the
  // Assignment and Desk views.
  property var prompt: null
  property var _answer: null
  readonly property bool prompting: prompt !== null
  property string message: ""
  property bool messageIsError: false
  // Counts say(): the panel's message band knows a message by it.
  property int messageSeq: 0

  // o: whether the picture shows where other windows (windows assigned to
  // no slot) go. Every tree has that place (Layout.withOther); o only shows
  // or hides it, and while it shows, hjkl move it like a slot.
  property bool showOther: false

  readonly property var activeDraft: drafts[screen] || null
  readonly property var activeNode: activeDraft ? activeDraft.node : null

  // The slot list: where the keys go (s switches), its rows (name and
  // description; Slots.js), the selected slot by name through re-reads.
  property bool slotFocus: false
  readonly property var slotRows: Slots.rows(state)
  property string selectedSlot: ""
  readonly property int slotIndex: indexOfSlot(selectedSlot)
  readonly property var slotRow: slotIndex >= 0 && slotIndex < slotRows.length ? slotRows[slotIndex] : null
  readonly property string slotsReadOnly: Slots.readOnlyReason(state)

  // The controls strip (StyledText: each trigger key highlighted, Help.js).
  readonly property string accent: String(Commons.Color.accent)
  readonly property string helpText: {
    if (prompting) return Help.escape(Prompts.help(prompt))
    var jump = Workspaces.jumpKeys(Workspaces.count(state))
    if (slotFocus) return Help.row(Layout.slotListHelp({ jumpKeys: jump }), accent)
    return Help.row(Layout.pictureHelp({ node: activeNode, hasOwn: Layout.hasOwn(state, layout, workspace), jumpKeys: jump }),
      accent)
  }

  function say(text, isError) {
    message = text
    messageIsError = !!isError
    messageSeq++
  }

  function edited(k) {
    var d = drafts[k]
    if (!d) return false
    var text = d.node ? Layout.format(d.node) : null
    return text !== d.base
  }

  function editedScreens() {
    return currentPanes().filter(function(p) { return root.edited(p.key) }).map(function(p) { return p.key })
  }

  // "workspace 3", or "all workspaces (the shared tree)" (the layout's
  // default trees: the workspaces without trees of their own use them).
  function workspaceName(n) {
    return n === "default" ? "all workspaces (the shared tree)" : "workspace " + n
  }

  // Where an edit goes: the shared trees ("default") once asked for all
  // workspaces, else the workspace shown.
  function target() {
    return Layout.editTarget(workspace, scope)
  }

  // Back to the opening target: the focused workspace's number and screen.
  function reset() {
    prompt = null
    _answer = null
    message = ""
    drafts = ({})
    selectedKey = ""
    slotFocus = false
    showOther = false
    selectedSlot = ""
    scope = ""
    if (state) {
      // All workspaces first: the shared trees most workspaces use.
      var t = Layout.initialTarget(state, focusedWorkspace)
      layout = state.layout || ""
      workspace = "default"
      screen = String(t.screen)
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
  // tree; an edited one keeps the edit (and gets a slot the slot list just
  // made, where the engine put it). Keep the selection on a leaf. When the
  // active desk's layout changes (another applied, a fork, a rename, a
  // hotplug), follow it.
  function sync() {
    var now = state && state.layout ? state.layout : ""
    if (state && now !== layout) {
      var was = layout
      var dropped = editedScreens()
      layout = now
      drafts = ({})
      if (was !== "") {
        say((now !== "" ? "The active desk uses layout '" + now + "' now; editing it." : "No desk is active: nothing to edit.")
          + (dropped.length ? " Unapplied edits dropped (screen " + dropped.join(", ") + ")." : ""), dropped.length > 0)
      }
    }
    var list = currentPanes()
    if (_newSlot !== "" && state && Array.isArray(state.slots)
        && state.slots.some(function(s) { return s.name === root._newSlot })) {
      drafts = Layout.followNewSlot(drafts, list, _newSlot)
      _newSlot = ""
    }
    var next = {}
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      var d = drafts[p.key]
      if (d && edited(p.key)) {
        next[p.key] = { node: d.node, base: p.tree }
      } else {
        var parsed = p.tree !== null ? Layout.parse(p.tree) : { node: null }
        next[p.key] = { node: parsed.node || null, base: p.tree }
      }
    }
    drafts = next
    keepSelection()
  }

  function keepSelection() {
    var list = currentPanes()
    if (screen === "" || !drafts[screen]) screen = list.length ? list[0].key : ""
    var draft = drafts[screen]
    var node = draft ? pictureOf(draft.node) : null
    if (node && Layout.leaves(node).indexOf(selectedKey) >= 0) return
    if (!node) {
      // the selection is on a screen with no tree: move to one that has one
      for (var i = 0; i < list.length; i++) {
        var d = drafts[list[i].key]
        if (d && d.node) {
          screen = list[i].key
          node = pictureOf(d.node)
          break
        }
      }
    }
    selectedKey = node ? Layout.leaves(node)[0] : ""
  }

  function setDraft(k, node) {
    var next = Object.assign({}, drafts)
    var old = drafts[k] || { base: null }
    next[k] = { node: node, base: old.base }
    drafts = next
  }

  // The tree as the picture draws it (Layout.picture): with or without
  // the place for other windows, as o says.
  function pictureOf(node) {
    return Layout.picture(node, showOther)
  }

  // A leaf as messages name it.
  function leafName(key) {
    return key === "*" ? "other windows" : key
  }

  function draftNote() {
    return " Not applied: w applies, Ctrl+S applies and saves."
      + (sharedWith.length ? " Desk" + (sharedWith.length > 1 ? "s " : " ") + sharedWith.join(", ") + " share" + (sharedWith.length > 1 ? "" : "s")
        + " this layout: fork it in the Desk tab first." : "")
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

  function paneIndex(k) {
    var list = currentPanes()
    for (var i = 0; i < list.length; i++) if (list[i].key === k) return i
    return -1
  }

  // The pane beyond the active one's left or right edge, or null.
  function neighbourPane(direction) {
    if (direction !== "left" && direction !== "right") return null
    var list = currentPanes()
    var i = paneIndex(screen) + (direction === "right" ? 1 : -1)
    return i >= 0 && i < list.length ? list[i] : null
  }

  function select(direction) {
    if (!activeNode) return
    var next = Layout.navigate(pictureOf(activeNode), selectedKey, direction)
    if (next !== null) {
      selectedKey = next
      return
    }
    var other = neighbourPane(direction)
    if (!other || !drafts[other.key] || !drafts[other.key].node) return
    var keys = Layout.leaves(pictureOf(drafts[other.key].node))
    screen = other.key
    selectedKey = direction === "right" ? keys[0] : keys[keys.length - 1]
  }

  function refuseEdit() {
    if (block === "") return false
    say("Cannot edit: " + block + ".", true)
    return true
  }

  function moveSelected(direction, forced) {
    if (!activeNode || refuseEdit()) return
    // other windows' place, where the engine puts them unless the tree
    // says (*), is written into the tree as it moves
    var from = selectedKey === "*" ? Layout.withOther(activeNode) : activeNode
    var result = forced ? Layout.forceMove(from, selectedKey, direction) : Layout.move(from, selectedKey, direction)
    if (result.error) {
      say(result.error, true)
      return
    }
    if (result.changed) {
      setDraft(screen, result.node)
      say("Moved " + leafName(selectedKey) + "." + draftNote(), false)
      return
    }
    // Nothing moved here: off this screen's edge is the next screen.
    var other = neighbourPane(direction)
    if (!other) return
    var target = drafts[other.key] ? drafts[other.key].node : null
    var crossed = Layout.crossMove(activeNode, target, selectedKey, direction)
    if (crossed.error) {
      say(crossed.error, true)
      return
    }
    var next = Object.assign({}, drafts)
    next[screen] = { node: crossed.source, base: drafts[screen].base }
    var old = drafts[other.key] || { base: null }
    next[other.key] = { node: crossed.target, base: old.base }
    drafts = next
    screen = other.key
    say("Moved " + selectedKey + " to screen " + other.key + "." + draftNote(), false)
  }

  function edit(fn, what) {
    if (!activeNode || refuseEdit()) return
    var result = fn(activeNode)
    if (result.error) {
      say(result.error, true)
      return
    }
    setDraft(screen, result.node)
    say(what + draftNote(), false)
    keepSelection()
  }

  function handleKey(key, text, modifiers) {
    if (prompting) return handlePrompt(key, text, modifiers)
    if (text === "[" || text === "]") goWorkspace(Workspaces.step(workspace, text === "]" ? 1 : -1, Workspaces.count(state)))
    else if (Workspaces.ofDigit(text, Workspaces.count(state)) !== null) goWorkspace(Workspaces.ofDigit(text, Workspaces.count(state)))
    else if (text === "-") goWorkspace("default")
    else if (text === "u" && !slotFocus) startDropOverride()
    else if (slotFocus) return handleSlotKey(key, text)
    else if (text === "s") focusSlots(true)
    else return handlePictureKey(key, text)
    return true
  }

  function handlePictureKey(key, text) {
    var arrow = arrowOf(key)
    if (arrow !== "") select(arrow)
    else if (moveKeys[text]) scoped(function() { root.moveSelected(root.moveKeys[text], false) }, true)
    else if (forceKeys[text]) scoped(function() { root.moveSelected(root.forceKeys[text], true) }, true)
    else if (text === "/") {
      // flip is for tiles: refused on a scroll tree before anything asks
      if (Layout.flipError(activeNode) !== "") say(Layout.flipError(activeNode), true)
      else scoped(function() { root.edit(function(n) { return { node: Layout.flip(n) } }, "Flipped every split.") }, true)
    }
    else if (text === "t") scoped(cycleScroll, true)
    else if (text === "o") toggleOther()
    else if (text === "r") {
      // ratios are for tiles: refused on a scroll tree before anything asks
      if (activeNode && activeNode.kind === "scroll") say(Layout.ratioPrompt(activeNode).error, true)
      else scoped(startRatio, true)
    }
    else if (text === "w") apply(null)
    else if (text === "d") scoped(startRevert, false)
    else if (text === "R") scoped(startRecord, false)
    else return false
    return true
  }

  // An edit on a workspace that uses the shared trees asks first whom it is
  // for: (a)ll workspaces edits the shared trees, (o)nly this one gives it
  // its own on w. `action` runs once answered (straight away when there is
  // nothing to ask, or it would refuse or do nothing: `needsNode` with no
  // tree selected).
  function scoped(action, needsNode) {
    if (block !== "" || (needsNode && !activeNode) || !Layout.needsScope(state, layout, workspace, scope)) {
      action()
      return
    }
    var n = workspace
    var q = Layout.scopeQuestion(n)
    ask(Prompts.choice(q.label, q.options, { inline: true }), function(value) {
      if (root.workspace !== n) return
      root.scope = value
      root.say(value === "all" ? "Editing the shared tree: every workspace without its own follows."
        : "Editing workspace " + n + " only: w gives it its own trees.", false)
      action()
    })
  }

  // u: a workspace's own trees dropped, after y/n; it uses the shared ones
  // again (api drop_override).
  function startDropOverride() {
    if (refuseEdit()) return
    if (!Layout.hasOwn(state, layout, workspace)) {
      say(workspace === "default" ? "u drops a workspace's own trees: pick one with [ ] or its digit."
        : "Workspace " + workspace + " uses the shared tree already.", true)
      return
    }
    var n = workspace
    confirm("Drop workspace " + n + "'s own trees and use the shared tree?", function() {
      root.engine.call("drop_override", { layout: root.layout, workspace: n }, function(reply) {
        if (!reply.ok) {
          root.say(reply.error, true)
          return
        }
        if (root.workspace === n) {
          root.scope = ""
          root.drafts = ({})
          root.sync()
        }
        root.say("Workspace " + n + " uses the shared tree of " + reply.layout + " again. Ctrl+S saves.", false)
      })
    })
  }

  // t: tiles -> scroll half -> scroll full -> tiles (Layout.cycleScroll).
  function cycleScroll() {
    var what = { tiles: "Tiles again.", half: "Scrolling, each column half the screen (h/l move them).",
      full: "Scrolling, each column the full screen (h/l move them)." }
    if (!activeNode) return
    var result = Layout.cycleScroll(activeNode)
    edit(function() { return result }, result.node ? what[Layout.scrollMode(result.node)] || "" : "")
  }

  // --- the slot list ---------------------------------------------------------

  function handleSlotKey(key, text) {
    if (key === Qt.Key_Up || text === "k") selectSlot(slotIndex - 1)
    else if (key === Qt.Key_Down || text === "j") selectSlot(slotIndex + 1)
    else if (text === "a") startNewSlot(null)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) showSelectedSlot()
    else if (text === "r") startRenameSlot()
    else if (text === "e") startDescribeSlot()
    else if (text === "d") startDeleteSlot()
    else if (text === "s" || key === Qt.Key_Escape) focusSlots(false)
    else return false
    return true
  }

  function focusSlots(on) {
    slotFocus = on
    if (on && selectedSlot === "" && slotRows.length) selectedSlot = slotRows[0].slot
    message = ""
  }

  function indexOfSlot(name) {
    for (var i = 0; i < slotRows.length; i++) if (slotRows[i].slot === name) return i
    return slotRows.length > 0 ? 0 : -1
  }

  function selectSlot(index) {
    if (slotRows.length === 0) return
    var i = Math.max(0, Math.min(slotRows.length - 1, index))
    selectedSlot = slotRows[i].slot
    slotList.positionViewAtIndex(i, ListView.Contain)
  }

  function slotsEditable() {
    if (slotsReadOnly === "") return true
    say(slotsReadOnly, true)
    return false
  }

  function needSlot() {
    if (slotRow) return true
    say("There are no slots yet; a makes one.", true)
    return false
  }

  // Return: the selected slot selected in the picture, where this
  // workspace's trees have it (every tree has every slot), the keys back to
  // the picture to move it.
  function showSlot(name) {
    var where = null
    for (var k in drafts) {
      var d = drafts[k]
      if (d && d.node && Layout.leaves(pictureOf(d.node)).indexOf(name) >= 0) where = where === null ? k : where
    }
    if (where === null) {
      say(name + " is in no tree of " + workspaceName(workspace) + " yet.", true)
      return
    }
    screen = where
    selectedKey = name
    slotFocus = false
    say(name + " is on screen " + where + ": hjkl move it.", false)
  }

  function showSelectedSlot() {
    if (!needSlot()) return
    showSlot(slotRow.slot)
  }

  // a: a new global slot, a name and then an optional description; the
  // engine puts it into every tree (an empty slot takes no room), and edited
  // drafts follow on the next state read (sync).
  function startNewSlot(values) {
    if (!slotsEditable()) return
    values = values || { name: "", description: "", error: "" }
    ask(Prompts.withError(Prompts.text(Slots.newSlotLabel(), { value: values.name, required: true }), values.error),
      function(name) {
        root.ask(Prompts.text("Description, optional [Enter] add  [Esc] cancel: ", { value: values.description }),
          function(description) {
            root.engine.call("add_slot", { slot: name.trim(), description: description }, function(reply) {
              if (!reply.ok) {
                root.startNewSlot({ name: name, description: description, error: reply.error })
                return
              }
              root.selectedSlot = reply.slot
              root._newSlot = reply.slot
              root.say(Slots.addedText(reply.slot), false)
            })
          })
      })
  }

  // Every edited draft follows a slot edit the engine made to the trees in
  // force (unedited ones take the engine's trees on the re-read).
  function editDrafts(fn) {
    var next = Object.assign({}, drafts)
    for (var k in next) {
      var d = next[k]
      if (d && d.node && edited(k)) next[k] = { node: fn(d.node), base: d.base }
    }
    drafts = next
  }

  function startRenameSlot() {
    if (!needSlot() || !slotsEditable()) return
    var old = slotRow.slot
    var label = "Rename '" + old + "' to (every tree and workspace follows) [Enter] save  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      if (to === old) return
      root.engine.call("rename_slot", { slot: old, to: to }, function(reply) {
        if (!reply.ok) {
          root.ask(Prompts.withError(Prompts.text(label, { value: to, required: true }), reply.error), answer)
          return
        }
        root.selectedSlot = reply.to
        root.editDrafts(function(n) { return Layout.renameSlot(n, old, reply.to) })
        if (root.selectedKey === old) root.selectedKey = reply.to
        var specs = reply.specs || []
        root.say("Renamed '" + old + "' to '" + reply.to + "'."
          + (reply.trees > 0 ? " Rewrote " + reply.trees + (reply.trees === 1 ? " tree." : " trees.") : "")
          + (specs.length ? " Its assignments on workspace" + (specs.length > 1 ? "s " : " ") + specs.join(", ") + " follow." : ""),
          false)
      })
    }
    ask(Prompts.text(label, { required: true }), answer)
  }

  function startDescribeSlot() {
    if (!needSlot() || !slotsEditable()) return
    var slot = slotRow.slot
    ask(Prompts.text("Description for '" + slot + "' (empty removes it) [Enter] save  [Esc] cancel: ",
      { value: slotRow.description }), function(text) {
      root.engine.call("describe_slot", { slot: slot, description: text }, function(reply) {
        if (!reply.ok) root.say(reply.error, true)
        else root.say(text === "" ? "Cleared the description of '" + slot + "'." : "Described '" + slot + "'.", false)
      })
    })
  }

  function startDeleteSlot() {
    if (!needSlot() || !slotsEditable()) return
    var row = slotRow
    confirm(Slots.deleteQuestion(row), function() {
      root.engine.call("remove_slot", { slot: row.slot, force: Slots.inUse(row) }, function(reply) {
        if (!reply.ok) {
          root.say(reply.error, true)
          return
        }
        root.editDrafts(function(n) {
          var out = Layout.leaves(n).indexOf(row.slot) >= 0 ? Layout.removeSlot(n, row.slot).node : n
          return out
        })
        root.keepSelection()
        root.say("Deleted slot '" + row.slot + "'.", false)
      })
    })
  }

  // o: show or hide where other windows go. It changes no tree.
  function toggleOther() {
    showOther = !showOther
    if (showOther && activeNode) selectedKey = "*"
    keepSelection()
    say(showOther ? "Showing where other windows (windows not assigned to a slot) go: hjkl move it."
      : "Other windows hidden from the picture; they still go where the tree puts them.", false)
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
      setDraft(screen, Layout.clearRatios(activeNode))
      say("Ratios cleared — equal shares everywhere." + draftNote(), false)
      return
    }
    var result = Layout.applyRatio(activeNode, entry)
    if (result.error) {
      ask(Prompts.withError(Prompts.text(Layout.ratioPrompt(activeNode).text, { value: input }), result.error), submitRatio)
      return
    }
    setDraft(screen, result.node)
    say("Set ratios " + Layout.ratio(result.node) + "." + draftNote(), false)
  }

  // A y/n question; action() runs on y.
  function confirm(text, action) {
    ask(Prompts.confirm(text), function(yes) {
      if (yes) action()
      else root.message = ""
    })
  }

  // [ ] and the digits: another workspace of the same layout, `-` its default
  // trees (the arrows stay the picture's).
  function goWorkspace(n) {
    if (!state || n === null) return
    if (n === workspace) {
      say("Editing " + workspaceName(workspace) + " already.", false)
      return
    }
    var dropped = editedScreens()
    workspace = n
    scope = ""
    drafts = ({})
    screen = ""
    selectedKey = ""
    sync()
    var note = Layout.defaultNote(state, layout, workspace)
    say("Editing " + workspaceName(workspace) + " of " + (layout || "no layout") + "." + (note ? " " + note : "")
      + (dropped.length ? " Unapplied edits dropped (screen " + dropped.join(", ") + ")." : ""), dropped.length > 0)
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

  // w: every edited pane of the workspace in one set_trees. `then` runs after it
  // worked (Ctrl+S's save, through applyThen).
  function apply(then) {
    if (refuseEdit()) return
    var keys = editedScreens()
    if (keys.length === 0) {
      if (then) then()
      else say("Nothing to apply: the trees are what the engine runs.", false)
      return
    }
    var trees = {}
    for (var i = 0; i < keys.length; i++) {
      var d = drafts[keys[i]]
      if (!d.node) {
        say("Screen " + keys[i] + " has no tree left; the engine cannot drop a screen's tree.", true)
        return
      }
      trees[keys[i]] = Layout.format(d.node)
    }
    if (!engine) return
    say("Applying screen " + keys.join(", ") + "…", false)
    engine.call("set_trees", { layout: layout, workspace: target(), trees: trees }, function(reply) {
      if (!reply.ok) {
        root.say(reply.error, true)
        return
      }
      if (reply.layout === root.layout && String(reply.workspace) === String(root.target())) {
        var next = Object.assign({}, root.drafts)
        for (var k in reply.trees) {
          var parsed = Layout.parse(reply.trees[k].tree)
          next[k] = { node: parsed.node, base: reply.trees[k].tree }
        }
        root.drafts = next
        root.keepSelection()
      }
      var parts = []
      for (var k2 in reply.trees) parts.push("screen " + k2 + " " + reply.trees[k2].tree)
      root.say("Applied " + root.workspaceName(reply.workspace) + " of " + reply.layout + ": " + parts.join(", ")
        + (then ? "" : ". Ctrl+S saves."), false)
      if (then) then()
    })
  }

  // Ctrl+S (the panel's): apply the edited panes first, then `then()`
  // saves. With nothing edited it saves straight away.
  function applyThen(then) {
    if (editedScreens().length === 0) then()
    else apply(then)
  }

  // d: the selected screen's tree back to how it was last saved, after
  // y/n (api reset): its draft and its applied but unsaved edits go.
  function startRevert() {
    if (refuseEdit()) return
    var k = screen
    var into = target()
    confirm(Layout.revertQuestion(into, k), function() {
      root.engine.call("reset", { layout: root.layout, workspace: into, screen: parseInt(k, 10) }, function(reply) {
        if (!reply.ok) {
          root.say(reply.error, true)
          return
        }
        var next = Object.assign({}, root.drafts)
        next[k] = { node: reply.tree ? Layout.parse(reply.tree).node : null, base: reply.tree || null }
        root.drafts = next
        root.keepSelection()
        root.say(Layout.revertedText(into, k, reply.tree), false)
      })
    })
  }

  // The bar widget's Record: R on the focused workspace and screen (the
  // view opens on All workspaces, which R does not record).
  function recordFocused() {
    if (state) {
      var t = Layout.initialTarget(state, focusedWorkspace)
      if (t.workspace !== workspace) {
        workspace = t.workspace
        scope = ""
        drafts = ({})
        selectedKey = ""
      }
      screen = String(t.screen)
      sync()
    }
    scoped(startRecord, false)
  }

  function workspaceIdOf(n, k) {
    var ws = state && state.workspaces ? state.workspaces : {}
    for (var id in ws) if (ws[id].workspace === n && String(ws[id].screen) === k) return parseInt(id, 10)
    return -1
  }

  // R: measure the windows on the screen, show the tree it makes and what
  // it would drop, apply only when confirmed.
  function startRecord() {
    if (refuseEdit()) return
    if (workspace === "default") {
      say("R records a workspace's windows: pick one with [ ] or its digit.", true)
      return
    }
    var id = workspaceIdOf(workspace, screen)
    if (id < 0) {
      say("Workspace " + workspace + " is not on screen " + screen + ".", true)
      return
    }
    say("Recording workspace " + id + "…", false)
    engine.call("record", { workspace_id: id, apply: false }, function(reply) {
      if (!reply.ok) {
        root.say(reply.error, true)
        return
      }
      var missing = reply.missing || []
      var text = "Recorded " + reply.tree + " (" + reply.ratio + ") from workspace " + reply.workspace_id
        + (missing.length ? "; missing " + missing.join(", ") + ": applying drops " + (missing.length === 1 ? "it" : "them")
          + " from the tree" : "") + ". Apply it?"
      root.confirm(text, function() {
        var r = String(reply.screen)
        var trees = {}
        trees[r] = reply.tree
        root.engine.call("set_trees", { layout: reply.layout, workspace: root.scope === "all" ? "default" : reply.workspace,
          trees: trees }, function(set) {
          if (!set.ok) {
            root.say(set.error, true)
            return
          }
          var next = Object.assign({}, root.drafts)
          next[r] = { node: Layout.parse(set.trees[r].tree).node, base: set.trees[r].tree }
          root.drafts = next
          root.keepSelection()
          root.say("Applied the recorded tree " + set.trees[r].tree + ". Ctrl+S saves.", false)
        })
      })
    })
  }

  // --- for scripts and the e2e smoke ----------------------------------------

  // "<screen> <leaf>", or "slots <name>" while the keys are the slot list's.
  function selectionText() {
    return slotFocus ? "slots " + selectedSlot : screen + " " + selectedKey
  }

  // The draft trees, "1: h[a, b]; 2: c" (edited ones marked *).
  function draftText() {
    return currentPanes().map(function(p) {
      var d = root.drafts[p.key]
      return p.key + ": " + (d && d.node ? Layout.format(d.node) : "-") + (root.edited(p.key) ? " *" : "")
    }).join("; ")
  }

  // The panes' titles, "Screen 1 · HEADLESS-2 (...)" joined by " | ": for the e2e smoke.
  function paneTitles() {
    return currentPanes().map(function(p) { return Layout.screenLabel(root.state, p.screen) }).join(" | ")
  }

  // The header as it reads: the workspace strip, the current one in
  // brackets ("All workspaces · 1 2 [3•] ..."), then the note on a workspace
  // that uses the shared trees: for the e2e smoke.
  function headerLine() {
    var note = Layout.defaultNote(state, layout, workspace, scope)
    return stripText() + (note ? "   " + note : "")
  }

  function stripText() {
    return Workspaces.stripLine(Workspaces.strip(state, layout, workspace))
  }

  // What a pane's picture is, "tiles" or "scroll · half"..., for the e2e
  // smoke: "1: scroll · half; 2: tiles".
  function modeText() {
    return currentPanes().map(function(p) {
      var d = root.drafts[p.key]
      return p.key + ": " + (d && d.node ? Layout.modeLabel(d.node) : "-")
    }).join("; ")
  }

  // --- drawing --------------------------------------------------------------

  function aspectOf(connector) {
    var list = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      if (m && m.name === connector && m.width > 0 && m.height > 0) return m.width / m.height
    }
    return 16 / 9
  }

  readonly property int gap: Style.spacing.md
  // other windows' place: drawn dim, beside the slots
  readonly property color otherColor: Commons.Color.muted

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    // Header: the workspace switcher, "WORKSPACE  All workspaces · 1 2
    // 3• ..." (All workspaces: the layout's shared trees, -; the workspaces
    // by their keys, [ ] step, the digits jump; a dot on one with trees of
    // its own, the ones using the shared trees dimmer); a note on a
    // workspace that uses them; at the right, edits the engine does not run
    // yet.
    Item {
      id: headerBox
      width: parent.width
      height: workspaceStrip.height
      WorkspaceSwitcher {
        id: workspaceStrip
        x: Tokens.textInset
        anchors.verticalCenter: parent.verticalCenter
        entries: Workspaces.strip(root.state, root.layout, root.workspace)
        onPicked: function(workspace) { root.goWorkspace(workspace) }
      }
      InfoText {
        anchors.left: workspaceStrip.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: editedMark.left
        anchors.rightMargin: Style.spacing.md
        anchors.verticalCenter: parent.verticalCenter
        elide: Text.ElideRight
        text: Layout.defaultNote(root.state, root.layout, root.workspace, root.scope)
      }
      InfoText {
        id: editedMark
        anchors.right: parent.right
        anchors.rightMargin: Tokens.cellPadding
        anchors.verticalCenter: parent.verticalCenter
        visible: root.editedScreens().length > 0
        urgent: true
        text: visible ? "edited, not applied (w)" : ""
      }
    }

    // Other desks share this layout: an edit here changes it for them too.
    InfoText {
      id: sharedNote
      width: parent.width
      leftPadding: Tokens.textInset
      visible: root.sharedWith.length > 0
      wrapMode: Text.WordWrap
      text: DesksLayouts.sharedNote(root.sharedWith)
    }

    // Why the trees cannot be edited, or the engine cannot be reached.
    ProblemText {
      id: problem
      width: parent.width
      text: {
        if (!root.engine) return "No engine service."
        if (root.engine.error !== "") return root.engine.error
        if (root.state && root.state.config_error) return "config error: " + root.state.config_error
        return root.state && root.block !== "" ? "Read only: " + root.block + "." : ""
      }
    }

    // The panes, side by side (a scale model of each screen), and the slot
    // list beside them.
    Row {
      id: body
      width: parent.width
      height: parent.height - headerBox.height - (problem.visible ? problem.height + parent.spacing : 0)
        - (sharedNote.visible ? sharedNote.height + parent.spacing : 0)
        - parent.spacing
      spacing: root.gap * 2

      Row {
        id: paneRow
        width: body.width - slotPanel.width - body.spacing
        height: body.height
        spacing: root.gap

        Repeater {
          model: root.paneList
          delegate: Column {
            id: pane
            required property var modelData
            required property int index
            readonly property var draft: root.drafts[modelData.key] || null
            readonly property var node: draft ? draft.node : null
            readonly property bool active: modelData.key === root.screen
            readonly property bool changed: root.edited(modelData.key)
            width: (paneRow.width - root.gap * (root.paneList.length - 1)) / Math.max(1, root.paneList.length)
            height: paneRow.height
            spacing: Style.spacing.sm

            PaneTitle {
              id: paneTitle
              width: parent.width
              leftPadding: Tokens.textInset
              // the keys' pane: not while the slot list has them
              active: pane.active && !root.slotFocus
              text: Layout.screenLabel(root.state, pane.modelData.screen)
                + (pane.changed ? "   edited" : "") + (pane.modelData.resized && !pane.changed ? "   keyboard-resized" : "")
            }

            // The picture, fitted to the screen's aspect.
            Item {
              id: frame
              width: parent.width
              height: parent.height - paneTitle.height - parent.spacing
              readonly property real aspect: root.aspectOf(pane.modelData.connector)
              readonly property int boxW: Math.floor(Math.min(width, height * aspect))
              readonly property int boxH: Math.floor(Math.min(height, width / aspect))
              // the tree as drawn (o: with other windows' place or not)
              readonly property var picture: pane.node ? Layout.picture(pane.node, root.showOther) : null
              readonly property bool scrolls: !!picture && picture.kind === "scroll"
              readonly property var titles: Layout.titles(root.state, root.workspace, pane.modelData.screen)

              // Tiles: boxes in a scale model of the screen.
              Rectangle {
                id: screenBox
                visible: !frame.scrolls
                x: Math.floor((frame.width - frame.boxW) / 2)
                width: frame.boxW
                height: frame.boxH
                radius: Style.cornerRadius
                color: "transparent"
                // the keys' side: the picture's frame steps back while the slot list has them
                border.width: pane.active && !root.slotFocus ? 2 : 1
                border.color: pane.active ? Commons.Util.alpha(Commons.Color.accent, root.slotFocus ? 0.5 : 1)
                  : Commons.Util.alpha(root.foreground, 0.35)

                Placeholder {
                  anchors.centerIn: parent
                  width: parent.width - Style.spacing.md * 2
                  visible: pane.node === null
                  text: root.workspace === "default" || !Layout.hasOwn(root.state, root.layout, root.workspace)
                    ? "No shared tree on this screen"
                    : "No tree for workspace " + root.workspace + " here"
                }

                Repeater {
                  model: frame.picture && !frame.scrolls ? Layout.rects(frame.picture, { x: 0, y: 0, w: screenBox.width - 8, h: screenBox.height - 8 }, {
                    pad: 5,
                    title: Style.font.bodySmall + 6,
                    selected: pane.active ? root.selectedKey : "",
                    titles: frame.titles,
                  }) : []
                  delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property bool isLeaf: modelData.kind === "slot" || modelData.kind === "overflow"
                    readonly property bool isOther: modelData.kind === "overflow"
                    readonly property bool isContainer: !isLeaf
                    readonly property bool picked: !!modelData.selected
                    x: 4 + modelData.x + 2
                    y: 4 + modelData.y + 2
                    width: Math.max(0, modelData.w - 4)
                    height: Math.max(0, modelData.h - 4)
                    radius: Style.cornerRadius
                    color: picked && isLeaf ? root.selectedBackground
                      : isLeaf ? Commons.Util.alpha(isOther ? root.otherColor : root.foreground, isOther ? 0.04 : 0.06)
                      : "transparent"
                    border.width: picked ? 2 : 1
                    border.color: picked ? Commons.Color.accent
                      : isOther ? Commons.Util.alpha(root.otherColor, 0.45)
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
                      color: root.foreground
                      opacity: 0.75
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      font.italic: true
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
                          : cell.isOther ? root.otherColor : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: !cell.isOther
                        font.italic: cell.isOther
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
                        root.screen = pane.modelData.key
                        root.selectedKey = cell.modelData.key
                      }
                    }
                  }
                }
              }

              // A scroll tree: a filmstrip. Its columns, half or full screen
              // width, in slot order; the screen a viewport over them,
              // scrolled to the selected column, a third of the picture's
              // width so a screen's width of the strip shows on each side;
              // columns beyond it faded.
              Item {
                id: film
                visible: frame.scrolls
                anchors.fill: parent
                clip: true
                readonly property int labelHeight: filmLabel.implicitHeight + Style.spacing.xs
                // between neighbouring columns, half of it each side
                readonly property int gap: Math.max(2, Style.spacing.xs)
                readonly property var strip: frame.scrolls
                  ? Layout.filmstrip(frame.picture, { x: 0, y: labelHeight, w: width, h: height - labelHeight }, {
                    aspect: frame.aspect,
                    span: 3,
                    selected: pane.active ? root.selectedKey : "",
                    titles: frame.titles,
                  })
                  : null

                // what it is, quietly, over the screen: "scroll · half"
                InfoText {
                  id: filmLabel
                  x: film.strip ? film.strip.viewport.x : 0
                  y: film.strip ? Math.max(0, film.strip.viewport.y - implicitHeight - Style.spacing.sm) : 0
                  text: film.strip ? film.strip.label : ""
                  font.italic: true
                }

                Repeater {
                  model: film.strip ? film.strip.columns : []
                  delegate: Rectangle {
                    id: column
                    required property var modelData
                    readonly property bool isOther: modelData.kind === "overflow"
                    readonly property bool picked: !!modelData.selected
                    readonly property bool onScreen: modelData.visible > 0.999
                    // the part of it the pane shows (a column beyond the
                    // screen peeks in at the side): its label goes there
                    readonly property real shownLeft: Math.max(x, 0)
                    readonly property real shownRight: Math.min(x + width, film.width)
                    x: modelData.x + film.gap
                    y: modelData.y + film.gap
                    width: Math.max(0, modelData.w - film.gap * 2)
                    height: Math.max(0, modelData.h - film.gap * 2)
                    radius: Style.cornerRadius
                    opacity: onScreen ? 1 : 0.45
                    color: picked ? root.selectedBackground
                      : Commons.Util.alpha(isOther ? root.otherColor : root.foreground, isOther ? 0.04 : 0.06)
                    border.width: picked ? 2 : 1
                    border.color: picked ? Commons.Color.accent
                      : isOther ? Commons.Util.alpha(root.otherColor, 0.45)
                      : Commons.Util.alpha(root.foreground, 0.5)

                    Column {
                      x: column.shownLeft - column.x + Style.spacing.sm
                      anchors.verticalCenter: parent.verticalCenter
                      width: Math.max(0, column.shownRight - column.shownLeft - Style.spacing.sm * 2)
                      Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: column.modelData.label
                        color: column.picked ? root.selectedText
                          : column.isOther ? root.otherColor : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: !column.isOther
                        font.italic: column.isOther
                      }
                      Text {
                        width: parent.width
                        visible: !!column.modelData.title
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        text: column.modelData.title || ""
                        color: column.picked ? root.selectedText : root.foreground
                        opacity: 0.55
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                      }
                    }

                    MouseArea {
                      anchors.fill: parent
                      onClicked: {
                        root.screen = pane.modelData.key
                        root.selectedKey = column.modelData.key
                      }
                    }
                  }
                }

                // the screen: a viewport over the strip, just outside the
                // columns it shows
                Rectangle {
                  x: film.strip ? film.strip.viewport.x - 2 : 0
                  y: film.strip ? film.strip.viewport.y - 2 : 0
                  width: film.strip ? film.strip.viewport.w + 4 : 0
                  height: film.strip ? film.strip.viewport.h + 4 : 0
                  radius: Style.cornerRadius
                  color: "transparent"
                  border.width: pane.active && !root.slotFocus ? 2 : 1
                  border.color: pane.active ? Commons.Util.alpha(Commons.Color.accent, root.slotFocus ? 0.5 : 1)
                    : Commons.Util.alpha(root.foreground, 0.35)
                }
              }
            }
          }
        }
      }

      // The global slots, by name: the name and the description, nothing
      // else. s moves the keys here (the border says so) and back.
      Rectangle {
        id: slotPanel
        width: Math.max(Style.space(190), Math.floor(body.width * 0.22))
        height: body.height
        radius: Style.cornerRadius
        color: root.slotFocus ? Commons.Util.alpha(Commons.Color.accent, 0.06) : "transparent"
        border.width: root.slotFocus ? 2 : 1
        border.color: root.slotFocus ? Commons.Color.accent : Commons.Util.alpha(root.foreground, 0.25)

        Column {
          anchors.fill: parent
          anchors.margins: Style.spacing.md
          spacing: Style.spacing.sm

          Item {
            id: slotTitle
            width: parent.width
            height: slotTitleText.implicitHeight
            PaneTitle {
              id: slotTitleText
              anchors.left: parent.left
              active: root.slotFocus
              text: "Slots"
            }
            InfoText {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.slotFocus ? "s / Esc: back" : "s: edit"
            }
          }

          ListView {
            id: slotList
            width: parent.width
            height: parent.height - slotTitle.height - parent.spacing
            clip: true
            spacing: Style.spacing.xs
            model: root.slotRows
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: root.slotIndex

            delegate: TableRow {
              id: slotItem
              required property var modelData
              required property int index
              readonly property bool current: index === root.slotIndex
              readonly property bool lit: current && root.slotFocus
              width: ListView.view.width
              height: slotLines.implicitHeight + Style.spacing.sm * 2
              selected: lit
              marked: current && !root.slotFocus
              onClicked: {
                root.selectedSlot = slotItem.modelData.slot
                root.focusSlots(true)
              }

              Column {
                id: slotLines
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.cellPadding
                anchors.rightMargin: Tokens.cellPadding
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  text: slotItem.modelData.slot
                  color: slotItem.lit ? root.selectedText : Commons.Color.accent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  width: parent.width
                  visible: slotItem.modelData.description !== ""
                  textFormat: Text.PlainText
                  wrapMode: Text.WordWrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  text: slotItem.modelData.description
                  color: slotItem.lit ? root.selectedText : root.foreground
                  opacity: 0.7
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            Placeholder {
              anchors.centerIn: parent
              width: parent.width
              visible: root.slotRows.length === 0
              text: root.state ? "No slots yet — s, then a, makes one (left, main, right…)" : ""
            }
          }
        }
      }
    }
  }
}
