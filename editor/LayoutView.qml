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
import "Guide.js" as Guide
import "Assignment.js" as Assignment
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
// tree's ratios, and so does the mouse: every boundary between two
// children of a tiled split is a divider, dragged to a new ratio of the split
// (Layout.dividers, Layout.dragDivider: the whole split snapped to whole
// weights 1 to 5, anchored to where its dividers were when the drag
// started; its ratio shown by the pointer meanwhile). Edits go to a draft; `w` applies it (api set_trees), Ctrl+S
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
// (describe_slot), K sets its key, the letter that picks it in every
// slot-choice prompt (set_slot_key), d deletes it after y/n naming the trees and workspaces it
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
  // A divider being dragged: { screen, divider (as the picture had it when
  // pressed), base (the draft then), node (the tree as it would be let go
  // now), label (its split's ratio), changed, x, y (the pointer, in the
  // pane's picture) }; the pane draws `node` meanwhile. null otherwise.
  property var dragging: null
  // A screen's pane being dragged by its title onto another's, to swap
  // their trees: { from (its screen key), x, y (the pointer, in this view),
  // target (the screen key of the pane under the pointer, null outside the
  // panes), action (Layout.screenDropAction: { kind: "swap", label } or
  // { kind: "none" }) }; null otherwise. It has the keyboard while held:
  // Esc lets it go, other keys wait.
  property var screenDrag: null
  readonly property bool screenDragging: screenDrag !== null

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
  // No slots yet: the picture's place explains them and makes the first
  // (Guide.layoutWelcome, a); once there is one, a line says what comes
  // next until a workspace fills a slot (Guide.layoutHint).
  readonly property var welcome: Guide.layoutWelcome(state)
  readonly property string nextHint: Guide.layoutHint(state)

  // The controls strip: its groups (the panel draws them as a toolbar,
  // what the picture or the slot list would refuse now dimmed) and the
  // same as StyledText (each trigger key highlighted, Help.js).
  readonly property string accent: String(Commons.Color.accent)
  readonly property var helpGroups: {
    var jump = Workspaces.jumpKeys(Workspaces.count(state))
    if (slotFocus) return Layout.slotListHelp({ jumpKeys: jump, readOnly: slotsReadOnly !== "", hasSlot: !!slotRow })
    if (welcome) return Guide.welcomeHelp()
    return Layout.pictureHelp({ node: activeNode, hasOwn: Layout.hasOwn(state, layout, workspace), jumpKeys: jump,
      readOnly: block !== "", edited: editedScreens().length > 0, workspace: workspace, screens: paneList.length })
  }
  readonly property string helpText: prompting ? Help.escape(Prompts.help(prompt)) : Help.row(helpGroups, accent)

  // A key by name, for the panel to feed as if pressed (Panel.press): a
  // double-click on a slot of the slot list shows it in the picture
  // (Return).
  signal pressKey(string name)

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
    dragging = null
    screenDrag = null
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
    // a pane held in a drag owns the keyboard: Esc cancels it, the rest waits
    if (screenDragging) {
      if (key === Qt.Key_Escape) screenDragCancel()
      return true
    }
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
    if (welcome) {
      // Nothing to arrange yet: a makes the first slot.
      if (text !== "a") return false
      startNewSlot(null, true)
      return true
    }
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
    else if (text === "p") swapWithNext()
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

  // --- swapping screens --------------------------------------------------------

  // Screens `a` and `b` trade trees (Layout.swapScreens): an edit like
  // any other, into both drafts (asking first, on a workspace on the shared
  // trees, whom it is for). The selection goes with screen a's tree, to b.
  function swapScreens(a, b) {
    if (refuseEdit()) return
    var check = Layout.swapScreens(drafts, a, b)
    if (check.error) {
      say(check.error, true)
      return
    }
    scoped(function() {
      var result = Layout.swapScreens(root.drafts, a, b)
      if (result.error) {
        root.say(result.error, true)
        return
      }
      root.drafts = result.drafts
      root.screen = String(b)
      if (root.slotFocus) root.slotFocus = false
      root.keepSelection()
      root.say(Layout.swappedText(a, b) + root.draftNote(), false)
    }, false)
  }

  // p: the selected screen with the next (round from the last to the first).
  function swapWithNext() {
    var next = Layout.nextScreen(currentPanes(), screen)
    if (next === null) {
      say("This layout has one screen: there is no other to swap it with.", true)
      return
    }
    swapScreens(screen, next)
  }

  // Whether a pane's title drags: an editable layout of more than one
  // screen, no prompt open, no divider held.
  readonly property bool screensDrag: block === "" && !prompting && !dragging && paneList.length > 1

  // A press on screen `k`'s title moved past the threshold: the drag
  // begins (false when it may not), at x, y in this view.
  function screenDragStart(k, x, y) {
    if (!screensDrag) return false
    message = ""
    screenDrag = { from: k, x: x, y: y, target: null, action: { kind: "none" } }
    screenDragTo(x, y)
    return true
  }

  // The pane under x, y (in this view): its screen key, or null.
  function paneKeyAt(x, y) {
    var p = mapToItem(paneRow, x, y)
    if (p.y < 0 || p.y >= paneRow.height) return null
    var i = Layout.paneAt(p.x, paneList.length, paneRow.width, root.gap)
    return i >= 0 ? paneList[i].key : null
  }

  function screenDragTo(x, y) {
    if (!screenDrag) return
    var target = paneKeyAt(x, y)
    screenDrag = { from: screenDrag.from, x: x, y: y, target: target,
      action: Layout.screenDropAction(drafts, screenDrag.from, target) }
  }

  // Let go: over another pane, the two swap (swapScreens, as p does).
  function screenDragDrop() {
    if (!screenDrag) return
    var done = screenDrag
    screenDrag = null
    var action = Layout.screenDropAction(drafts, done.from, paneKeyAt(done.x, done.y))
    if (action.kind === "swap") swapScreens(done.from, paneKeyAt(done.x, done.y))
  }

  function screenDragCancel() {
    screenDrag = null
  }

  // A click on a pane's title: its screen has the keys.
  function pickScreen(k) {
    if (slotFocus) slotFocus = false
    if (screen === k) return
    screen = k
    selectedKey = ""
    keepSelection()
  }

  // --- the slot list ---------------------------------------------------------

  function handleSlotKey(key, text) {
    if (key === Qt.Key_Up || text === "k") selectSlot(slotIndex - 1)
    else if (key === Qt.Key_Down || text === "j") selectSlot(slotIndex + 1)
    else if (text === "a") startNewSlot(null, slotRows.length === 0)
    else if (key === Qt.Key_Return || key === Qt.Key_Enter) showSelectedSlot()
    else if (text === "r") startRenameSlot()
    else if (text === "e") startDescribeSlot()
    else if (text === "K") startSlotKey(null)
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
  // drafts follow on the next state read (sync). `first`: the first slot,
  // made from the picture's explanation, asked for in a newcomer's words.
  function startNewSlot(values, first) {
    if (!slotsEditable()) return
    values = values || { name: "", description: "", error: "" }
    var label = first ? Guide.firstSlotLabel() : Slots.newSlotLabel()
    ask(Prompts.withError(Prompts.text(label, { value: values.name, required: true }), values.error),
      function(name) {
        root.ask(Prompts.text("Description, optional [Enter] add  [Esc] cancel: ", { value: values.description }),
          function(description) {
            root.engine.call("add_slot", { slot: name.trim(), description: description }, function(reply) {
              if (!reply.ok) {
                root.startNewSlot({ name: name, description: description, error: reply.error }, first)
                return
              }
              root.selectedSlot = reply.slot
              root._newSlot = reply.slot
              root.say(first ? Guide.firstSlotAdded(reply.slot) : Slots.addedText(reply.slot), false)
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

  // K: the slot's key, the letter that picks it in every slot-choice prompt
  // (set_slot_key). A letter that is taken or no letter is refused in the
  // prompt (Slots.keyAnswer), as is the engine's refusal: the answer kept.
  function startSlotKey(again) {
    if (!needSlot() || !slotsEditable()) return
    var row = slotRow
    var p = Prompts.text(Slots.keyLabel(row), { value: again ? again.value : row.key, required: true })
    ask(again ? Prompts.withError(p, again.error) : p, function(text) {
      var answer = Slots.keyAnswer(root.slotRows, row.slot, text)
      if (answer.error) {
        root.startSlotKey({ value: text, error: answer.error })
        return
      }
      if (answer.key === row.key) {
        root.say("Slot '" + row.slot + "' is picked with " + row.key + " already.", false)
        return
      }
      root.engine.call("set_slot_key", { slot: row.slot, key: answer.key }, function(reply) {
        if (!reply.ok) root.startSlotKey({ value: text, error: reply.error })
        else root.say(Slots.keyedText(reply.slot, reply.key), false)
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

  // A click on a tile or a filmstrip column: it is the selection, and the
  // keys go back to the picture (from the slot list) to act on it.
  function pickLeaf(screenKey, leafKey) {
    screen = screenKey
    selectedKey = leafKey
    if (slotFocus) slotFocus = false
  }

  // --- dividers: the mouse's ratios ------------------------------------------

  // Whether the dividers of screen `k`'s picture take the mouse: an editable
  // layout, no prompt open, a tiled tree there.
  function dividersLive(k) {
    var d = drafts[k]
    return block === "" && !prompting && !!d && !!d.node && d.node.kind !== "scroll"
  }

  // A press on `divider` of screen `k`'s picture: the drag starts there
  // (false when it may not), the keys back to the picture on that screen.
  function dragStart(k, divider) {
    if (!dividersLive(k)) return false
    screen = k
    if (slotFocus) slotFocus = false
    var base = drafts[k].node
    dragging = { screen: k, divider: divider, base: base, node: base, changed: false,
      label: Layout.dragDivider(base, divider, null).label || "", x: -1, y: -1 }
    return true
  }

  // The pointer at `fraction` of the two neighbours (Layout.dividerFraction),
  // at x, y in the picture: always snapped from the tree the drag started on
  // (dragging.base), never from where the drag has had it since.
  function dragTo(fraction, x, y) {
    if (!dragging) return
    var result = Layout.dragDivider(dragging.base, dragging.divider, fraction)
    if (result.error) return
    dragging = { screen: dragging.screen, divider: dragging.divider, base: dragging.base, node: result.node,
      changed: result.changed, label: result.label, x: x, y: y }
  }

  // Let go: the new ratio is an edit like r's, into the draft (asking first,
  // on a workspace on the shared trees, whom it is for).
  function dragEnd() {
    var done = dragging
    dragging = null
    if (!done || !done.changed) return
    scoped(function() {
      if (!root.drafts[done.screen]) return
      root.setDraft(done.screen, done.node)
      root.say("Set ratios " + Layout.ratio(done.node) + "." + root.draftNote(), false)
      root.keepSelection()
    }, true)
  }

  function dragCancel() {
    dragging = null
  }

  // The tree screen `k`'s pane draws: the dragged one while a divider of it
  // is held, else its draft's.
  function shownNode(k, draft) {
    if (dragging && dragging.screen === k) return dragging.node
    return draft ? draft.node : null
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
    dragging = null
    screenDrag = null
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

    // After the first slot: what comes next, until a workspace fills one.
    InfoText {
      id: nextNote
      width: parent.width
      leftPadding: Tokens.textInset
      visible: root.nextHint !== ""
      elide: Text.ElideRight
      text: root.nextHint
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
        - (nextNote.visible ? nextNote.height + parent.spacing : 0)
        - parent.spacing
      spacing: root.gap * 2

      // No slots yet: in the picture's place, what slots are, what
      // happens next, and the one thing to do now (a, or the button).
      Item {
        id: welcomeBox
        visible: !!root.welcome
        width: body.width - slotPanel.width - body.spacing
        height: body.height

        Column {
          anchors.centerIn: parent
          width: Math.min(parent.width - Style.spacing.xxl * 2, Style.space(560))
          spacing: Style.spacing.lg

          Placeholder {
            width: parent.width
            color: Tokens.text
            font.bold: true
            font.pixelSize: Style.font.subtitle
            text: root.welcome ? root.welcome.title : ""
          }
          Repeater {
            model: root.welcome ? root.welcome.lines : []
            delegate: Placeholder {
              required property string modelData
              width: parent.width
              text: modelData
            }
          }
          Item {
            width: parent.width
            height: createButton.height + Style.spacing.sm
            ActionButton {
              id: createButton
              objectName: root.welcome ? "welcome:create" : ""
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.bottom: parent.bottom
              accented: true
              keyText: root.welcome ? root.welcome.action.key : ""
              text: root.welcome ? root.welcome.action.label : ""
              pixelSize: Style.font.body
              padX: Style.spacing.xl
              padY: Style.spacing.sm
              onClicked: root.pressKey(root.welcome.action.key)
            }
          }
        }
      }

      Row {
        id: paneRow
        visible: !root.welcome
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
            // the draft's tree, or the dragged one while a divider is held
            readonly property var node: root.shownNode(modelData.key, draft)
            readonly property bool active: modelData.key === root.screen
            readonly property bool changed: root.edited(modelData.key)
            // held in a drag by its title (dimmed), or where one would land
            readonly property bool dragged: !!root.screenDrag && root.screenDrag.from === modelData.key
            readonly property bool landing: !!root.screenDrag && root.screenDrag.action.kind === "swap"
              && root.screenDrag.target === modelData.key
            width: (paneRow.width - root.gap * (root.paneList.length - 1)) / Math.max(1, root.paneList.length)
            height: paneRow.height
            spacing: Style.spacing.sm
            opacity: dragged ? Tokens.dim : 1

            PaneTitle {
              id: paneTitle
              width: parent.width
              leftPadding: Tokens.textInset
              // the keys' pane: not while the slot list has them
              active: pane.active && !root.slotFocus
              text: Layout.screenLabel(root.state, pane.modelData.screen)
                + (pane.changed ? "   edited" : "") + (pane.modelData.resized && !pane.changed ? "   keyboard-resized" : "")

              // The title is the pane's handle: dragged onto another pane
              // it swaps their trees (screenDragStart, screenDragTo,
              // screenDragDrop; Esc cancels: handleKey); a click gives its
              // screen the keys. Tiles, dividers and filmstrip columns
              // keep the rest of the pane.
              MouseArea {
                id: titleMouse
                objectName: "screen:" + pane.modelData.key
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                property real pressX: 0
                property real pressY: 0
                // this press made a drag (held, let go or cancelled): no click
                property bool dragMade: false
                cursorShape: root.screenDrag ? Qt.ClosedHandCursor : root.screensDrag ? Qt.OpenHandCursor : Qt.ArrowCursor

                function follow(mouse) {
                  var p = mapToItem(root, mouse.x, mouse.y)
                  root.screenDragTo(p.x, p.y)
                }
                onPressed: (mouse) => {
                  pressX = mouse.x
                  pressY = mouse.y
                  dragMade = false
                }
                onPositionChanged: (mouse) => {
                  if (!pressed) return
                  if (dragMade) {
                    if (root.screenDrag) follow(mouse)
                    return
                  }
                  if (!Assignment.dragBegins(pressX, pressY, mouse.x, mouse.y)) return
                  var p = mapToItem(root, mouse.x, mouse.y)
                  dragMade = root.screenDragStart(pane.modelData.key, p.x, p.y)
                }
                onReleased: (mouse) => {
                  if (root.screenDrag) {
                    follow(mouse)
                    root.screenDragDrop()
                  }
                }
                onClicked: {
                  if (!dragMade) root.pickScreen(pane.modelData.key)
                }
                onCanceled: root.screenDragCancel()
              }
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
              // the tiles' layout, inside the screen box's 4 px margin
              readonly property var area: ({ x: 0, y: 0, w: screenBox.width - 8, h: screenBox.height - 8 })
              readonly property var boxOpts: ({ pad: 5, title: Style.font.bodySmall + 6,
                selected: pane.active ? root.selectedKey : "", titles: frame.titles })
              readonly property var boxes: picture && !scrolls ? Layout.rects(picture, area, boxOpts) : []
              readonly property var dividers: picture && !scrolls ? Layout.dividers(picture, area, boxOpts) : []
              // the drag on this pane, else null: every binding below reads
              // this one, so none sees a drag the others have let go
              readonly property var drag: root.dragging && root.dragging.screen === pane.modelData.key ? root.dragging : null
              readonly property bool dragHere: drag !== null

              // Where a screen dragged by its title would land: the whole
              // pane, its title included, outlined in the accent with a
              // faint accent fill, as a drop target in the Assignment table.
              Rectangle {
                objectName: "dropzone:screen:" + pane.modelData.key
                visible: pane.landing
                z: 5
                x: -Tokens.dropLine
                y: -(paneTitle.height + pane.spacing) - Tokens.dropLine
                width: frame.width + Tokens.dropLine * 2
                height: frame.height + paneTitle.height + pane.spacing + Tokens.dropLine * 2
                radius: Tokens.radius
                color: Tokens.dropFill
                border.width: Tokens.dropLine
                border.color: Tokens.dropOutline
              }

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
                  model: frame.boxes
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

                    // a click selects the tile, the keys back to the picture
                    MouseArea {
                      objectName: cell.isContainer ? "" : "tile:" + pane.modelData.key + ":" + cell.modelData.key
                      anchors.fill: parent
                      enabled: !cell.isContainer
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.pickLeaf(pane.modelData.key, cell.modelData.key)
                    }
                  }
                }

                // The dividers: every boundary between two children of a
                // tiled split, a band the pointer grabs, its line lit on
                // hover and while dragged. (Drawn only; dividerMouse below
                // takes the pointer, so a drag survives the picture being
                // laid out anew at every step.)
                Repeater {
                  model: frame.dividers
                  delegate: Item {
                    id: band
                    required property var modelData
                    readonly property bool across: modelData.axis === "h"
                    readonly property bool held: !!frame.drag && frame.drag.divider.id === modelData.id
                    readonly property bool lit: held || (!frame.dragHere && dividerMouse.enabled && dividerMouse.hoveredId === modelData.id)
                    objectName: "divider:" + pane.modelData.key + ":" + modelData.id
                    x: 4 + (across ? modelData.at - Tokens.dividerHit / 2 : modelData.x)
                    y: 4 + (across ? modelData.y : modelData.at - Tokens.dividerHit / 2)
                    width: across ? Tokens.dividerHit : modelData.length
                    height: across ? modelData.length : Tokens.dividerHit
                    Rectangle {
                      anchors.centerIn: parent
                      width: band.across ? Tokens.dividerLine : parent.width - 8
                      height: band.across ? parent.height - 8 : Tokens.dividerLine
                      radius: Tokens.dividerLine / 2
                      color: band.held ? Tokens.dividerActive : band.lit ? Tokens.dividerHover : "transparent"
                    }
                  }
                }

                // The pointer on the picture: on a divider a resize cursor,
                // and a press there drags it (Layout.dragDivider: the split
                // snapped to a new ratio); anywhere else the press
                // goes on to the tile under it.
                MouseArea {
                  id: dividerMouse
                  objectName: "dividers:" + pane.modelData.key
                  anchors.fill: parent
                  enabled: root.dividersLive(pane.modelData.key)
                  hoverEnabled: true
                  preventStealing: true
                  property string hoveredId: ""
                  property string hoveredAxis: ""
                  property bool overLeaf: false
                  readonly property string axis: frame.drag ? frame.drag.divider.axis : hoveredAxis
                  cursorShape: axis === "h" ? Qt.SplitHCursor : axis === "v" ? Qt.SplitVCursor
                    : overLeaf ? Qt.PointingHandCursor : Qt.ArrowCursor

                  // the divider under the pointer (picture coordinates are
                  // the screen box's less its 4 px margin)
                  function hit(mx, my) {
                    return Layout.dividerAt(frame.dividers, mx - 4, my - 4, Tokens.dividerHit / 2)
                  }
                  function onLeaf(mx, my) {
                    return frame.boxes.some(function(b) {
                      return (b.kind === "slot" || b.kind === "overflow") && mx - 4 >= b.x && mx - 4 < b.x + b.w
                        && my - 4 >= b.y && my - 4 < b.y + b.h
                    })
                  }
                  function hover(mx, my) {
                    var d = hit(mx, my)
                    hoveredId = d ? d.id : ""
                    hoveredAxis = d ? d.axis : ""
                    overLeaf = !d && onLeaf(mx, my)
                  }

                  onPositionChanged: (mouse) => {
                    if (!frame.drag) {
                      hover(mouse.x, mouse.y)
                      return
                    }
                    var d = frame.drag.divider
                    root.dragTo(Layout.dividerFraction(d, (d.axis === "h" ? mouse.x : mouse.y) - 4), mouse.x, mouse.y)
                  }
                  onPressed: (mouse) => {
                    var d = hit(mouse.x, mouse.y)
                    if (!d || !root.dragStart(pane.modelData.key, d)) {
                      mouse.accepted = false
                      return
                    }
                    root.dragTo(null, mouse.x, mouse.y)
                  }
                  onReleased: (mouse) => {
                    if (!frame.dragHere) return
                    root.dragEnd()
                    hover(mouse.x, mouse.y)
                  }
                  onCanceled: if (frame.dragHere) root.dragCancel()
                  onExited: {
                    hoveredId = ""
                    hoveredAxis = ""
                    overLeaf = false
                  }
                }

                // The dragged split's ratio, by the pointer.
                Rectangle {
                  id: ratioTip
                  objectName: "dragRatio:" + pane.modelData.key
                  visible: !!frame.drag && frame.drag.x >= 0
                  readonly property real px: frame.drag ? frame.drag.x : 0
                  readonly property real py: frame.drag ? frame.drag.y : 0
                  x: Math.max(0, Math.min(screenBox.width - width, px + Style.spacing.md))
                  y: Math.max(0, Math.min(screenBox.height - height, py + Style.spacing.md))
                  width: tipText.implicitWidth + Style.spacing.md * 2
                  height: tipText.implicitHeight + Style.spacing.xs * 2
                  radius: Tokens.radius
                  color: Tokens.tipFill
                  border.width: 1
                  border.color: Tokens.tipBorder
                  Text {
                    id: tipText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: frame.drag ? frame.drag.label : ""
                    color: Tokens.tipText
                    font.family: Tokens.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
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

                    // a click selects the column, the keys back to the picture
                    MouseArea {
                      objectName: "tile:" + pane.modelData.key + ":" + column.modelData.key
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.pickLeaf(pane.modelData.key, column.modelData.key)
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
              objectName: "slot:" + slotItem.modelData.slot
              selected: lit
              marked: current && !root.slotFocus
              onClicked: {
                root.selectedSlot = slotItem.modelData.slot
                root.focusSlots(true)
              }
              // its primary action, as its key: show it in the picture
              onDoubleClicked: {
                root.selectedSlot = slotItem.modelData.slot
                root.pressKey("Return")
              }

              Column {
                id: slotLines
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.cellPadding
                anchors.rightMargin: Tokens.cellPadding
                // the name, and at the right the key that picks it in
                // every slot-choice prompt (K changes it)
                Item {
                  width: parent.width
                  height: Math.max(slotName.implicitHeight, slotKey.height)
                  Text {
                    id: slotName
                    anchors.left: parent.left
                    anchors.right: slotKey.left
                    anchors.rightMargin: Style.spacing.sm
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    text: slotItem.modelData.slot
                    color: slotItem.lit ? root.selectedText : Commons.Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  KeyCap {
                    id: slotKey
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: slotItem.modelData.key !== ""
                    text: slotItem.modelData.key
                    ink: slotItem.lit ? root.selectedText : Commons.Color.accent
                  }
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
              text: root.state ? "No slots yet" : ""
            }
          }
        }
      }
    }
  }

  // A screen's pane held by its title: its ghost by the pointer (the
  // screen and the slots its tree places), and what letting go does there.
  DragGhost {
    id: screenGhost
    objectName: "screenGhost"
    visible: root.screenDragging
    z: 10
    readonly property var draft: root.screenDrag ? root.drafts[root.screenDrag.from] || null : null
    title: root.screenDrag ? Layout.screenLabel(root.state, parseInt(root.screenDrag.from, 10)) : ""
    subtitle: draft && draft.node ? Layout.leaves(Layout.picture(draft.node, false)).join(", ") : ""
    label: root.screenDrag && root.screenDrag.action.kind !== "none" ? root.screenDrag.action.label : ""
    x: root.screenDrag ? Math.max(0, Math.min(root.width - width, root.screenDrag.x + Style.spacing.lg)) : 0
    y: root.screenDrag ? Math.max(0, Math.min(root.height - height, root.screenDrag.y + Style.spacing.md)) : 0
  }
}
