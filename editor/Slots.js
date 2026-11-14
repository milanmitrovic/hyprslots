.pragma library

// The slot list's model (the Layout view's list beside the screens,
// aerolayout's logical slots): the global slots, defined once for every
// workspace, each with its optional description; read off one api `state`
// reply (docs/design.md §9). The list shows the name and description only; a
// row also knows the trees that place the slot and the workspaces that fill
// it, which a delete names. Which app fills a slot on a workspace is set from
// the Assignment view. Pure, so node can test it (editor/tests/slots.test.mjs).
//
// A row is { slot, key (its stored key, docs/design.md §4; "" for none),
//   description, places: ["dual/3/1", "dual/default/1", ...]
//   (layout/workspace/screen of every tree that places it, as remove_slot
//   names them; a workspace showing the default trees has none of its own),
//   specs: [{ workspace, spec }, ...] }.

function slotList(state) {
  return state && Array.isArray(state.slots) ? state.slots : []
}

function numeric(a, b) {
  return Number(a) - Number(b)
}

function rows(state) {
  if (!state) return []
  var layouts = state.layouts || {}
  var names = Object.keys(layouts).sort()
  var specs = state.specs || {}
  var filling = Object.keys(specs).sort(numeric)
  return slotList(state).map(function(entry) {
    var slot = entry.name
    var places = []
    var placed = function(name, workspace, branches, count) {
      for (var screen = 1; screen <= count; screen++) {
        var branch = (branches || {})[String(screen)]
        if (branch && Array.isArray(branch.slots) && branch.slots.indexOf(slot) >= 0) {
          places.push(name + "/" + workspace + "/" + screen)
        }
      }
    }
    for (var n = 0; n < names.length; n++) {
      var l = layouts[names[n]]
      var count = l.screens || 0
      placed(names[n], "default", l.default, count)
      var own = (Array.isArray(l.own) ? l.own : []).map(Number).sort(numeric)
      for (var d = 0; d < own.length; d++) placed(names[n], own[d], (l.workspaces || {})[String(own[d])], count)
    }
    var filled = []
    for (var i = 0; i < filling.length; i++) {
      var text = specs[filling[i]] ? specs[filling[i]][slot] : undefined
      if (text !== undefined) filled.push({ workspace: Number(filling[i]), spec: String(text) })
    }
    return {
      slot: slot,
      key: entry.key ? String(entry.key) : "",
      description: entry.description ? String(entry.description) : "",
      places: places,
      specs: filled,
    }
  })
}

// The y/n `d` asks: every tree holds every slot, so the slot goes from every
// tree, and from the assignments of the workspaces that fill it (the engine
// refuses those without force).
function deleteQuestion(row) {
  var q = "Delete slot '" + row.slot + "'? It goes from every tree"
  if (row.specs.length) {
    var numbers = row.specs.map(function(s) { return s.workspace })
    q += " and from the assignments of workspace" + (numbers.length > 1 ? "s " : " ") + numbers.join(", ")
  }
  return q + "."
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
  if (cfg.editable === false) return "your config loads no editor data, so there is nothing the editor may change"
  var paths = Array.isArray(cfg.read_only) ? cfg.read_only : []
  for (var i = 0; i < paths.length; i++) {
    if (paths[i] === "slots") return "the slots are set by code in your config; edit them there"
  }
  return ""
}

// The slot list's a: the name prompt, and what it says once the engine made
// the slot (which it puts into every tree; nothing to place).
function newSlotLabel() {
  return "New slot name (every tree gets it; an empty slot takes no room) [Enter] next  [Esc] cancel: "
}

function addedText(slot) {
  return "Added slot '" + slot + "' to every tree. Ctrl+S saves."
}

// The slot list's K: the slot's key, the letter that picks it in every
// slot-choice prompt (api set_slot_key). The prompt for it, its answer read
// (trimmed, lower case) and checked here as the engine checks it, so a
// refusal shows before anything is sent: { key } or { error }; and what the
// list says once it is set.
function keyLabel(row) {
  return "Key for '" + row.slot + "' (one letter a-z; " + (row.key ? "now " + row.key : "none now")
    + ") [Enter] set  [Esc] cancel: "
}

function keyAnswer(rows, slot, text) {
  var key = String(text).trim().toLowerCase()
  if (!/^[a-z]$/.test(key)) return { error: "A slot's key is one letter a-z (the digits jump workspaces)." }
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].slot !== slot && rows[i].key === key) return { error: key + " is the key of slot '" + rows[i].slot + "' already." }
  }
  return { key: key }
}

function keyedText(slot, key) {
  return "Slot '" + slot + "' is picked with " + key + " now. Ctrl+S saves."
}
