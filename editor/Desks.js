.pragma library

// Desk keys, the same in the Layout and Assignment views (docs/design.md §9):
// [ and ] step through desks 1 to 10 (Omarchy's ten workspaces per screen),
// the digits jump to one as Super+N does (0 is desk 10). The arrows stay the
// view's own. Pure, so node can test it (editor/tests/desks.test.mjs).

var COUNT = 10

// The desk `delta` (+1 or -1) on from `desk`, round from 10 to 1 and back.
function step(desk, delta) {
  if (!(desk >= 1 && desk <= COUNT)) return delta > 0 ? 1 : COUNT
  return ((desk - 1 + delta) % COUNT + COUNT) % COUNT + 1
}

// The desk a digit key jumps to, or null for any other text.
function ofDigit(text) {
  if (typeof text !== "string" || text.length !== 1 || text < "0" || text > "9") return null
  return text === "0" ? COUNT : Number(text)
}

// Desks 1 to 10 for a header strip: { desk, label (the key: 0 for 10),
// current, trees (the arrangement has a tree for the desk) }.
function strip(state, arrangement, current) {
  var entry = state && state.arrangements ? state.arrangements[arrangement] : null
  var desks = entry && entry.desks ? entry.desks : {}
  var out = []
  for (var d = 1; d <= COUNT; d++) {
    var branches = desks[String(d)]
    out.push({ desk: d, label: String(d % COUNT), current: d === current,
      trees: !!branches && Object.keys(branches).length > 0 })
  }
  return out
}
