.pragma library

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
//     workspaceId, workspace, slot, screen, spec, placed }
// (placed false: a global slot no tree of the active layout places on the
// workspace, listed after the placed ones and looking just like them; `a`
// into it places it)
// (workspaceId the Hyprland workspace id the window is on, workspace the
// number 1 to 10 of its slot or its workspace, screen its screen number on
// the active desk)
// with status one of "slot" (matched by its spec), "manual" (assigned by
// hand), "overflow" (matches `slot`, which is taken: in the workspace's
// overflow leaf), "unassigned" (taken out of its slot by hand), "none" (matches no
// spec), "missing" (a slot whose window is not open: the spec it waits
// for), "empty" (a slot of the workspace with no window and no spec: nothing
// says what fills it, so nothing is missing).

// The workspaces with a page: of the engine's used workspaces (specs, or
// trees in any layout), those the active layout shows trees for or that
// have specs; a workspace only another layout places slots on has nothing
// to show here.
function workspaceList(state) {
  var used = state && Array.isArray(state.used_workspaces) ? state.used_workspaces : []
  var specs = (state && state.specs) || {}
  var layout = state && state.layouts && state.layout ? state.layouts[state.layout] : null
  var shows = layout && layout.workspaces ? layout.workspaces : {}
  return used.filter(function(n) {
    var trees = shows[String(n)]
    var spec = specs[String(n)]
    return (!!trees && Object.keys(trees).length > 0) || (!!spec && Object.keys(spec).length > 0)
  })
}

// The pages ←/→ move through: every window, then each workspace.
function pages(state) {
  var out = [{ workspace: null, label: "All windows" }]
  var numbers = workspaceList(state)
  for (var i = 0; i < numbers.length; i++) out.push({ workspace: numbers[i], label: "Workspace " + numbers[i] })
  return out
}

function workspaceEntry(state, id) {
  if (!state || !state.workspaces || id === null || id === undefined) return null
  return state.workspaces[String(id)] || null
}

// The workspace number (1 to 10) a Hyprland workspace id is on the active
// desk, or null.
function workspaceOf(state, id) {
  var entry = workspaceEntry(state, id)
  return entry ? entry.workspace : null
}

