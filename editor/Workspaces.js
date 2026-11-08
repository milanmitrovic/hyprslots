.pragma library

// Workspace keys, the same in the Layout and Assignment views (docs/design.md
// §9): [ and ] step through workspaces 1 to 10 (Omarchy's ten workspaces per
// screen), the digits jump to one as Super+N does (0 is workspace 10). The
// arrows stay the view's own. Pure, so node can test it
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

// Workspaces 1 to 10 for a header strip: { workspace, label (the key: 0 for
// 10), current, trees (the arrangement has a tree for the workspace) }.
function strip(state, arrangement, current) {
  var entry = state && state.arrangements ? state.arrangements[arrangement] : null
  var workspaces = entry && entry.workspaces ? entry.workspaces : {}
  var out = []
  for (var n = 1; n <= COUNT; n++) {
    var branches = workspaces[String(n)]
    out.push({ workspace: n, label: String(n % COUNT), current: n === current,
      trees: !!branches && Object.keys(branches).length > 0 })
  }
  return out
}
