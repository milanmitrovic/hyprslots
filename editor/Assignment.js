.pragma library
.import "Workspaces.js" as Workspaces

// The Assignment view's model: which live window fills which slot, read off
// one api `state` reply (docs/design.md §9). Ported from aerolayout's
// AssignmentView (views.py): a table of the windows on a workspace, each with
// its slot, plus a placeholder row for every slot whose window is not
// running; `a` puts the selected window into a global slot and makes its spec
// the workspace's for that slot (as aerolayout's `a` wrote the spec), `u`
// takes a window out (and the spec with it), or on a Missing row clears the
// workspace's spec for the slot. Pure, so node can test it
// (editor/tests/assignment.test.mjs).
//
// A row is
//   { kind: "window" | "missing" | "empty", status, address, cls, title,
//     workspaceId, workspace, slot, screen, spec }
// (workspaceId the Hyprland workspace id the window is on, workspace the
// number 1 to 10 of its slot or its workspace, screen its screen number on
// the active desk)
// with status one of "slot" (matched by its spec), "manual" (assigned by
// hand), "overflow" (matches `slot`, which is taken: in the workspace's
// overflow leaf), "unassigned" (taken out of its slot by hand), "none" (matches no
// spec), "missing" (a slot whose window is not open: the spec it waits
// for), "empty" (a slot of the workspace with no window and no spec: nothing
// says what fills it, so nothing is missing).

// The pages ←/→ move through: workspaces 1 to N, the ones the engine manages
// (Workspaces.count).
function pages(state) {
  var out = []
  var last = Workspaces.count(state)
  for (var n = 1; n <= last; n++) out.push({ workspace: n, label: "Workspace " + n })
  return out
}

// The workspace number (1 to 10) a Hyprland workspace id is on the active
// desk, or null.
function workspaceOf(state, id) {
  var entry = Workspaces.entry(state, id)
  return entry ? entry.workspace : null
}

// The workspace's specs: slot -> spec text.
function workspaceSpecs(state, workspace) {
  return (state && state.specs && state.specs[String(workspace)]) || {}
}

// The global slot names, in the state's order (by name).
function slotNames(state) {
  var list = state && Array.isArray(state.slots) ? state.slots : []
  return list.map(function(s) { return s.name })
}

// slot name -> its stored key (state.slots[].key), "" for a slot with none.
function slotKeys(state) {
  var out = {}
  var list = state && Array.isArray(state.slots) ? state.slots : []
  list.forEach(function(s) { out[s.name] = s.key ? String(s.key) : "" })
  return out
}

// The slots of a workspace as [{ slot, screen }]: those the active layout's
// trees for it place (its own, else the default ones; every tree has every
// global slot), in tree order, screen by screen, then any other global slot
// (screen null; a layout with no tree for the workspace), by name, with any
// the workspace has a spec for that is no global slot among them.
function slotOrder(state, workspace) {
  var out = []
  var seen = {}
  var specs = workspaceSpecs(state, workspace)
  var layout = Workspaces.activeLayout(state)
  var branches = layout && layout.workspaces ? layout.workspaces[String(workspace)] || {} : {}
  var count = layout ? layout.screens || 0 : 0
  for (var r = 1; r <= count; r++) {
    var branch = branches[String(r)]
    var slots = branch && Array.isArray(branch.slots) ? branch.slots : []
    for (var s = 0; s < slots.length; s++) {
      if (!seen[slots[s]]) {
        seen[slots[s]] = true
        out.push({ slot: slots[s], screen: r })
      }
    }
  }
  var others = {}
  slotNames(state).concat(Object.keys(specs)).forEach(function(name) { if (!seen[name]) others[name] = true })
  var rest = Object.keys(others).sort()
  for (var i = 0; i < rest.length; i++) out.push({ slot: rest[i], screen: null })
  return out
}

// Where slot `slot`'s mini-map comes from: the screen of the active
// layout whose tree for workspace `workspace` places it (as state reports
// it: the workspace's own, else the default ones), that tree's text and the
// active desk's monitor there; null when no tree places it.
function miniMapSource(state, workspace, slot) {
  var layout = Workspaces.activeLayout(state)
  if (!layout || !layout.workspaces) return null
  var branches = layout.workspaces[String(workspace)] || {}
  for (var r = 1; r <= (layout.screens || 0); r++) {
    var branch = branches[String(r)]
    if (branch && Array.isArray(branch.slots) && branch.slots.indexOf(slot) >= 0) {
      var screens = state && Array.isArray(state.screens) ? state.screens : []
      return { screen: r, tree: branch.tree, connector: screens[r - 1] || "" }
    }
  }
  return null
}

