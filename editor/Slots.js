.pragma library

// The Slots view's model (aerolayout's LogicalView, per desk): the slots of
// one desk with their specs and descriptions, where the trees of every
// arrangement place them, and the window each holds; read off one api
// `state` reply (docs/design.md §9). Pure, so node can test it
// (editor/tests/slots.test.mjs).
//
// A row is { slot, spec, description, role, places: ["dual/big", ...],
//   holder: { address, cls, title } | null }: role is the screen role the
// active arrangement places the slot on (null when no tree of it does).

var DESKS = 10

function slotsOf(state, desk) {
  return (state && state.slots && state.slots[String(desk)]) || {}
}

// Desks 1 to 10, each with how many slots it has.
function pages(state) {
  var out = []
  for (var d = 1; d <= DESKS; d++) {
    out.push({ desk: d, label: "Desk " + d, count: Object.keys(slotsOf(state, d)).length })
  }
  return out
}

// The page to open on: the focused workspace's desk, else the first desk
// with slots, else desk 1.
function initialPage(state, workspaceId) {
  var entry = state && state.workspaces && workspaceId !== null && workspaceId !== undefined
    ? state.workspaces[String(workspaceId)] : null
  if (entry && entry.desk >= 1 && entry.desk <= DESKS) return entry.desk - 1
  var list = pages(state)
  for (var i = 0; i < list.length; i++) if (list[i].count > 0) return i
  return 0
}

function windows(state) {
  return state && Array.isArray(state.windows) ? state.windows : []
}

function onDesk(state, w, desk) {
  if (w.desk === desk) return true
  var entry = state && state.workspaces ? state.workspaces[String(w.workspace)] : null
  return !!(entry && entry.desk === desk)
}

function rows(state, desk) {
  if (!state) return []
  var specs = slotsOf(state, desk)
  var descriptions = (state.descriptions && state.descriptions[String(desk)]) || {}
  var arrangements = state.arrangements || {}
  var names = Object.keys(arrangements).sort()
  var held = {}
  var ws = windows(state)
  for (var i = 0; i < ws.length; i++) {
    if (ws[i].desk === desk && ws[i].slot) held[ws[i].slot] = ws[i]
  }
  return Object.keys(specs).sort().map(function(slot) {
    var places = []
    var role = null
    for (var n = 0; n < names.length; n++) {
      var a = arrangements[names[n]]
      var branches = (a.desks && a.desks[String(desk)]) || {}
      var roles = Array.isArray(a.roles) ? a.roles : Object.keys(branches).sort()
      for (var r = 0; r < roles.length; r++) {
        var branch = branches[roles[r]]
        if (branch && Array.isArray(branch.slots) && branch.slots.indexOf(slot) >= 0) {
          places.push(names[n] + "/" + roles[r])
          if (names[n] === state.arrangement) role = roles[r]
        }
      }
    }
    var w = held[slot]
    return {
      slot: slot,
      spec: String(specs[slot]),
      description: descriptions[slot] ? String(descriptions[slot]) : "",
      role: role,
      places: places,
      holder: w ? { address: w.address, cls: w.class || "", title: w.title || "" } : null,
    }
  })
}

function placesText(row) {
  return row.places.length ? row.places.join(", ") : "no tree"
}

// The windows `t` (take spec from window) offers: the desk's first, then the
// rest, numbered 1-9 (then the arrows).
function windowOptions(state, desk) {
  var ws = windows(state)
  var first = ws.filter(function(w) { return onDesk(state, w, desk) })
  var rest = ws.filter(function(w) { return !onDesk(state, w, desk) })
  return first.concat(rest).map(function(w, i) {
    return { key: i < 9 ? String(i + 1) : "", label: (w.class || "?") + " — " + (w.title || "No Title"), value: w.address }
  })
}

// Classes to step through while typing a spec: the desk's windows first.
function specSuggestions(state, desk) {
  var seen = {}
  var out = []
  var ws = windows(state)
  var ordered = ws.filter(function(w) { return onDesk(state, w, desk) })
    .concat(ws.filter(function(w) { return !onDesk(state, w, desk) }))
  for (var i = 0; i < ordered.length; i++) {
    var cls = ordered[i].class
    if (cls && !seen[cls]) {
      seen[cls] = true
      out.push(cls)
    }
  }
  return out
}

function deleteQuestion(row, desk) {
  var q = "Delete slot '" + row.slot + "' from desk " + desk + "?"
  if (row.places.length) q += " It goes from " + row.places.join(", ") + "."
  return q
}

// Why the editor may not change a desk's slots, "" when it may (the engine
// refuses the same; saying so first spares typing an answer it will refuse).
function readOnlyReason(state, desk) {
  var cfg = state && state.config
  if (!cfg) return ""
  if (cfg.editable === false) return "config.lua loads no slots.lua, so there is nothing the editor may change"
  var paths = Array.isArray(cfg.read_only) ? cfg.read_only : []
  for (var i = 0; i < paths.length; i++) {
    if (paths[i] === "slots" || paths[i] === "slots." + desk) {
      return "desk " + desk + "'s slots are set by code in config.lua; edit them there"
    }
  }
  return ""
}
