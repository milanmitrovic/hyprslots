.pragma library

// Workspace keys, the same in the Layout and Assignment views (docs/design.md
// §9): [ and ] step through the workspaces hyprslots manages (state
// `workspace_count`, config `workspaces`: 1 to 10 by default, Omarchy's ten
// per screen), the digits jump to one as Super+N does (0 is workspace 10,
// no key when it manages fewer). The arrows stay the view's own; `-` is the
// layout's default trees in the Layout view. Pure, so node can test it
// (editor/tests/workspaces.test.mjs).

var COUNT = 10

// How many workspaces the engine manages, from a state reply.
function count(state) {
  var n = state && state.workspace_count
  return typeof n === "number" && n >= 1 && n <= COUNT ? n : COUNT
}

// The workspace `delta` (+1 or -1) on from `workspace`, round from the last
// (`last`, default 10) to 1 and back.
function step(workspace, delta, last) {
  var n = last || COUNT
  if (!(workspace >= 1 && workspace <= n)) return delta > 0 ? 1 : n
  return ((workspace - 1 + delta) % n + n) % n + 1
}

// The workspace a digit key jumps to (of 1 to `last`, default 10), or null
// for any other text.
function ofDigit(text, last) {
  if (typeof text !== "string" || text.length !== 1 || text < "0" || text > "9") return null
  var workspace = text === "0" ? COUNT : Number(text)
  return workspace <= (last || COUNT) ? workspace : null
}

// The managed workspaces for a header strip, then the layout's default
// trees (`-`): { workspace (1..N or "default"), label (the key: 0 for 10,
// "def"), current, trees (trees of its own; the
// default ones when there are any), shared (no trees of its own, showing the
// default ones) }.
function strip(state, layout, current) {
  var entry = state && state.layouts ? state.layouts[layout] : null
  var own = entry && Array.isArray(entry.own) ? entry.own.map(Number) : []
  var shows = entry && entry.workspaces ? entry.workspaces : {}
  var out = []
  var last = count(state)
  for (var n = 1; n <= last; n++) {
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

// The digit keys for the help row: "1–9 0" for ten workspaces, "1–9" for
// nine, "1" for one.
function jumpKeys(last) {
  var n = last || COUNT
  if (n === COUNT) return "1–9 0"
  return n === 1 ? "1" : "1–" + n
}