function windowList(state) {
  return state && Array.isArray(state.windows) ? state.windows : []
}

function isManual(state, address) {
  var a = state && state.assignments ? state.assignments[address] : null
  return !!(a && a.manual)
}

function windowRow(state, w) {
  var entry = Workspaces.entry(state, w.workspace_id)
  var row = {
    kind: "window",
    address: w.address,
    cls: w.class || "",
    title: w.title || "",
    workspaceId: w.workspace_id,
    workspace: entry ? entry.workspace : null,
    slot: null,
    screen: entry ? entry.screen : null,
    spec: null,
    status: w.unassigned ? "unassigned" : "none",
  }
  if (w.slot !== undefined && w.slot !== null) {
    row.workspace = w.workspace
    row.slot = w.slot
    row.status = isManual(state, w.address) ? "manual" : "slot"
  } else if (w.overflow) {
    row.workspace = w.overflow.workspace
    row.slot = w.overflow.slot
    row.status = "overflow"
  }
  return row
}

function holders(state) {
  var out = {}
  var windows = windowList(state)
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (w.slot !== undefined && w.slot !== null) out[w.workspace + "/" + w.slot] = w
  }
  return out
}

// The rows of workspace `workspace`'s page.
function rows(state, workspace) {
  if (!state || workspace === null || workspace === undefined) return []
  var windows = windowList(state)
  var held = holders(state)
  var out = []
  var used = {}
  var i

  var slots = slotOrder(state, workspace)
  var specs = workspaceSpecs(state, workspace)
  for (i = 0; i < slots.length; i++) {
    var w = held[workspace + "/" + slots[i].slot]
    if (w) {
      used[w.address] = true
      var row = windowRow(state, w)
      if (!row.screen) row.screen = slots[i].screen
      out.push(row)
    } else {
      var waits = specs[slots[i].slot] !== undefined
      out.push({
        kind: waits ? "missing" : "empty",
        status: waits ? "missing" : "empty",
        address: null,
        cls: "",
        title: "",
        workspaceId: null,
        workspace: workspace,
        slot: slots[i].slot,
        screen: slots[i].screen,
        spec: specs[slots[i].slot] !== undefined ? String(specs[slots[i].slot]) : "",
      })
    }
  }
  for (i = 0; i < windows.length; i++) {
    if (!used[windows[i].address] && windows[i].overflow && windows[i].overflow.workspace === workspace) {
      used[windows[i].address] = true
      out.push(windowRow(state, windows[i]))
    }
  }
  for (i = 0; i < windows.length; i++) {
    var other = windows[i]
    if (!used[other.address] && workspaceOf(state, other.workspace_id) === workspace
        && (other.slot === undefined || other.slot === null)) {
      used[other.address] = true
      out.push(windowRow(state, other))
    }
  }
  return out
}

// What the Slot column says for a row.
function slotText(row) {
  switch (row.status) {
  case "slot": return row.slot
  case "manual": return row.slot + " (by hand)"
  case "overflow": return "other (" + row.slot + " taken)"
  case "unassigned": return "unassigned"
  case "missing": return row.slot
  case "empty": return row.slot
  default: return "—"
  }
}

// What a slot row with no window says in the App column: the spec a
// Missing one waits for, a dash for an empty one.
function specText(row) {
  return row.spec ? row.spec : "—"
}

// What the Title column says: "Missing — waiting for it to open" for a
// slot whose window is not open (the App column names the window it waits
// for), a dash for an empty one, else the window's title.
function titleText(row) {
  if (row.kind === "missing") return "Missing — waiting for it to open"
  if (row.kind === "empty") return "—"
  return row.title || "No Title"
}

// The Screen column: the screen number and the active desk's monitor there.
function screenText(state, row) {
  if (!row || row.screen === null || row.screen === undefined) return ""
  var connector = state && Array.isArray(state.screens) ? state.screens[row.screen - 1] : null
  return String(row.screen) + (connector ? " " + connector : "")
}

