.pragma library

// Capture in the editor (docs/design.md §9): the windows of a workspace,
// arranged by hand, made into slots and the layout's trees in one edit (the
// api's `capture`). The Layout tab's `c` (and the Assignment tab's, the
// toolbar's capture, the bar's "Capture this workspace…", the first run's
// "Capture my windows") asks whom it is for, as every edit of a workspace
// on the shared trees does, previews what it would make (the picture draws
// the captured trees, slots not made yet included) and applies it on y.
// Pure, so node can test it (editor/tests/capture.test.mjs).

// The workspace a capture takes: the one shown, or, on All workspaces,
// the focused one (`focusedId`, a Hyprland workspace id; when that is none
// of ours, the first workspace in use, else 1).
function workspaceFor(state, workspace, focusedId) {
  if (workspace !== "default" && workspace !== null && workspace !== undefined) return workspace
  var ws = state && state.workspaces ? state.workspaces[String(focusedId)] : null
  if (ws && ws.workspace) return ws.workspace
  var used = state && Array.isArray(state.used_workspaces) ? state.used_workspaces : []
  return used.length ? used[0] : 1
}

// The question it asks first, for Prompts.choice(label, options, { inline:
// true }): the api's scope, "all" (the shared trees) or "workspace" (its own).
function question(n) {
  return {
    label: "Capture workspace " + n + ": apply to (a)ll workspaces or (o)nly workspace " + n + "?",
    options: [{ key: "a", label: "all workspaces", value: "all" }, { key: "o", label: "only workspace " + n, value: "workspace" }],
  }
}

// Where the Layout view shows the preview: All workspaces when the capture
// is for all of them and the view is there, else the captured workspace.
function previewWorkspace(viewWorkspace, scope, n) {
  return scope === "all" && viewWorkspace === "default" ? "default" : n
}

// The captured trees by screen key ("1"), as text; null for a screen the
// capture leaves with none.
function previewTrees(reply) {
  var out = {}
  var trees = reply && reply.trees ? reply.trees : {}
  for (var k in trees) out[String(k)] = trees[k] && trees[k].tree ? String(trees[k].tree) : null
  return out
}

// What the preview's tiles show under their slot names: each captured
// window's title in its slot.
function titles(reply) {
  var out = {}
  var windows = reply && Array.isArray(reply.windows) ? reply.windows : []
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (w.slot && out[w.slot] === undefined) out[w.slot] = w.title || ""
  }
  return out
}

function listed(words) {
  if (words.length <= 1) return words.join("")
  return words.slice(0, -1).join(", ") + " and " + words[words.length - 1]
}

function slotList(reply) {
  var slots = reply && Array.isArray(reply.new_slots) ? reply.new_slots : []
  return listed(slots.map(function(s) { return s.key ? s.slot + " (" + s.key + ")" : s.slot }))
}

function newCount(reply) {
  return reply && Array.isArray(reply.new_slots) ? reply.new_slots.length : 0
}

function windowCount(reply) {
  return reply && Array.isArray(reply.windows) ? reply.windows.length : 0
}

function whom(reply) {
  return reply.scope === "workspace" ? "workspace " + reply.workspace + " only" : "all workspaces"
}

// The preview's y/n question (Prompts.confirm adds "(y/n)").
function previewText(reply) {
  var n = newCount(reply)
  var made = n === 0 ? "uses the slots there are" : "makes slot" + (n === 1 ? " " : "s ") + slotList(reply)
  var w = windowCount(reply)
  return "Capture workspace " + reply.workspace + " for " + whom(reply) + ": " + made + ", puts " + w
    + (w === 1 ? " window into its slot" : " windows into their slots") + ". Apply it?"
}

// What an applied capture says: an edit like any other, unsaved.
function appliedText(reply) {
  var n = newCount(reply)
  var w = windowCount(reply)
  return "Captured workspace " + reply.workspace + " for " + whom(reply) + ": "
    + (n === 0 ? "" : "made slot" + (n === 1 ? " " : "s ") + slotList(reply) + "; ")
    + w + (w === 1 ? " window is in its slot" : " windows are in their slots") + ". Ctrl+S saves."
}
