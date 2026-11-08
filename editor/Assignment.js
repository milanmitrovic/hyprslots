.pragma library

// The Assignment view's model: which live window fills which slot, read off
// one api `state` reply (docs/design.md §9). Ported from aerolayout's
// AssignmentView (views.py): a table of the windows on a desk, each with its
// slot, plus a placeholder row for every slot whose window is not running;
// `a` puts the selected window into a global slot and makes its spec the
// desk's for that slot (as aerolayout's `a` wrote the spec), `c` clears a
// desk's spec for a slot, `u` takes a window out. Pure, so node can test it
// (editor/tests/assignment.test.mjs).
//
// A row is
//   { kind: "window" | "missing", status, address, cls, title, workspace,
//     desk, slot, role, spec }
// with status one of "slot" (matched by its spec), "manual" (assigned by
// hand), "overflow" (matches `slot`, which is taken: in the desk's overflow
// leaf), "unassigned" (taken out of its slot by hand), "none" (matches no
// spec), "missing" (a slot with no window: the spec it waits for, "" when
// the desk has none for it).

function deskList(state) {
  return state && Array.isArray(state.desks) ? state.desks : []
}

// The pages ←/→ move through: every window, then each desk.
function pages(state) {
  var out = [{ desk: null, label: "All windows" }]
  var desks = deskList(state)
  for (var i = 0; i < desks.length; i++) out.push({ desk: desks[i], label: "Desk " + desks[i] })
  return out
}

function workspaceEntry(state, id) {
  if (!state || !state.workspaces || id === null || id === undefined) return null
  return state.workspaces[String(id)] || null
}

// The desk a workspace is of in the active arrangement, or null.
function deskOfWorkspace(state, id) {
  var entry = workspaceEntry(state, id)
  return entry ? entry.desk : null
}

function activeArrangement(state) {
  if (!state || !state.arrangements || !state.arrangement) return null
  return state.arrangements[state.arrangement] || null
}

// The desk's specs: slot -> spec text.
function deskSpecs(state, desk) {
  return (state && state.specs && state.specs[String(desk)]) || {}
}

// The global slot names, in the state's order (by name).
function slotNames(state) {
  var list = state && Array.isArray(state.slots) ? state.slots : []
  return list.map(function(s) { return s.name })
}

// The slots of a desk as [{ slot, role }]: those the active arrangement's
// trees place, in tree order, screen role by screen role, then any the desk
// has a spec for that no tree shows (role null), by name.
function slotOrder(state, desk) {
  var out = []
  var seen = {}
  var specs = deskSpecs(state, desk)
  var arrangement = activeArrangement(state)
  var branches = arrangement && arrangement.desks ? arrangement.desks[String(desk)] || {} : {}
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
  var entry = workspaceEntry(state, w.workspace)
  var row = {
    kind: "window",
    address: w.address,
    cls: w.class || "",
    title: w.title || "",
    workspace: w.workspace,
    desk: entry ? entry.desk : null,
    slot: null,
    role: entry ? entry.role : null,
    spec: null,
    status: w.unassigned ? "unassigned" : "none",
  }
  if (w.slot !== undefined && w.slot !== null) {
    row.desk = w.desk
    row.slot = w.slot
    row.status = isManual(state, w.address) ? "manual" : "slot"
  } else if (w.overflow) {
    row.desk = w.overflow.desk
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
    if (w.slot !== undefined && w.slot !== null) out[w.desk + "/" + w.slot] = w
  }
  return out
}