// What `u` does for a row: { address, clearSpec, question } (the y/n it
// asks), { clear: { workspace, slot, spec }, question }, or { error }. A
// window in a slot leaves it with the workspace's spec for it (api unassign
// with clear_spec), so the slot is left empty instead of Missing that window;
// an overflowing window, or one in a slot the workspace has no spec for, is
// only taken out. A Missing row (a spec whose window is not open) loses the
// spec (api clear_spec): the slot is left empty.
function unassignPlan(state, row) {
  if (!row) return { error: "Nothing selected." }
  if (row.kind === "missing") {
    var waits = workspaceSpecs(state, row.workspace)[row.slot]
    var text = waits !== undefined ? String(waits) : row.spec
    return { clear: { workspace: row.workspace, slot: row.slot, spec: text },
      question: "Unassign " + text + " from " + row.slot + " on workspace " + row.workspace
        + "? It is not open; the slot is left empty." }
  }
  if (row.kind !== "window") {
    return { error: "Nothing is assigned to " + row.slot + " on workspace " + row.workspace + ": there is nothing to unassign." }
  }
  if (row.status === "overflow") {
    return { address: row.address, clearSpec: false, question: "Unassign " + row.cls + " from " + row.slot
      + "? It waits with the other windows while " + row.slot + " is taken." }
  }
  if (row.status !== "slot" && row.status !== "manual") return { error: row.cls + " is assigned to no slot." }
  var spec = workspaceSpecs(state, row.workspace)[row.slot]
  if (spec === undefined) {
    return { address: row.address, clearSpec: false, question: "Unassign " + row.cls + " from " + row.slot + "?" }
  }
  return { address: row.address, clearSpec: true, question: "Unassign " + row.cls + " from " + row.slot
    + " on workspace " + row.workspace + "? The slot is left empty." }
}

// The question `a` asks: which slot of workspace `workspace` the window
// (its class, `cls`) goes into.
function assignTitle(workspace, cls) {
  return "Assign " + cls + " to a slot on workspace " + workspace
}

// The slots `a` offers on workspace `workspace`'s page: every global slot,
// the workspace's own in tree order
// first, then the rest by name. Each option is { key, workspace, slot, spec
// (the workspace's spec for it, "" for none), holder } where holder is the
// address in the slot (or null) and key the slot's own, stored with it
// (docs/design.md §4: the same on every page and in every prompt); "" for a
// slot with none (pick it with the arrows).
function slotOptions(state, workspace) {
  var on = workspace
  if (on === null || on === undefined) return []
  var held = holders(state)
  var specs = workspaceSpecs(state, on)
  var keys = slotKeys(state)
  var names = slotOrder(state, on).map(function(o) { return o.slot })
  var listed = {}
  names.forEach(function(n) { listed[n] = true })
  slotNames(state).forEach(function(n) {
    if (!listed[n]) {
      listed[n] = true
      names.push(n)
    }
  })
  return names.map(function(name) {
    var holder = held[on + "/" + name]
    return { key: keys[name] || "", workspace: on, slot: name, spec: specs[name] !== undefined ? String(specs[name]) : "",
      holder: holder ? holder.address : null }
  })
}

// The slot options as Prompts.js choice options ({ key, label, value });
// the value is the slot option.
function promptOptions(options) {
  return options.map(function(o) {
    return { key: o.key, label: o.slot, value: o }
  })
}

// The page of workspace `workspace` (the digit keys jump to it), -1 when it
// is no managed one.
function pageOfWorkspace(state, workspace) {
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].workspace === workspace) return i
  return -1
}

// The page to open on: the focused workspace's, else workspace 1's.
function initialPage(state, workspaceId) {
  var i = pageOfWorkspace(state, workspaceOf(state, workspaceId))
  return i < 0 ? 0 : i
}

// The message after `a` (take_spec's reply): the slot the window took, the
// window it replaced, the one that gave the slot up and the slot it left.
function assignedText(state, cls, reply) {
  var text = "Assigned " + cls + " to " + reply.slot + " on workspace " + reply.workspace
  if (reply.replaced && reply.replaced !== reply.spec) text += " (instead of " + reply.replaced + ")"
  if (reply.displaced) {
    var windows = windowList(state)
    var gone = reply.displaced
    for (var i = 0; i < windows.length; i++) if (windows[i].address === reply.displaced) gone = windows[i].class
    text += "; " + gone + " gave it up"
  }
  // The slot it moved out of, its spec cleared with the move (take_spec's left).
  if (reply.left) {
    text += "; " + reply.left.slot + (reply.left.workspace !== reply.workspace ? " on workspace " + reply.left.workspace : "")
      + " is empty now"
  }
  return text + ". Ctrl+S saves."
}

