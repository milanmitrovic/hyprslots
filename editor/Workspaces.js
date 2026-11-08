.pragma library

// Workspace keys, the same in the Layout and Assignment views (docs/design.md
// §9): [ and ] step through the workspaces hyprslots manages (state
// `workspace_count`, config `workspaces`: 1 to 10 by default, Omarchy's ten
// per screen), the digits jump to one as Super+N does (0 is workspace 10,
// no key when it manages fewer). The arrows stay the view's own; `-` is
// "All workspaces", the layout's shared (default) trees, in the Layout view. Pure, so node can test it
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

// The header strip: "All workspaces" first (`-`: the layout's shared
// trees, workspace "default"), then the managed workspaces: { workspace
// (1..N or "default"), label (its key: 0 for 10), current, own (trees of
// its own: an override of the shared ones), shared (none of its own: it
// shows the shared ones) }.
function strip(state, layout, current) {
  var entry = state && state.layouts ? state.layouts[layout] : null
  var own = entry && Array.isArray(entry.own) ? entry.own.map(Number) : []
  var out = [{ workspace: "default", label: "All workspaces", current: current === "default", own: false, shared: false }]
  var last = count(state)
  for (var n = 1; n <= last; n++) {
    var mine = own.indexOf(n) >= 0
    out.push({ workspace: n, label: String(n % COUNT), current: n === current, own: mine, shared: !!entry && !mine })
  }
  return out
}

// A strip entry as it reads: its label, a dot after a workspace with trees
// of its own.
function stripText(entry) {
  return entry.label + (entry.own ? "•" : "")
}

// The digit keys for the help row: "1–9 0" for ten workspaces, "1–9" for
// nine, "1" for one.
function jumpKeys(last) {
  var n = last || COUNT
  if (n === COUNT) return "1–9 0"
  return n === 1 ? "1" : "1–" + n
}
