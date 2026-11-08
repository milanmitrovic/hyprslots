.pragma library

// The bar widget's model (docs/design.md §9): what BarWidget.qml shows for
// the engine's state and the workspace its bar's monitor shows, and what its
// right-click menu offers. Pure, so node can test it
// (editor/tests/bar-status.test.mjs).

var GLYPH = "󰕰" // the grid milan.layout shows for slots

// The workspace entry (workspace 1 to 10, screen) of a Hyprland workspace id
// on the active desk, or null.
function entryOf(state, id) {
  var ws = state && state.workspaces ? state.workspaces[String(id)] : null
  return ws && ws.workspace !== undefined && ws.workspace !== null ? ws : null
}

function workspaceOf(state, id) {
  var ws = entryOf(state, id)
  return ws ? ws.workspace : null
}

// Whether the active layout has a tree for that workspace on that screen.
function hasTree(state, entry) {
  var layout = state && state.layouts && state.layout ? state.layouts[state.layout] : null
  var trees = layout && layout.workspaces ? layout.workspaces[String(entry.workspace)] : null
  return !!(trees && trees[String(entry.screen)])
}

var HINT = "Click: editor · Right-click: menu"

// Where the bar's screen is, in words: "desk laptop, workspace 3".
function where(desk, entry, tree, workspaceId) {
  if (!desk) return "no desk for these monitors"
  if (entry) return "desk " + desk + ", workspace " + entry.workspace + (tree ? "" : " has no tree on this screen")
  if (workspaceId === undefined || workspaceId === null || workspaceId < 0) return "desk " + desk + ", no workspace"
  return "desk " + desk + ", workspace " + workspaceId + " has no tree"
}

// "Layout: solo (also used by: office)", or "" with no layout.
function layoutLine(state) {
  if (!state || !state.layout) return ""
  var l = state.layouts ? state.layouts[state.layout] : null
  var others = (l && Array.isArray(l.used_by) ? l.used_by : []).filter(function(d) { return d !== state.desk })
  return "Layout: " + state.layout + (others.length ? " (also used by: " + others.join(", ") + ")" : "")
}

// input: { engine (whether the service is there), error (its last state
// read's error, "" when fine), state (the last state that read fine, or
// null), workspaceId (the bar's monitor's active Hyprland workspace id, -1 if
// none) }. Returns { label, status: "normal" | "dirty" | "error", tooltip,
// error, workspace (its number 1 to 10, or null), desk ("" when none),
// dirty }. The label is "<desk> · ws <n>", a dash for a workspace with no
// tree on the bar's screen.
function view(input) {
  var state = input.state
  var entry = entryOf(state, input.workspaceId)
  var workspace = entry ? entry.workspace : null
  var tree = entry ? hasTree(state, entry) : false
  var desk = state && state.desk ? String(state.desk) : ""
  var dirty = !!(state && state.dirty === true)
  var label = GLYPH + " " + (desk || "none") + " · ws " + (tree ? workspace : "–") + (dirty ? " •" : "")
  var line = layoutLine(state)
  var here = where(desk, entry, tree, input.workspaceId) + (dirty ? " · unsaved edits" : "") + (line ? "\n" + line : "")
  var out = { label: label, status: dirty ? "dirty" : "normal", tooltip: "", error: "", workspace: workspace,
    desk: desk, dirty: dirty }

  if (!input.engine) {
    out.error = "the milan.hyprslots service is not running"
  } else if (input.error) {
    // The state is older than the failure, or there is none.
    out.error = String(input.error)
  } else if (state && state.refused) {
    out.error = "hyprslots is off: " + state.refused
    out.label = GLYPH + " off"
  } else if (state && state.config_error) {
    out.error = "config error: " + state.config_error
  }
  if (out.error) {
    out.status = "error"
    if (!state) out.label = GLYPH + " hyprslots"
    out.tooltip = "Hyprslots: " + out.error + (state && input.engine && !input.error && !state.refused ? "\n" + here : "") + "\n" + HINT
  } else {
    out.tooltip = "Hyprslots: " + here + "\n" + HINT
  }
  return out
}

// The right-click menu for the same input as view(): [{ id, label, enabled }]
// with ids "arrange", "record", "save", "reload". Re-apply and record need
// the bar's screen to show a workspace of a running engine (a config error leaves
// the last good config running); save needs unsaved edits; reload needs
// only the service (it is how a fixed config error is picked up).
function menu(input) {
  var v = view(input)
  var state = input.state
  var live = !!(input.engine && !input.error && state && !state.refused)
  var onWorkspace = live && v.workspace !== null
  return [
    { id: "arrange", label: "Re-apply layout" + (v.workspace !== null ? " (workspace " + v.workspace + ")" : ""),
      enabled: onWorkspace },
    { id: "record", label: "Record workspace" + (v.workspace !== null ? " " + v.workspace : "") + "…",
      enabled: onWorkspace },
    { id: "save", label: "Save", enabled: live && v.dirty },
    { id: "reload", label: "Reload config", enabled: !!input.engine },
  ]
}

// The api calls a menu entry makes, in order ([] for record, which opens
// the panel's Layout tab on its record flow instead). Re-apply is the
// workspace's Super+N (`workspace`: every screen of the desk shows it
// again, scroll branches back in slot order) and then `arrange` (the scroll
// pass now, the focused scroll workspace's columns widened).
function calls(id, workspace) {
  if (id === "arrange") return [{ name: "workspace", args: { workspace: workspace } }, { name: "arrange", args: {} }]
  if (id === "save") return [{ name: "save", args: {} }]
  if (id === "reload") return [{ name: "reload", args: {} }]
  return []
}

// What a menu entry's last reply says, for a notification.
function outcome(id, workspace, reply) {
  if (!reply || !reply.ok) return reply && reply.error ? String(reply.error) : "the call failed"
  if (id === "arrange") return "Workspace " + workspace + " laid out again."
  if (id === "save") return "Saved " + reply.path + "."
  if (id === "reload") {
    return reply.desk ? "Reloaded the config; desk " + reply.desk + " runs layout " + reply.layout + "."
      : "Reloaded the config; these monitors have no desk."
  }
  return "Done."
}
