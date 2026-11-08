.pragma library

// The Slots view's model (aerolayout's logical slots): the global slots,
// defined once for every desk, each with its description, the trees that
// place it and the desks that say which app fills it; read off one api
// `state` reply (docs/design.md §9). Which app fills a slot on a desk is
// set from the Assignment view. Pure, so node can test it
// (editor/tests/slots.test.mjs).
//
// A row is { slot, description, places: ["dual/3/big", ...] (arrangement/
//   desk/role of every tree that places it), specs: [{ desk, spec }, ...] }.

function slotList(state) {
  return state && Array.isArray(state.slots) ? state.slots : []
}

function numeric(a, b) {
  return Number(a) - Number(b)
}

function rows(state) {
  if (!state) return []
  var arrangements = state.arrangements || {}
  var names = Object.keys(arrangements).sort()
  var specs = state.specs || {}
  var desks = Object.keys(specs).sort(numeric)
  return slotList(state).map(function(entry) {
    var slot = entry.name
    var places = []
    for (var n = 0; n < names.length; n++) {
      var a = arrangements[names[n]]
      var deskMap = a.desks || {}
      var deskKeys = Object.keys(deskMap).sort(numeric)
      for (var d = 0; d < deskKeys.length; d++) {
        var branches = deskMap[deskKeys[d]] || {}
        var roles = Array.isArray(a.roles) ? a.roles : Object.keys(branches).sort()
        for (var r = 0; r < roles.length; r++) {
          var branch = branches[roles[r]]
          if (branch && Array.isArray(branch.slots) && branch.slots.indexOf(slot) >= 0) {
            places.push(names[n] + "/" + deskKeys[d] + "/" + roles[r])
          }
        }
      }
    }
    var filled = []
    for (var i = 0; i < desks.length; i++) {
      var text = specs[desks[i]] ? specs[desks[i]][slot] : undefined
      if (text !== undefined) filled.push({ desk: Number(desks[i]), spec: String(text) })
    }
    return {
      slot: slot,
      description: entry.description ? String(entry.description) : "",
      places: places,
      specs: filled,
    }
  })
}

function placesText(row) {
  return row.places.length ? row.places.join(", ") : "no tree"
}

function specsText(row) {
  if (!row.specs.length) return "no desk"
  return row.specs.map(function(s) { return s.desk + " " + s.spec }).join(", ")
}

// The y/n `d` asks: plain when nothing uses the slot, else every tree and
// desk it goes from (the engine refuses those without force).
function deleteQuestion(row) {
  var q = "Delete slot '" + row.slot + "'?"
  var parts = []
  if (row.places.length) parts.push("the trees " + row.places.join(", "))
  if (row.specs.length) {
    var desks = row.specs.map(function(s) { return s.desk })
    parts.push("the specs of desk" + (desks.length > 1 ? "s " : " ") + desks.join(", "))
  }
  if (parts.length) q += " It goes from " + parts.join(" and ") + "."
  return q
}

// Whether a delete needs the engine's force (something uses the slot).
function inUse(row) {
  return row.places.length > 0 || row.specs.length > 0
}

// Why the editor may not change the slots, "" when it may (the engine
// refuses the same; saying so first spares typing an answer it will refuse).
function readOnlyReason(state) {
  var cfg = state && state.config
  if (!cfg) return ""
  if (cfg.editable === false) return "config.lua loads no slots.lua, so there is nothing the editor may change"
  var paths = Array.isArray(cfg.read_only) ? cfg.read_only : []
  for (var i = 0; i < paths.length; i++) {
    if (paths[i] === "slots") return "the slots are set by code in config.lua; edit them there"
  }
  return ""
}