// The rows of one page: `desk` a desk number, or null for every window.
function rows(state, desk) {
  if (!state) return []
  var windows = windowList(state)
  var held = holders(state)
  var out = []
  var used = {}
  var i

  if (desk === null || desk === undefined) {
    var desks = deskList(state)
    for (var d = 0; d < desks.length; d++) {
      var order = slotOrder(state, desks[d])
      for (var s = 0; s < order.length; s++) {
        var holder = held[desks[d] + "/" + order[s].slot]
        if (holder) {
          used[holder.address] = true
          out.push(windowRow(state, holder))
        }
      }
    }
    for (i = 0; i < windows.length; i++) {
      if (!used[windows[i].address] && windows[i].slot !== undefined && windows[i].slot !== null) {
        used[windows[i].address] = true // a slot of a desk the list does not name
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
      if (a.workspace !== b.workspace) return (a.workspace || 0) - (b.workspace || 0)
      return a.address < b.address ? -1 : a.address > b.address ? 1 : 0
    })
    for (i = 0; i < rest.length; i++) out.push(windowRow(state, rest[i]))
    return out
  }

  var slots = slotOrder(state, desk)
  var specs = deskSpecs(state, desk)
  for (i = 0; i < slots.length; i++) {
    var w = held[desk + "/" + slots[i].slot]
    if (w) {
      used[w.address] = true
      var row = windowRow(state, w)
      if (!row.role) row.role = slots[i].role
      out.push(row)
    } else {
      out.push({
        kind: "missing",
        status: "missing",
        address: null,
        cls: "",
        title: "",
        workspace: null,
        desk: desk,
        slot: slots[i].slot,
        role: slots[i].role,
        spec: specs[slots[i].slot] !== undefined ? String(specs[slots[i].slot]) : "",
      })
    }
  }
  for (i = 0; i < windows.length; i++) {
    if (!used[windows[i].address] && windows[i].overflow && windows[i].overflow.desk === desk) {
      used[windows[i].address] = true
      out.push(windowRow(state, windows[i]))
    }
  }
  for (i = 0; i < windows.length; i++) {
    var other = windows[i]
    if (!used[other.address] && deskOfWorkspace(state, other.workspace) === desk
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
  default: return "—"
  }
}

// What a Missing row's App column says: the spec it waits for.
function specText(row) {
  return row.spec ? row.spec : "(no spec)"
}

// The desk `a` assigns on (and writes the spec into): the page's desk; on
// the every-window page the row's desk, else the desk of its workspace,
// else `focusedDesk` (the focused workspace's); null when there is none.
function assignDesk(state, desk, row, focusedDesk) {
  if (desk !== null && desk !== undefined) return desk
  if (row && row.desk !== null && row.desk !== undefined) return row.desk
  var own = row ? deskOfWorkspace(state, row.workspace) : null
  if (own !== null) return own
  return focusedDesk === undefined ? null : focusedDesk
}

function assignTitle(desk) {
  return "Assign to desk " + desk + " slot (takes its spec)"
}

// The slots `a` offers for a row: every global slot, on the desk
// assignDesk picks (none without one), the desk's own in tree order first,
// then the rest by name. Each option is { key, desk, slot, spec (the desk's
// spec for it, "" for none), holder } where holder is the address in the
// slot (or null) and key the letter that picks it: the slot's first letter,
// or the first digit still free when that letter is taken (aerolayout's
// rule); "" when there is none left (pick it with the arrows).
function slotOptions(state, desk, row, focusedDesk) {
  var on = assignDesk(state, desk, row, focusedDesk)
  if (on === null) return []
  var held = holders(state)
  var specs = deskSpecs(state, on)
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
    out.push({ key: key, desk: on, slot: name, spec: specs[name] !== undefined ? String(specs[name]) : "",
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

// What `c` clears for a row: { desk, slot, spec } (the desk's spec for the
// row's slot), or { error }.
function clearTarget(state, desk, row) {
  if (!row) return { error: "Nothing selected." }
  if (row.kind !== "missing" && row.status !== "slot" && row.status !== "manual" && row.status !== "overflow") {
    return { error: (row.cls || "This window") + " is in no slot, so there is no spec to clear." }
  }
  var on = row.desk !== null && row.desk !== undefined ? row.desk : desk
  var spec = deskSpecs(state, on)[row.slot]
  if (spec === undefined) return { error: "Desk " + on + " has no spec for " + row.slot + "." }
  return { desk: on, slot: row.slot, spec: String(spec) }
}

// The page to open on: the focused workspace's desk, else every window.
// The page of desk `desk` (the digit keys jump to it), -1 when it has none.
function pageOfDesk(state, desk) {
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].desk === desk) return i
  return -1
}

function initialPage(state, workspaceId) {
  var desk = deskOfWorkspace(state, workspaceId)
  if (desk === null) return 0
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].desk === desk) return i
  return 0
}
