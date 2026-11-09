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

// One workspace's trees in the active desk's layout, edited (aerolayout's
// LayoutView). A pane per screen 1..N of the layout, labelled with the
// active desk's monitor at that position, each a scale model of it: boxes proportional
// to the weights, nested containers titled with their kind and ratio, a
// scroll branch as a filmstrip of its numbered full-width columns in order
// (no tabs: Hyprland's scrolling layout, not a group), then the tree text and ratio
// string. Edits go to a draft; `w` applies it (api set_trees), Ctrl+S (the
// panel's) applies it and saves (api save), `d` puts a screen's tree back
// to what slots.lua holds (api reset), `R` records the windows on screen
// (api record, previewed). It opens on "All workspaces" (`-`): the layout's
// shared (default) trees, which every workspace with none of its own uses;
// [ ] and the digits change the workspace (Workspaces.js; a dot marks one
// with trees of its own). A workspace on the shared trees shows them, and
// its first edit asks whether it is for all workspaces (the shared trees)
// or only this one (w then gives it its own); `u` drops a workspace's own
// trees, back to the shared ones (api drop_override). `f` forks the layout
// (the active desk then uses the copy: other desks sharing the layout see
// every edit to it).
//
// Beside the picture, the global slots (aerolayout's logical slots), their
// names and descriptions: `s` moves the keys to that list and back (Esc
// too), where a makes a slot (name, then an optional description; api
// add_slot) and offers to put it in the tree at once, Return puts the
// selected one in the tree after the selected leaf, r renames it everywhere
// (rename_slot), e describes it (describe_slot), d deletes it after y/n
// naming the trees and workspaces it goes from (remove_slot). The models are
// Layout.js and Slots.js; the calls are in docs/design.md §9.
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
  // The layout the view follows changes under it (a, f, x in the Desks &
  // Desk tab, a hotplug): edited drafts are dropped, except after this
  // view's own fork (the copy is the same trees).
  property bool _keepDrafts: false

  readonly property var paneList: Layout.panes(state, layout, workspace)
  // The same, computed now: a handler running on a state change can see the
  // binding above before it has caught up.
  function currentPanes() {
    return Layout.panes(state, layout, workspace)
  }
  // screen key -> { node (the draft, null when the screen has no tree), base
  // (the tree text in force it started from), memory (a parked overflow leaf) }
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
    var workspaceKeys = { title: "Workspace", items: [{ key: "[ ]", label: "prev/next" }, { key: Workspaces.jumpKeys(Workspaces.count(state)), label: "jump" },
      { key: "-", label: "all workspaces (the shared tree)" }] }
    if (slotFocus) {
      return Help.row([
        { title: "Slot list", items: [{ key: "↑/↓", label: "select" }, { key: "a", label: "new" },
          { key: "Return", label: "put in " + (screen ? "screen " + screen + "'s" : "the") + " tree" },
          { key: "r", label: "rename" }, { key: "e", label: "describe" }, { key: "d", label: "delete" }] },
        [{ key: "s/Esc", label: "back to the screens" }],
        workspaceKeys,
        [{ key: "Ctrl+S", label: "save" }],
        [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
      ], accent)
    }
    return Help.row([
      [{ key: "←↑↓→", label: "select" }],
      { title: "Tree", items: [{ key: "a", label: "add slot" }, { key: "x", label: "take out" }, { key: "hjkl", label: "move" },
        { key: "HJKL", label: "force move" }, { key: "/", label: "flip" }, { key: "t", label: toggleLabel },
        { key: "r", label: "ratios" }, { key: "o", label: "overflow" }] },
      { title: "Layout", items: [{ key: "w", label: "apply" }, { key: "Ctrl+S", label: "apply+save" },
        { key: "d", label: "back to slots.lua" }, { key: "R", label: "record" }, { key: "f", label: "fork" }]
          .concat(Layout.hasOwn(state, layout, workspace) ? [{ key: "u", label: "use the shared tree" }] : []) },
      [{ key: "s", label: "slot list" }],
      workspaceKeys,
      [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
    ], accent)
  }

  // t turns the whole tree into a scroll branch (full-width scrolling
  // columns in order) and back.
  readonly property string toggleLabel: activeNode && activeNode.kind === "scroll" ? "tiles" : "scroll"

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
  // tree; an edited one keeps the edit. Keep the selection on a leaf. When
  // the active desk's layout changes (another applied, a fork, a rename, a
  // hotplug), follow it.
  function sync() {
    var now = state && state.layout ? state.layout : ""
    if (state && now !== layout) {
      var was = layout
      var dropped = _keepDrafts ? [] : editedScreens()
      layout = now
      if (!_keepDrafts) drafts = ({})
      if (was !== "" && !_keepDrafts) {
        say((now !== "" ? "The active desk uses layout '" + now + "' now; editing it." : "No desk is active: nothing to edit.")
          + (dropped.length ? " Unapplied edits dropped (screen " + dropped.join(", ") + ")." : ""), dropped.length > 0)
      }
      _keepDrafts = false
    }
    var next = {}
    var list = currentPanes()
    for (var i = 0; i < list.length; i++) {
      var p = list[i]
      var d = drafts[p.key]
      if (d && edited(p.key)) {
        next[p.key] = { node: d.node, base: p.tree, memory: d.memory }
      } else {
        var parsed = p.tree !== null ? Layout.parse(p.tree) : { node: null }
        next[p.key] = { node: parsed.node || null, base: p.tree, memory: d && d.base === p.tree ? d.memory : null }
      }
    }
    drafts = next
    keepSelection()
  }

  function keepSelection() {
    var list = currentPanes()
    if (screen === "" || !drafts[screen]) screen = list.length ? list[0].key : ""
    var draft = drafts[screen]
    var node = draft ? draft.node : null
    if (node && Layout.leaves(node).indexOf(selectedKey) >= 0) return
    if (!node) {
      // the selection is on a screen with no tree: move to one that has one
      for (var i = 0; i < list.length; i++) {
        var d = drafts[list[i].key]
        if (d && d.node) {
          screen = list[i].key
          node = d.node
          break
        }
      }
    }
    selectedKey = node ? Layout.leaves(node)[0] : ""
  }

  function setDraft(k, node, memory) {
    var next = Object.assign({}, drafts)
    var old = drafts[k] || { base: null }
    next[k] = { node: node, base: old.base, memory: memory === undefined ? old.memory : memory }
    drafts = next
  }

  function draftNote() {
    return " Not applied: w applies, Ctrl+S applies and saves."
      + (sharedWith.length ? " Desk" + (sharedWith.length > 1 ? "s " : " ") + sharedWith.join(", ") + " share" + (sharedWith.length > 1 ? "" : "s")
        + " this layout: f forks it first." : "")
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
    var next = Layout.navigate(activeNode, selectedKey, direction)
    if (next !== null) {
      selectedKey = next
      return
    }
    var other = neighbourPane(direction)
    if (!other || !drafts[other.key] || !drafts[other.key].node) return
    var keys = Layout.leaves(drafts[other.key].node)
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
    var result = forced ? Layout.forceMove(activeNode, selectedKey, direction) : Layout.move(activeNode, selectedKey, direction)
    if (result.error) {
      say(result.error, true)
      return
    }
    if (result.changed) {
      setDraft(screen, result.node)
      say("Moved " + selectedKey + "." + draftNote(), false)
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
    next[screen] = { node: crossed.source, base: drafts[screen].base, memory: drafts[screen].memory }
    var old = drafts[other.key] || { base: null, memory: null }
    next[other.key] = { node: crossed.target, base: old.base, memory: old.memory }
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
    setDraft(screen, result.node, result.memory)
    say(what + draftNote(), false)
    keepSelection()
  }

  function handleKey(key, text, modifiers) {
    if (prompting) return handlePrompt(key, text, modifiers)
    if (text === "[" || text === "]") goWorkspace(Workspaces.step(workspace, text === "]" ? 1 : -1, Workspaces.count(state)))
    else if (Workspaces.ofDigit(text, Workspaces.count(state)) !== null) goWorkspace(Workspaces.ofDigit(text, Workspaces.count(state)))
    else if (text === "-") goWorkspace("default")
    else if (text === "f") startFork()
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
    else if (text === "/") scoped(function() { root.edit(function(n) { return { node: Layout.flip(n) } }, "Flipped every split.") }, true)
    else if (text === "t") scoped(function() {
      root.edit(function(n) { return Layout.toggleScroll(n) },
        root.toggleLabel === "tiles" ? "Tiled again." : "Scrolling: full-width columns in this order (hl move them).")
    }, true)
    else if (text === "o") scoped(toggleOverflow, true)
    else if (text === "a") scoped(startAddSlot, false)
    else if (text === "x") scoped(removeSelected, true)
    else if (text === "r") scoped(startRatio, true)
    else if (text === "w") apply(null)
    else if (text === "d") scoped(startReset, false)
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

  // a: one of the global slots no pane of this workspace places yet, added after
  // the selected leaf (or as the tree of a screen that has none).
  function startAddSlot() {
    if (refuseEdit() || screen === "") return
    var names = Layout.slotChoices(state, drafts)
    if (names.length === 0) {
      say("Every slot is placed on " + workspaceName(workspace) + " already; s, then a, makes a new one.", true)
      return
    }
    var k = screen
    ask(Prompts.choice("Add slot to screen " + k, Prompts.options(names)), function(name) {
      var result = Layout.addSlot(root.drafts[k] ? root.drafts[k].node : null, root.selectedKey, name)
      if (result.error) {
        root.say(result.error, true)
        return
      }
      root.setDraft(k, result.node)
      root.screen = k
      root.selectedKey = name
      root.say("Added " + name + " to screen " + k + "." + root.draftNote(), false)
    })
  }

  // x: the selected slot out of this screen's tree (it stays a slot; the
  // slot list's d deletes slots).
  function removeSelected() {
    if (!activeNode || refuseEdit()) return
    var key = selectedKey
    var result = Layout.removeSlot(activeNode, key)
    if (result.error) {
      say(result.error, true)
      return
    }
    setDraft(screen, result.node)
    keepSelection()
    say("Took " + key + " out of screen " + screen + "." + draftNote(), false)
  }

  // --- the slot list ---------------------------------------------------------

  function handleSlotKey(key, text) {
    if (key === Qt.Key_Up || text === "k") selectSlot(slotIndex - 1)
    else if (key === Qt.Key_Down || text === "j") selectSlot(slotIndex + 1)
    else if (text === "a") startNewSlot(null)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) placeSelectedSlot()
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

  // Return (and a's offer): the slot into the selected screen's tree, after
  // the selected leaf, as a draft; the keys go back to the picture with it
  // selected, to move it where it belongs. A slot this workspace places already
  // is selected where it is.
  function placeSlot(name) {
    if (refuseEdit()) return
    if (screen === "") {
      say("Layout '" + layout + "' has no screens to put " + name + " on.", true)
      return
    }
    var where = Layout.placedIn(drafts, name)
    if (where !== null) {
      screen = where
      selectedKey = name
      slotFocus = false
      say(name + " is on screen " + where + " already: selected it there.", false)
      return
    }
    var r = screen
    var after = activeNode && Layout.leaves(activeNode).indexOf(selectedKey) >= 0 ? selectedKey : ""
    var result = Layout.addSlot(activeNode, selectedKey, name)
    if (result.error) {
      say(result.error, true)
      return
    }
    setDraft(r, result.node)
    selectedKey = name
    slotFocus = false
    say("Put " + name + " in screen " + r + "'s tree" + (after !== "" ? " after " + after : "")
      + " — hjkl move it." + draftNote(), false)
  }

  function placeSelectedSlot() {
    if (!needSlot()) return
    var name = slotRow.slot
    scoped(function() { root.placeSlot(name) }, false)
  }

  // a: a new global slot, a name and then an optional description; then,
  // when this workspace's trees may be edited, the offer to put it in the tree.
  function startNewSlot(values) {
    if (!slotsEditable()) return
    values = values || { name: "", description: "", error: "" }
    ask(Prompts.withError(Prompts.text("New slot name (every workspace's trees may place it) [Enter] next  [Esc] cancel: ",
      { value: values.name, required: true }), values.error), function(name) {
      root.ask(Prompts.text("Description, optional [Enter] add  [Esc] cancel: ", { value: values.description }),
        function(description) {
          root.engine.call("add_slot", { slot: name.trim(), description: description }, function(reply) {
            if (!reply.ok) {
              root.startNewSlot({ name: name, description: description, error: reply.error })
              return
            }
            root.selectedSlot = reply.slot
            root.offerPlace(reply.slot)
          })
        })
    })
  }

  function offerPlace(slot) {
    if (block !== "" || screen === "") {
      say("Added slot '" + slot + "'.", false)
      return
    }
    var after = activeNode && Layout.leaves(activeNode).indexOf(selectedKey) >= 0 ? " after " + selectedKey : ""
    ask(Prompts.confirm("Added slot '" + slot + "'. Put it in screen " + screen + "'s tree on " + workspaceName(workspace)
      + after + "?"),
      function(yes) {
        if (yes) root.scoped(function() { root.placeSlot(slot) }, false)
        else root.say("Added slot '" + slot + "'. Return puts it in a tree.", false)
      })
  }

  // Every edited draft follows a slot edit the engine made to the trees in
  // force (unedited ones take the engine's trees on the re-read).
  function editDrafts(fn) {
    var next = Object.assign({}, drafts)
    for (var k in next) {
      var d = next[k]
      if (d && d.node && edited(k)) next[k] = { node: fn(d.node), base: d.base, memory: d.memory }
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
          + (specs.length ? " Moved the specs of workspace" + (specs.length > 1 ? "s " : " ") + specs.join(", ") + "." : ""),
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

  function toggleOverflow() {
    if (!activeNode || refuseEdit()) return
    var memory = activeDraft.memory
    var result = Layout.toggleOverflow(activeNode, memory)
    if (result.error) {
      say(result.error, true)
      return
    }
    var scrolling = result.node.kind === "scroll"
    setDraft(screen, result.node, result.memory)
    if (!result.parked) selectedKey = "*"
    keepSelection()
    say((result.parked
      ? (scrolling ? "Overflow column parked — windows with no slot go after the columns."
        : "Overflow leaf parked — windows with no slot get a column at the right.")
      : (scrolling ? "Overflow column back — h/l move it among the columns to choose where they go."
        : "Overflow leaf back — move it like any node to choose where they go.")) + draftNote(), false)
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

  // f: fork the layout (the active desk then uses the copy, so editing it
  // leaves the other desks' alone); the edited drafts carry over to it.
  function startFork() {
    if (!state || layout === "") {
      say("No desk is active: there is no layout to fork.", true)
      return
    }
    var source = layout
    var label = "Fork layout '" + source + "' as [Enter] fork  [Esc] cancel: "
    var answer = function(to) {
      to = to.trim()
      root._keepDrafts = true
      root.engine.call("fork_layout", { layout: source, to: to }, function(reply) {
        if (!reply.ok) {
          root._keepDrafts = false
          root.ask(Prompts.withError(Prompts.text(label, { value: to, required: true }), reply.error), answer)
          return
        }
        if (!reply.desk) root._keepDrafts = false
        root.say(DesksLayouts.forkMessage(reply), false)
      })
    }
    ask(Prompts.text(label, { value: DesksLayouts.forkName(state, source), required: true }), answer)
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
          next[k] = { node: parsed.node, base: reply.trees[k].tree, memory: next[k] ? next[k].memory : null }
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

  function startReset() {
    if (refuseEdit()) return
    var k = screen
    var into = target()
    var what = into === "default" ? "The shared tree" : "Workspace " + into
    confirm("Put " + workspaceName(into) + " on screen " + k + " back to the tree slots.lua holds?", function() {
      root.engine.call("reset", { layout: root.layout, workspace: into, screen: parseInt(k, 10) }, function(reply) {
        if (!reply.ok) {
          root.say(reply.error, true)
          return
        }
        var next = Object.assign({}, root.drafts)
        next[k] = { node: reply.tree ? Layout.parse(reply.tree).node : null, base: reply.tree || null, memory: null }
        root.drafts = next
        root.keepSelection()
        root.say(what + " on screen " + k + " is back to "
          + (reply.tree || "no tree") + ".", false)
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
          next[r] = { node: Layout.parse(set.trees[r].tree).node, base: set.trees[r].tree, memory: null }
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

  // The header's text: what is edited, and the desks sharing it.
  function headerLine() {
    var note = Layout.defaultNote(state, layout, workspace, scope)
    return (workspace === "default" ? "All workspaces (the shared tree)" : "Workspace " + workspace) + "   [" + (layout || "no layout") + "]"
      + (note ? "   " + note : "")
  }

  // The workspace strip as it reads, the current one in brackets:
  // "[All workspaces] 1 2 3• ...": for the e2e smoke.
  function stripText() {
    return Workspaces.strip(state, layout, workspace).map(function(w) {
      return w.current ? "[" + Workspaces.stripText(w) + "]" : Workspaces.stripText(w)
    }).join(" ")
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
  readonly property color scrollColor: Commons.Color.accent
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
        text: root.headerLine()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      // "All workspaces", the shared trees (-), then the managed workspaces
      // by their keys ([ ] step, the digits jump): the one edited reversed,
      // the ones with trees of their own brighter and dotted, the ones
      // using the shared trees dimmer.
      Row {
        id: workspaceStrip
        anchors.left: headerText.right
        anchors.leftMargin: Style.spacing.lg * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.xs
        Repeater {
          model: Workspaces.strip(root.state, root.layout, root.workspace)
          delegate: Rectangle {
            required property var modelData
            width: workspaceKey.implicitWidth + Style.spacing.sm * 2
            height: workspaceKey.implicitHeight + Style.spacing.xs * 2
            radius: Style.cornerRadius
            color: modelData.current ? root.selectedBackground : "transparent"
            Text {
              id: workspaceKey
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: Workspaces.stripText(parent.modelData)
              color: parent.modelData.current ? root.selectedText : root.foreground
              opacity: parent.modelData.current || parent.modelData.own || parent.modelData.workspace === "default" ? 1 : 0.6
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: parent.modelData.current || parent.modelData.own || parent.modelData.workspace === "default"
              font.italic: parent.modelData.shared
            }
            MouseArea {
              anchors.fill: parent
              onClicked: root.goWorkspace(parent.modelData.workspace)
            }
          }
        }
      }
      Text {
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        readonly property int pending: root.editedScreens().length
        text: (pending > 0 ? "edited, not applied (w)   " : "")
          + (root.state && root.state.dirty ? "● unsaved (Ctrl+S)" : "saved")
        color: root.state && root.state.dirty || pending > 0 ? Commons.Color.urgent : root.foreground
        opacity: root.state && root.state.dirty || pending > 0 ? 1 : 0.6
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.state && root.state.dirty
      }
    }

    // Other desks share this layout: an edit here changes it for them too.
    Text {
      id: sharedNote
      width: parent.width
      visible: root.sharedWith.length > 0
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "Layout '" + root.layout + "' is also used by " + (root.sharedWith.length === 1 ? "desk " : "desks ")
        + root.sharedWith.join(", ") + ": every edit here changes it there too (f forks it for this desk)."
      color: Commons.Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
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

    // The panes, side by side (a scale model of each screen), and the slot
    // list beside them.
    Row {
      id: body
      width: parent.width
      height: parent.height - headerBox.height - (problem.visible ? problem.height + parent.spacing : 0)
        - (sharedNote.visible ? sharedNote.height + parent.spacing : 0)
        - orderText.height - parent.spacing * 3
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

            Text {
              id: paneTitle
              width: parent.width
              textFormat: Text.PlainText
              elide: Text.ElideRight
              text: Layout.screenLabel(root.state, pane.modelData.screen)
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
              readonly property real aspect: root.aspectOf(pane.modelData.connector)
              readonly property int boxW: Math.floor(Math.min(width, height * aspect))
              readonly property int boxH: Math.floor(Math.min(height, width / aspect))

              Rectangle {
                id: screenBox
                x: Math.floor((frame.width - frame.boxW) / 2)
                width: frame.boxW
                height: frame.boxH
                radius: Style.cornerRadius
                color: "transparent"
                // the keys' side: the picture's frame steps back while the slot list has them
                border.width: pane.active && !root.slotFocus ? 2 : 1
                border.color: pane.active ? Commons.Util.alpha(Commons.Color.accent, root.slotFocus ? 0.5 : 1)
                  : Commons.Util.alpha(root.foreground, 0.35)

                Text {
                  anchors.centerIn: parent
                  visible: pane.node === null
                  textFormat: Text.PlainText
                  text: root.workspace === "default" || !Layout.hasOwn(root.state, root.layout, root.workspace)
                    ? "No shared tree on this screen"
                    : "No tree for workspace " + root.workspace + " here"
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
                    selected: pane.active ? root.selectedKey : "",
                    titles: Layout.titles(root.state, root.workspace, pane.modelData.screen),
                  }) : []
                  delegate: Rectangle {
                    id: cell
                    required property var modelData
                    readonly property bool isLeaf: modelData.kind === "slot" || modelData.kind === "overflow"
                    readonly property bool isFrame: !!modelData.column
                    readonly property bool isContainer: !isLeaf
                    readonly property bool picked: !!modelData.selected
                    x: 4 + modelData.x + 2
                    y: 4 + modelData.y + 2
                    width: Math.max(0, modelData.w - 4)
                    height: Math.max(0, modelData.h - 4)
                    radius: Style.cornerRadius
                    color: picked && isLeaf ? root.selectedBackground
                      : isFrame ? Commons.Util.alpha(root.scrollColor, 0.08)
                      : isLeaf ? Commons.Util.alpha(modelData.kind === "overflow" ? root.overflowColor : root.foreground, 0.06)
                      : "transparent"
                    border.width: picked ? 2 : 1
                    border.color: picked ? Commons.Color.accent
                      : isFrame ? Commons.Util.alpha(root.scrollColor, 0.8)
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
                        root.screen = pane.modelData.key
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
                + (!pane.node ? ""
                  : pane.node.kind === "scroll" ? (Layout.leaves(pane.node).indexOf("*") < 0
                    ? "   full-width scrolling columns; windows with no slot after them (o: a column of their own)"
                    : "   full-width scrolling columns; windows with no slot in the * column")
                  : Layout.leaves(pane.node).indexOf("*") < 0 ? "   overflow parked (a column at the right)" : "")
              color: root.foreground
              opacity: 0.75
              font.family: "monospace"
              font.pixelSize: Style.font.body
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
            Text {
              id: slotTitleText
              anchors.left: parent.left
              textFormat: Text.PlainText
              text: "Slots"
              color: root.slotFocus ? Commons.Color.accent : root.foreground
              opacity: root.slotFocus ? 1 : 0.7
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: root.slotFocus
            }
            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              textFormat: Text.PlainText
              text: root.slotFocus ? "s / Esc: back" : "s: edit"
              color: root.foreground
              opacity: 0.5
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
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

            delegate: Rectangle {
              id: slotItem
              required property var modelData
              required property int index
              readonly property bool current: index === root.slotIndex
              readonly property bool lit: current && root.slotFocus
              width: ListView.view.width
              height: slotLines.implicitHeight + Style.spacing.sm * 2
              radius: Style.cornerRadius
              color: lit ? root.selectedBackground : "transparent"
              border.width: current && !root.slotFocus ? 1 : 0
              border.color: Commons.Util.alpha(root.foreground, 0.3)

              Column {
                id: slotLines
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.md
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

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.selectedSlot = slotItem.modelData.slot
                  root.focusSlots(true)
                }
              }
            }

            Text {
              anchors.centerIn: parent
              width: parent.width
              visible: root.slotRows.length === 0
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: root.state ? "No slots yet — s, then a, makes one (left, main, right…)" : ""
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
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
  }
}
