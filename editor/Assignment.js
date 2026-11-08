.pragma library

// The Assignment view's model: which live window fills which slot, read off
// one api `state` reply (docs/design.md §9). Ported from aerolayout's
// AssignmentView (views.py): a table of the windows on a workspace, each with
// its slot, plus a placeholder row for every slot whose window is not
// running; `a` puts the selected window into a global slot and makes its spec
// the workspace's for that slot (as aerolayout's `a` wrote the spec), `c`
// clears a workspace's spec for a slot, `u` takes a window out. Pure, so node
// can test it (editor/tests/assignment.test.mjs).
//
// A row is
//   { kind: "window" | "missing" | "empty", status, address, cls, title,
//     workspaceId, workspace, slot, role, spec }
// (workspaceId the Hyprland workspace id the window is on, workspace the
// number 1 to 10 of its slot or its workspace)
// with status one of "slot" (matched by its spec), "manual" (assigned by
// hand), "overflow" (matches `slot`, which is taken: in the workspace's
// overflow leaf), "unassigned" (taken out of its slot by hand), "none" (matches no
// spec), "missing" (a slot whose window is not open: the spec it waits
// for), "empty" (a slot of the workspace with no window and no spec: nothing
// says what fills it, so nothing is missing).

function workspaceList(state) {
  return state && Array.isArray(state.used_workspaces) ? state.used_workspaces : []
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

// The workspace number (1 to 10) a Hyprland workspace id is in the active
// arrangement, or null.
function workspaceOf(state, id) {
  var entry = workspaceEntry(state, id)
  return entry ? entry.workspace : null
}

function activeArrangement(state) {
  if (!state || !state.arrangements || !state.arrangement) return null
  return state.arrangements[state.arrangement] || null
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

// The slots of a workspace as [{ slot, role }]: those the active
// arrangement's trees place, in tree order, screen role by screen role, then
// any the workspace has a spec for that no tree shows (role null), by name.
function slotOrder(state, workspace) {
  var out = []
  var seen = {}
  var specs = workspaceSpecs(state, workspace)
  var arrangement = activeArrangement(state)
  var branches = arrangement && arrangement.workspaces ? arrangement.workspaces[String(workspace)] || {} : {}
  var roles = arrangement && Array.isArray(arrangement.roles) ? arrangement.roles : []
  for (var r = 0; r < roles.length; r++) {
    var branch = branches[roles[r]]
    var slots = branch && Array.isArray(branch.slots) ? branch.slots : []
    for (var s = 0; s < slots.length; s++) {
      if (!seen[slots[s]]) {
        seen[slots[s]] = true
        out.push({ slot: slots[s], role: roles[r] })
      }
    }
  }
  var rest = Object.keys(specs).filter(function(name) { return !seen[name] }).sort()
  for (var i = 0; i < rest.length; i++) out.push({ slot: rest[i], role: null })
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
    role: entry ? entry.role : null,
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
      if (!row.role) row.role = slots[i].role
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
        role: slots[i].role,
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

// What a Missing row's App column says: the spec it waits for ("" for an
// empty slot).
function specText(row) {
  return row.spec ? row.spec : ""
}

// What the Title column says: "Missing" for a slot whose window is not
// open, a dash for an empty one, else the window's title.
function titleText(row) {
  if (row.kind === "missing") return "Missing"
  if (row.kind === "empty") return "—"
  return row.title || "No Title"
}

// What `u` does for a row: { address, clearSpec, question } (the y/n it
// asks) or { error }. A window in a slot leaves it with the workspace's spec
// for it (api unassign with clear_spec), so the slot is left empty instead of
// Missing that window; an overflowing window, or one in a slot the workspace
// has no spec for, is only taken out.
function unassignPlan(state, row) {
  if (!row) return { error: "Nothing selected." }
  if (row.kind !== "window") return { error: "No window in " + row.slot + " to unassign." }
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

// What `c` clears for a row: { workspace, slot, spec } (the workspace's spec
// for a slot whose window is not open, a Missing row), or { error }. A window in
// a slot is u's: it takes the window out and clears the spec with it.
function clearTarget(state, workspace, row) {
  if (!row) return { error: "Nothing selected." }
  if (row.status === "slot" || row.status === "manual" || row.status === "overflow") {
    return { error: row.cls + " is open in " + row.slot
      + ": u takes it out and clears the spec with it (c clears a slot whose window is not open)." }
  }
  if (row.kind === "window") {
    return { error: (row.cls || "This window") + " is in no slot, so there is no spec to clear." }
  }
  var on = row.workspace !== null && row.workspace !== undefined ? row.workspace : workspace
  var spec = workspaceSpecs(state, on)[row.slot]
  if (spec === undefined) return { error: "Workspace " + on + " has no spec for " + row.slot + "." }
  return { workspace: on, slot: row.slot, spec: String(spec) }
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