// The help row (Help.row groups) on `row`, the selected row of a page:
// a puts a window into a slot (not on an empty or Missing row), u takes out
// what unassignPlan can; what the view would refuse now is marked
// `enabled: false` (the toolbar dims it). `jumpKeys` is Workspaces.jumpKeys.
//
// opts (optional): { capture (whether c, capture the page's workspace in
// the Layout tab, would go ahead: false dims it), launch (the page's launch
// items, Launch.js's, a group of their own) }.
function helpGroups(state, row, jumpKeys, opts) {
  opts = opts || {}
  var assign = { key: "a", label: "assign" }
  if (!row || row.kind !== "window") assign.enabled = false
  var unassign = { key: "u", label: "unassign" }
  if (unassignPlan(state, row).error) unassign.enabled = false
  var edits = [assign, unassign]
  if (opts.capture !== undefined) {
    var capture = { key: "c", label: "capture" }
    if (!opts.capture) capture.enabled = false
    edits.push(capture)
  }
  var groups = [
    [{ key: "↑/↓", label: "select" }],
    { title: "Workspace", items: [{ key: "←/→ [ ]", label: "prev/next" }, { key: jumpKeys, label: "jump" }] },
    edits,
  ]
  if (opts.launch && opts.launch.length) groups.push(opts.launch)
  return groups.concat([
    [{ key: "Ctrl+S", label: "save" }],
    [{ key: "Tab", label: "switch view" }, { key: "q", label: "close" }],
  ])
}

// --- drag and drop ---------------------------------------------------------
//
// A row with a window is dragged (the view's one MouseArea over the list);
// where it is let go decides what happens (dropAction). Pure, so node tests
// it (editor/tests/assignment-drag.test.mjs).

// How far (px) the pointer moves from its press before the press is a drag:
// under it, a click (select) or a double-click (a), as before.
var DRAG_THRESHOLD = 6

// Whether a press at x0, y0 with the pointer now at x, y is a drag.
function dragBegins(x0, y0, x, y) {
  var dx = x - x0, dy = y - y0
  return dx * dx + dy * dy >= DRAG_THRESHOLD * DRAG_THRESHOLD
}

// Whether `row` drags: any row with a window (in a slot, overflowing or a
// stray), never a Missing or empty slot.
function canDrag(row) {
  return !!row && row.kind === "window" && !!row.address
}

// Whether `row` is one of the page's slot rows: a slot's window, a Missing
// slot or an empty one (not an overflowing window or a stray).
function isSlotRow(row) {
  if (!row) return false
  if (row.kind === "missing" || row.kind === "empty") return true
  return row.kind === "window" && (row.status === "slot" || row.status === "manual")
}

// What letting `source` (the dragged row) go over `target` does on
// workspace `workspace`'s page: target is { row } (the row under the
// pointer), { others: true } (the other windows, or the list's empty space
// below its rows) or null (anywhere else). One of
//   { kind: "assign", option, label }   a with that slot (option as
//                                       slotOptions has it, what a's prompt
//                                       answers with)
//   { kind: "unassign", plan, label }   u on the window (unassignPlan's plan)
//   { kind: "none" }                    nothing: a cancelled drag
function dropAction(state, workspace, source, target) {
  var none = { kind: "none" }
  if (!canDrag(source) || !target) return none
  var row = target.row || null
  if (row && isSlotRow(row)) {
    if (isSlotRow(source) && source.slot === row.slot) return none
    var options = slotOptions(state, workspace)
    for (var i = 0; i < options.length; i++) {
      if (options[i].slot === row.slot) return { kind: "assign", option: options[i], label: "Assign to " + row.slot }
    }
    return none
  }
  // the other windows: only a window in a slot has one to leave
  if (!isSlotRow(source)) return none
  var plan = unassignPlan(state, source)
  if (plan.error) return none
  return { kind: "unassign", plan: plan, label: "Unassign" }
}
