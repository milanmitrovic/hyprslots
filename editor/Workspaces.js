.pragma library

// Workspace keys, the same in the Layout and Assignment views (docs/design.md
// §9): [ and ] step through workspaces 1 to 10 (Omarchy's ten workspaces per
// screen), the digits jump to one as Super+N does (0 is workspace 10). The
// arrows stay the view's own; `-` is the layout's default trees in the
// Layout view. Pure, so node can test it
// (editor/tests/workspaces.test.mjs).

var COUNT = 10

// The workspace `delta` (+1 or -1) on from `workspace`, round from 10 to 1 and
// back.
function step(workspace, delta) {
  if (!(workspace >= 1 && workspace <= COUNT)) return delta > 0 ? 1 : COUNT
  return ((workspace - 1 + delta) % COUNT + COUNT) % COUNT + 1
}

// The workspace a digit key jumps to, or null for any other text.
function ofDigit(text) {
  if (typeof text !== "string" || text.length !== 1 || text < "0" || text > "9") return null
  return text === "0" ? COUNT : Number(text)
}

// Workspaces 1 to 10 for a header strip, then the layout's default trees
// (`-`): { workspace (1..10 or "default"), label (the key: 0 for 10, "def"),
// current, trees (trees of its own; the default ones when there are any),
// shared (no trees of its own, showing the default ones) }.
function strip(state, layout, current) {
  var entry = state && state.layouts ? state.layouts[layout] : null
  var own = entry && Array.isArray(entry.own) ? entry.own.map(Number) : []
  var shows = entry && entry.workspaces ? entry.workspaces : {}
  var out = []
  for (var n = 1; n <= COUNT; n++) {
    var mine = own.indexOf(n) >= 0
    var branches = shows[String(n)]
    out.push({ workspace: n, label: String(n % COUNT), current: n === current, trees: mine,
      shared: !mine && !!branches && Object.keys(branches).length > 0 })
  }
  var def = entry && entry.default ? entry.default : {}
  out.push({ workspace: "default", label: "def", current: current === "default", trees: Object.keys(def).length > 0,
    shared: false })
  return out
}
