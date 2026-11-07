.pragma library

// Read-only summaries of an api `state` for the tabs whose editors arrive in
// later slices (Layout: D2; Slots, Arrangements: D3), so each tab already
// shows what it will edit. Pure (editor/tests/summary.test.mjs).

function pad(text, width) {
  var s = String(text)
  while (s.length < width) s += " "
  return s
}

function widest(items) {
  var w = 0
  for (var i = 0; i < items.length; i++) w = Math.max(w, String(items[i]).length)
  return w
}

function layoutLines(state) {
  var arrangement = state.arrangements && state.arrangements[state.arrangement]
  if (!arrangement) return []
  var roles = arrangement.roles || []
  var width = widest(roles)
  var out = []
  var desks = state.desks || []
  for (var d = 0; d < desks.length; d++) {
    var branches = (arrangement.desks || {})[String(desks[d])] || {}
    for (var r = 0; r < roles.length; r++) {
      var branch = branches[roles[r]]
      if (!branch) continue
      out.push("desk " + desks[d] + "  " + pad(roles[r], width) + "  " + branch.tree + "   ratio " + branch.ratio
        + (branch.resized ? "   (resized, unsaved)" : ""))
    }
  }
  return out
}

function slotLines(state) {
  var out = []
  var desks = state.desks || []
  for (var d = 0; d < desks.length; d++) {
    var specs = (state.slots || {})[String(desks[d])] || {}
    var names = Object.keys(specs).sort()
    var width = widest(names)
    for (var i = 0; i < names.length; i++) out.push("desk " + desks[d] + "  " + pad(names[i], width) + "  " + specs[names[i]])
  }
  return out
}

function arrangementLines(state) {
  var out = []
  var names = Object.keys(state.arrangements || {}).sort()
  for (var i = 0; i < names.length; i++) {
    var a = state.arrangements[names[i]]
    var screens = Object.keys(a.screens || {}).sort().map(function(role) { return role + " = " + a.screens[role] })
    var marks = []
    if (a.active) marks.push("(active)")
    if (a.read_only) marks.push("(set in config.lua)")
    out.push(names[i] + "  " + (marks.length ? marks.join(" ") + "  " : "") + screens.join(", "))
  }
  return out
}

// The lines a tab ("Layout", "Slots", "Arrangements") shows.
function lines(state, view) {
  if (!state) return []
  if (view === "Layout") return layoutLines(state)
  if (view === "Slots") return slotLines(state)
  if (view === "Arrangements") return arrangementLines(state)
  return []
}