function activeLayout(state) {
  if (!state || !state.layouts || !state.layout) return null
  return state.layouts[state.layout] || null
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

// The slots of a workspace as [{ slot, screen, placed }]: those the active
// layout's trees for it place (its own, else the default ones), in tree
// order, screen by screen, then every other global slot (screen null, placed
// false), by name, with any the workspace has a spec for
// that is no global slot among them.
function slotOrder(state, workspace) {
  var out = []
  var seen = {}
  var specs = workspaceSpecs(state, workspace)
  var layout = activeLayout(state)
  var branches = layout && layout.workspaces ? layout.workspaces[String(workspace)] || {} : {}
  var count = layout ? layout.screens || 0 : 0
  for (var r = 1; r <= count; r++) {
    var branch = branches[String(r)]
    var slots = branch && Array.isArray(branch.slots) ? branch.slots : []
    for (var s = 0; s < slots.length; s++) {
      if (!seen[slots[s]]) {
        seen[slots[s]] = true
        out.push({ slot: slots[s], screen: r, placed: true })
      }
    }
  }
  var others = {}
  slotNames(state).concat(Object.keys(specs)).forEach(function(name) { if (!seen[name]) others[name] = true })
  var rest = Object.keys(others).sort()
  for (var i = 0; i < rest.length; i++) out.push({ slot: rest[i], screen: null, placed: false })
  return out
}

function windowList(state) {
  return state && Array.isArray(state.windows) ? state.windows : []
}

function isManual(state, address) {
  var a = state && state.assignments ? state.assignments[address] : null
  return !!(a && a.manual)
}

function windowRow(state, w) {
  var entry = workspaceEntry(state, w.workspace_id)
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
    placed: true,
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

// The rows of one page: `workspace` a workspace number, or null for every
// window.
function rows(state, workspace) {
  if (!state) return []
  var windows = windowList(state)
  var held = holders(state)
  var out = []
  var used = {}
  var i

  if (workspace === null || workspace === undefined) {
    var numbers = workspaceList(state)
    for (var d = 0; d < numbers.length; d++) {
      var order = slotOrder(state, numbers[d])
      for (var s = 0; s < order.length; s++) {
        var holder = held[numbers[d] + "/" + order[s].slot]
        if (holder) {
          used[holder.address] = true
          out.push(windowRow(state, holder))
        }
      }
    }
    for (i = 0; i < windows.length; i++) {
      if (!used[windows[i].address] && windows[i].slot !== undefined && windows[i].slot !== null) {
        used[windows[i].address] = true // a slot of a workspace the list does not name
        out.push(windowRow(state, windows[i]))
      }
    }
    for (i = 0; i < windows.length; i++) {
      if (!used[windows[i].address] && windows[i].overflow) {
        used[windows[i].address] = true
        out.push(windowRow(state, windows[i]))
      }
    }
    var rest = windows.filter(function(w) { return !used[w.address] })
    rest.sort(function(a, b) {
      if (a.workspace_id !== b.workspace_id) return (a.workspace_id || 0) - (b.workspace_id || 0)
      return a.address < b.address ? -1 : a.address > b.address ? 1 : 0
    })
    for (i = 0; i < rest.length; i++) out.push(windowRow(state, rest[i]))
    return out
  }

  var slots = slotOrder(state, workspace)
  var specs = workspaceSpecs(state, workspace)
  for (i = 0; i < slots.length; i++) {
    var w = held[workspace + "/" + slots[i].slot]
    if (w) {
      used[w.address] = true
      var row = windowRow(state, w)
      if (!row.screen) row.screen = slots[i].screen
      row.placed = slots[i].placed
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
        placed: slots[i].placed,
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
  case "overflow": return "overflow (" + row.slot + ")"
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

// What the Title column says: "Missing" for a slot whose window is not
// open, a dash for an empty one (placed by a tree or not: they look the
// same), else the window's title.
function titleText(row) {
  if (row.kind === "missing") return "Missing"
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
      question: "Clear workspace " + row.workspace + "'s spec for " + row.slot + " (" + text + ")? The slot is left empty" }
  }
  if (row.kind !== "window") {
    return { error: "Workspace " + row.workspace + " has no spec for " + row.slot
      + " and no window in it: there is nothing to unassign." }
  }
  if (row.status === "overflow") {
    return { address: row.address, clearSpec: false, question: "Take " + row.cls + " out of the overflow of " + row.slot + "?" }
  }
  if (row.status !== "slot" && row.status !== "manual") return { error: row.cls + " is in no slot." }
  var spec = workspaceSpecs(state, row.workspace)[row.slot]
  if (spec === undefined) {
    return { address: row.address, clearSpec: false, question: "Unassign " + row.cls + " from " + row.slot + "?" }
  }
  return { address: row.address, clearSpec: true, question: "Unassign " + row.cls + " from " + row.slot
    + " and clear workspace " + row.workspace + "'s spec for it (" + spec + ")? (the slot is left empty)" }
}

// The workspace `a` assigns on (and writes the spec into): the page's
// workspace; on the every-window page the row's workspace, else the number of
// the workspace it is on, else `focusedNumber` (the focused workspace's); null
// when there is none.
function assignWorkspace(state, workspace, row, focusedNumber) {
  if (workspace !== null && workspace !== undefined) return workspace
  if (row && row.workspace !== null && row.workspace !== undefined) return row.workspace
  var own = row ? workspaceOf(state, row.workspaceId) : null
  if (own !== null) return own
  return focusedNumber === undefined ? null : focusedNumber
}

function assignTitle(workspace) {
  return "Assign to workspace " + workspace + " slot (takes its spec)"
}

// The slots `a` offers for a row: every global slot, on the workspace
// assignWorkspace picks (none without one), the workspace's own in tree order
// first, then the rest by name. Each option is { key, workspace, slot, spec
// (the workspace's spec for it, "" for none), holder } where holder is the
// address in the slot (or null) and key the letter that picks it: the slot's
// first letter, or the first digit still free when that letter is taken
// (aerolayout's rule); "" when there is none left (pick it with the arrows).
function slotOptions(state, workspace, row, focusedNumber) {
  var on = assignWorkspace(state, workspace, row, focusedNumber)
  if (on === null) return []
  var held = holders(state)
  var specs = workspaceSpecs(state, on)
  var names = slotOrder(state, on).map(function(o) { return o.slot })
  var listed = {}
  names.forEach(function(n) { listed[n] = true })
  slotNames(state).forEach(function(n) {
    if (!listed[n]) {
      listed[n] = true
      names.push(n)
    }
  })
  var used = {}
  var out = []
  for (var s = 0; s < names.length; s++) {
    var name = names[s]
    var key = name.charAt(0).toLowerCase()
    if (used[key]) {
      key = ""
      for (var n = 1; n <= 9; n++) {
        if (!used[String(n)]) {
          key = String(n)
          break
        }
      }
    }
    if (key !== "") used[key] = true
    var holder = held[on + "/" + name]
    out.push({ key: key, workspace: on, slot: name, spec: specs[name] !== undefined ? String(specs[name]) : "",
      holder: holder ? holder.address : null })
  }
  return out
}

// The slot options as Prompts.js choice options ({ key, label, value });
// the value is the slot option.
function promptOptions(options) {
  return options.map(function(o) {
    return { key: o.key, label: o.slot, value: o }
  })
}

// The page to open on: the focused workspace's number, else every window.
// The page of workspace `workspace` (the digit keys jump to it), -1 when it
// has none.
function pageOfWorkspace(state, workspace) {
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].workspace === workspace) return i
  return -1
}

function initialPage(state, workspaceId) {
  var workspace = workspaceOf(state, workspaceId)
  if (workspace === null) return 0
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].workspace === workspace) return i
  return 0
}

// The line under the header on a page with slots no tree places, when other
// desks share the active layout: `a` into one of them places it in that
// layout, so there too. "" otherwise.
function placeNote(state, rows) {
  var unplaced = (rows || []).some(function(r) { return r.placed === false })
  var l = activeLayout(state)
  if (!unplaced || !l) return ""
  var others = (Array.isArray(l.used_by) ? l.used_by : []).filter(function(d) { return d !== state.desk })
  if (others.length === 0) return ""
  return "Layout '" + state.layout + "' is also used by " + (others.length === 1 ? "desk " : "desks ") + others.join(", ")
    + ": a on a slot its trees lack places it there too."
}

// What the message after `a` adds when take_spec placed the slot (its reply's
// `placed`): the tree it went into, and the other desks using that layout.
// "" when it placed nothing.
function placedText(reply, desk) {
  var p = reply && reply.placed
  if (!p) return ""
  var others = (Array.isArray(p.used_by) ? p.used_by : []).filter(function(d) { return d !== desk })
  return "placed " + reply.slot + " in layout " + p.layout + ", workspace " + reply.workspace + " screen " + p.screen + ": "
    + p.tree + (others.length ? " (also used by " + others.join(", ") + ")" : "")
}
