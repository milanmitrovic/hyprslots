.pragma library
.import "Layout.js" as Layout
.import "Capture.js" as Capture

// The Layout view's flows that move the view itself (docs/design.md §9),
// as pure transitions so node can test them
// (editor/tests/layout-controller.test.mjs): capture (c: asked whom it is
// for, previewed in the picture, applied on y or put back on n/Esc) and
// record (R: the windows on a screen measured into a tree, applied on y).
// LayoutView.qml runs the engine calls and prompts and sets what these
// return; Capture.js holds what a capture says and sends.
//
// A view is { workspace (a number, or "default" for All workspaces), scope
// ("" | "all" | "workspace"), screen (a screen key, "" for none),
// selectedKey (the selected leaf), drafts (screen key -> { node, base }) }.
// A transition returns { view, moved }: the next view and whether it shows
// another workspace than before (the view then re-reads its panes: sync).

function copy(view) {
  return { workspace: view.workspace, scope: view.scope, screen: view.screen, selectedKey: view.selectedKey,
    drafts: view.drafts || {} }
}

// A draft for a tree in force: its parsed node (null for none, or for a
// tree that does not parse) and the text it came from.
function draftOf(text) {
  var t = text !== null && text !== undefined && text !== false ? String(text) : null
  return { node: t !== null ? Layout.parse(t).node || null : null, base: t }
}

// --- capture ------------------------------------------------------------------

// c (or a capture asked for workspace `n`, null for the view's own:
// Capture.workspaceFor): { error } while there are unapplied edits (a
// capture replaces the arrangement), else { workspace, question } (the
// workspace captured and Capture.question's whom-for).
function captureStart(view, n, state, focusedWorkspace, editedScreens) {
  if (editedScreens && editedScreens.length > 0) {
    return { error: "Apply (w) or revert (d) your edits first: a capture replaces the arrangement." }
  }
  var target = n !== null && n !== undefined ? n : Capture.workspaceFor(state, view.workspace, focusedWorkspace)
  return { workspace: target, question: Capture.question(target) }
}

// The engine's preview `reply`, shown: the view moves to the workspace it
// is for (Capture.previewWorkspace: a fresh view there, unscoped), the
// selection is cleared, and `preview` holds { reply, trees (screen key ->
// the captured tree, parsed, or null), titles (slot -> its window's
// title), back (where the view was, for captureEnd) }.
function capturePreview(view, reply) {
  var back = { workspace: view.workspace, scope: view.scope, screen: view.screen, selectedKey: view.selectedKey }
  var to = Capture.previewWorkspace(view.workspace, reply.scope, reply.workspace)
  var next = copy(view)
  var moved = to !== view.workspace
  if (moved) {
    next.workspace = to
    next.scope = ""
    next.drafts = {}
    next.screen = ""
  }
  next.selectedKey = ""
  var texts = Capture.previewTrees(reply)
  var trees = {}
  for (var k in texts) trees[k] = draftOf(texts[k]).node
  return { view: next, moved: moved, preview: { reply: reply, trees: trees, titles: Capture.titles(reply), back: back } }
}

// n, Esc or a refused apply: the view as it was before `preview` (its
// workspace, screen, scope and selection; a fresh view when the preview
// had moved it). With no preview, the view as it is.
function captureEnd(view, preview) {
  var back = preview ? preview.back : null
  var next = copy(view)
  if (!back) return { view: next, moved: false }
  var moved = back.workspace !== view.workspace
  if (moved) {
    next.workspace = back.workspace
    next.drafts = {}
    next.screen = back.screen
  }
  next.scope = back.scope
  next.selectedKey = back.selectedKey
  return { view: next, moved: moved }
}

// y, applied (the engine's `done`): the view stays where the preview put it,
// unscoped (the capture said whom it is for), each captured screen's draft
// the tree it made (an edit like any other, unsaved), and what to say.
function captureApplied(view, done) {
  var next = copy(view)
  next.scope = ""
  var drafts = Object.assign({}, next.drafts)
  var trees = done && done.trees ? done.trees : {}
  for (var k in trees) drafts[String(k)] = draftOf(trees[k] && trees[k].tree ? trees[k].tree : null)
  next.drafts = drafts
  return { view: next, moved: false, text: Capture.appliedText(done) }
}

// --- record -------------------------------------------------------------------

// The bar widget's Record: the view on the focused workspace and screen
// (Layout.initialTarget; the view opens on All workspaces, which R does
// not record), a fresh one when that is another workspace.
function recordFocused(view, state, focusedWorkspace) {
  var t = Layout.initialTarget(state, focusedWorkspace)
  var next = copy(view)
  var moved = t.workspace !== view.workspace
  if (moved) {
    next.workspace = t.workspace
    next.scope = ""
    next.drafts = {}
    next.selectedKey = ""
  }
  next.screen = String(t.screen)
  return { view: next, moved: moved }
}

// The Hyprland workspace id workspace `n` has on screen `k`, -1 for none.
function workspaceIdOf(state, n, k) {
  var ws = state && state.workspaces ? state.workspaces : {}
  for (var id in ws) if (ws[id].workspace === n && String(ws[id].screen) === String(k)) return parseInt(id, 10)
  return -1
}

// R: { error } when the view has no workspace's screen to record, else
// { workspaceId, text } (the record call's id and what the band says
// meanwhile).
function recordStart(view, state) {
  if (view.workspace === "default") return { error: "R records a workspace's windows: pick one with [ ] or its digit." }
  var id = workspaceIdOf(state, view.workspace, view.screen)
  if (id < 0) return { error: "Workspace " + view.workspace + " is not on screen " + view.screen + "." }
  return { workspaceId: id, text: "Recording workspace " + id + "…" }
}

// The recorded reply's y/n question: the tree, its ratio, and the slots
// applying it would drop.
function recordQuestion(reply) {
  var missing = reply.missing || []
  return "Recorded " + reply.tree + " (" + reply.ratio + ") from workspace " + reply.workspace_id
    + (missing.length ? "; missing " + missing.join(", ") + ": applying drops " + (missing.length === 1 ? "it" : "them")
      + " from the tree" : "") + ". Apply it?"
}

// y: the set_trees call that applies the recorded tree, to the shared
// trees once the view was asked for all workspaces, else the workspace's.
function recordSetArgs(reply, scope) {
  var trees = {}
  trees[String(reply.screen)] = reply.tree
  return { layout: reply.layout, workspace: scope === "all" ? "default" : reply.workspace, trees: trees }
}

// set_trees done (`set`): the recorded screen's draft the tree applied, and
// what to say; { error } when the reply has no tree for that screen.
function recordApplied(view, reply, set) {
  var r = String(reply.screen)
  var applied = set && set.trees ? set.trees[r] : null
  if (!applied || !applied.tree) return { error: "The engine applied no tree to screen " + r + "." }
  var next = copy(view)
  var drafts = Object.assign({}, next.drafts)
  drafts[r] = draftOf(applied.tree)
  next.drafts = drafts
  return { view: next, moved: false, text: "Applied the recorded tree " + applied.tree + ". Ctrl+S saves." }
}
