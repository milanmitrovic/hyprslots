// The Layout view's capture and record flows (LayoutController.js): where
// the view goes while a capture is previewed, how n/Esc or a refused apply
// puts it back, what an applied capture leaves, and record's checks, call
// and drafts.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const LC = load("LayoutController.js");
const L = load("Layout.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Workspace 3 shows on screen 1 as Hyprland workspace 3, on screen 2 as 13;
// workspace 2 on screen 1 as 2.
const state = {
  layout: "dual",
  workspaces: { 2: { workspace: 2, screen: 1 }, 3: { workspace: 3, screen: 1 }, 13: { workspace: 3, screen: 2 } },
  used_workspaces: [2, 3],
};

const draft = (text) => ({ node: L.parse(text).node, base: text });

// The view on workspace 5, screen 2, leaf "b" selected, scoped to it.
function view(extra) {
  return { workspace: 5, scope: "workspace", screen: "2", selectedKey: "b",
    drafts: { 1: draft("h[a, b]"), 2: draft("v[b, c]") }, ...extra };
}

// The api's capture reply (lua/hyprslots/api.lua handlers.capture), previewed.
function reply(extra) {
  return {
    ok: true,
    workspace: 3,
    scope: "all",
    layout: "dual",
    trees: { 1: { tree: "h[ghostty:2, chrome]", ratio: "2:1" }, 2: false },
    new_slots: [{ slot: "ghostty", key: "g" }, { slot: "chrome", key: "c" }],
    windows: [
      { address: "0x1", class: "com.mitchellh.ghostty", title: "notes | ~", slot: "ghostty", new: true },
      { address: "0x2", class: "google-chrome", title: "Inbox", slot: "chrome", new: true },
    ],
    plan: "1a2b3c4d",
    applied: false,
    ...extra,
  };
}

// --- capture: start ---------------------------------------------------------

test("c refuses while there are unapplied edits: a capture replaces the arrangement", () => {
  const start = LC.captureStart(view(), null, state, 3, ["1"]);
  assert.equal(start.error, "Apply (w) or revert (d) your edits first: a capture replaces the arrangement.");
  assert.equal(start.workspace, undefined);
});

test("c asks whom for, on the workspace shown, the focused one from All workspaces, or the one asked", () => {
  const own = LC.captureStart(view(), null, state, 3, []);
  assert.equal(own.workspace, 5);
  assert.equal(own.question.label, "Capture workspace 5: apply to (a)ll workspaces or (o)nly workspace 5?");
  assert.equal(LC.captureStart(view({ workspace: "default" }), null, state, 13, []).workspace, 3, "All workspaces: the focused");
  assert.equal(LC.captureStart(view({ workspace: "default" }), undefined, state, 3, undefined).workspace, 3);
  assert.equal(LC.captureStart(view(), 2, state, 3, []).workspace, 2, "the bar's capture: the workspace asked");
});

// --- capture: preview -------------------------------------------------------

test("the preview of another workspace moves the view there, fresh and unscoped, and remembers where it was", () => {
  const v = view();
  const step = LC.capturePreview(v, reply({ scope: "workspace" }));
  assert.equal(step.moved, true);
  assert.deepEqual(plain(step.view), { workspace: 3, scope: "", screen: "", selectedKey: "", drafts: {} });
  assert.deepEqual(plain(step.preview.back), { workspace: 5, scope: "workspace", screen: "2", selectedKey: "b" });
  assert.equal(v.workspace, 5, "the view passed in is left as it was");
  assert.equal(v.selectedKey, "b");
});

test("the preview for all workspaces from All workspaces stays there, its drafts kept, the selection cleared", () => {
  const v = view({ workspace: "default", scope: "" });
  const step = LC.capturePreview(v, reply());
  assert.equal(step.moved, false);
  assert.equal(step.view.workspace, "default");
  assert.equal(step.view.screen, "2");
  assert.equal(step.view.selectedKey, "");
  assert.equal(step.view.drafts, v.drafts, "the same drafts");
});

test("the preview holds the captured trees parsed, a screen left with none as null, and the windows' titles", () => {
  const { preview } = LC.capturePreview(view({ workspace: 3 }), reply());
  assert.equal(L.format(preview.trees[1]), "h[ghostty:2, chrome]");
  assert.equal(preview.trees[2], null);
  assert.deepEqual(plain(preview.titles), { ghostty: "notes | ~", chrome: "Inbox" });
  assert.equal(preview.reply.plan, "1a2b3c4d");
});

test("a captured tree that does not parse previews as no tree, not a crash", () => {
  const { preview } = LC.capturePreview(view({ workspace: 3 }), reply({ trees: { 1: { tree: "h[a," } } }));
  assert.equal(preview.trees[1], null);
});

// --- capture: cancel / restore ----------------------------------------------

test("n or Esc after a preview that moved puts the view back: its workspace, screen, scope and selection", () => {
  const before = view();
  const shown = LC.capturePreview(before, reply({ scope: "workspace" }));
  // the sync on workspace 3 chose a screen; the preview cleared the selection
  const now = { ...shown.view, screen: "1", drafts: { 1: draft("h[x, y]") } };
  const end = LC.captureEnd(now, shown.preview);
  assert.equal(end.moved, true);
  assert.deepEqual(plain(end.view), { workspace: 5, scope: "workspace", screen: "2", selectedKey: "b", drafts: {} },
    "a fresh view on workspace 5, re-read by the sync");
});

test("n after a preview in place keeps the drafts and screen, the scope and selection back", () => {
  const before = view({ workspace: "default", scope: "all" });
  const shown = LC.capturePreview(before, reply());
  const end = LC.captureEnd(shown.view, shown.preview);
  assert.equal(end.moved, false);
  assert.equal(end.view.workspace, "default");
  assert.equal(end.view.scope, "all");
  assert.equal(end.view.selectedKey, "b");
  assert.equal(end.view.screen, "2");
  assert.equal(end.view.drafts, before.drafts);
});

test("ending with no preview leaves the view as it is", () => {
  const v = view();
  const end = LC.captureEnd(v, null);
  assert.equal(end.moved, false);
  assert.deepEqual(plain(end.view), plain(v));
});

test("a refused apply ends the capture as n does: the view back where it was", () => {
  const shown = LC.capturePreview(view(), reply({ scope: "workspace" }));
  const end = LC.captureEnd(shown.view, shown.preview);
  assert.equal(end.view.workspace, 5);
  assert.equal(end.view.scope, "workspace");
});

// --- capture: apply ---------------------------------------------------------

test("y after the preview moved: the view stays on the captured workspace, unscoped, its drafts the trees made", () => {
  const shown = LC.capturePreview(view(), reply({ scope: "workspace" }));
  const synced = { ...shown.view, screen: "1", drafts: { 1: draft("h[old]"), 2: draft("v[keep]") } };
  const done = reply({ scope: "workspace", applied: true, trees: { 1: { tree: "h[ghostty:2, chrome]" }, 2: false } });
  const step = LC.captureApplied(synced, done);
  assert.equal(step.view.workspace, 3, "not back on workspace 5");
  assert.equal(step.view.scope, "");
  assert.equal(step.view.screen, "1");
  assert.equal(L.format(step.view.drafts[1].node), "h[ghostty:2, chrome]");
  assert.equal(step.view.drafts[1].base, "h[ghostty:2, chrome]");
  assert.deepEqual(plain(step.view.drafts[2]), { node: null, base: null }, "a screen the capture left empty");
  assert.equal(step.text,
    "Captured workspace 3 (this workspace only): made slots ghostty (g) and chrome (c); 2 windows are in their slots. Ctrl+S saves.");
  assert.equal(L.format(synced.drafts[1].node), "h[old]", "the view passed in is left as it was");
});

test("y keeps the drafts of screens the capture did not touch", () => {
  const v = view({ workspace: 3, scope: "all" });
  const step = LC.captureApplied(v, reply({ applied: true, trees: { 1: { tree: "a" } } }));
  assert.equal(L.format(step.view.drafts[1].node), "a");
  assert.equal(L.format(step.view.drafts[2].node), "v[b, c]");
});

test("y with a reply of no trees changes no draft", () => {
  const v = view();
  const step = LC.captureApplied(v, reply({ applied: true, trees: undefined }));
  assert.deepEqual(Object.keys(step.view.drafts), ["1", "2"]);
});

// --- record -----------------------------------------------------------------

test("the bar's Record moves the view to the focused workspace and screen, fresh", () => {
  const step = LC.recordFocused(view(), state, 13);
  assert.equal(step.moved, true);
  assert.deepEqual(plain(step.view), { workspace: 3, scope: "", screen: "2", selectedKey: "", drafts: {} });
});

test("the bar's Record on the workspace shown keeps its scope, drafts and selection, on the focused screen", () => {
  const v = view({ workspace: 3 });
  const step = LC.recordFocused(v, state, 3);
  assert.equal(step.moved, false);
  assert.equal(step.view.screen, "1");
  assert.equal(step.view.scope, "workspace");
  assert.equal(step.view.selectedKey, "b");
  assert.equal(step.view.drafts, v.drafts);
});

test("R records a workspace's screen; refuses on All workspaces and on a screen the workspace is not on", () => {
  assert.equal(LC.recordStart(view({ workspace: "default" }), state).error,
    "R records a workspace's windows: pick one with [ ] or its digit.");
  assert.equal(LC.recordStart(view({ workspace: 2, screen: "2" }), state).error, "Workspace 2 is not on screen 2.");
  assert.equal(LC.recordStart(view({ workspace: 3, screen: "1" }), null).error, "Workspace 3 is not on screen 1.", "no state");
  assert.deepEqual(plain(LC.recordStart(view({ workspace: 3, screen: "2" }), state)),
    { workspaceId: 13, text: "Recording workspace 13…" });
  assert.equal(LC.workspaceIdOf(state, 3, 1), 3, "a screen key as a number too");
});

test("R asks y/n naming the tree, its ratio and what applying drops", () => {
  const rec = { tree: "h[a, b]", ratio: "1:1", workspace_id: 13 };
  assert.equal(LC.recordQuestion(rec), "Recorded h[a, b] (1:1) from workspace 13. Apply it?");
  assert.equal(LC.recordQuestion({ ...rec, missing: ["c"] }),
    "Recorded h[a, b] (1:1) from workspace 13; missing c: applying drops it from the tree. Apply it?");
  assert.equal(LC.recordQuestion({ ...rec, missing: ["c", "d"] }),
    "Recorded h[a, b] (1:1) from workspace 13; missing c, d: applying drops them from the tree. Apply it?");
});

test("R's y sets the recorded tree on the shared trees once asked for all, else on the workspace's", () => {
  const rec = { layout: "dual", workspace: 3, screen: 2, tree: "h[a, b]" };
  assert.deepEqual(plain(LC.recordSetArgs(rec, "all")), { layout: "dual", workspace: "default", trees: { 2: "h[a, b]" } });
  assert.deepEqual(plain(LC.recordSetArgs(rec, "workspace")), { layout: "dual", workspace: 3, trees: { 2: "h[a, b]" } });
  assert.deepEqual(plain(LC.recordSetArgs(rec, "")), { layout: "dual", workspace: 3, trees: { 2: "h[a, b]" } });
});

test("R applied: the recorded screen's draft is the tree set, the others kept; a reply without it is an error", () => {
  const v = view({ workspace: 3 });
  const rec = { screen: 2 };
  const step = LC.recordApplied(v, rec, { ok: true, trees: { 2: { tree: "h[a:2, b]" } } });
  assert.equal(L.format(step.view.drafts[2].node), "h[a:2, b]");
  assert.equal(step.view.drafts[2].base, "h[a:2, b]");
  assert.equal(step.view.drafts[1], v.drafts[1]);
  assert.equal(step.text, "Applied the recorded tree h[a:2, b]. Ctrl+S saves.");
  assert.equal(L.format(v.drafts[2].node), "v[b, c]", "the view passed in is left as it was");
  assert.equal(LC.recordApplied(v, rec, { ok: true, trees: {} }).error, "The engine applied no tree to screen 2.");
  assert.equal(LC.recordApplied(v, rec, { ok: true }).error, "The engine applied no tree to screen 2.");
});
