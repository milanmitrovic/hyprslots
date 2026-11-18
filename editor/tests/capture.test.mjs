// Capture in the editor (Capture.js): the workspace a capture takes, the
// question it asks first, what the preview shows and asks, and what the
// applied capture says.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const C = load("Capture.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

// Workspace 3 shows on screen 1 as Hyprland workspace 3, on screen 2 as 13.
const state = {
  workspaces: { 3: { workspace: 3, screen: 1 }, 13: { workspace: 3, screen: 2 } },
  used_workspaces: [2, 3],
};

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
      { address: "0x1", class: "com.mitchellh.ghostty", title: "notes | ~", slot: "ghostty", spec: "com.mitchellh.ghostty", new: true },
      { address: "0x2", class: "google-chrome", title: "Inbox", slot: "chrome", spec: "google-chrome", new: true },
    ],
    plan: "1a2b3c4d",
    applied: false,
    seq: 7,
    ...extra,
  };
}

test("a capture takes the workspace shown, or on All workspaces the focused one", () => {
  assert.equal(C.workspaceFor(state, 5, 3), 5, "a workspace's page: that one");
  assert.equal(C.workspaceFor(state, "default", 3), 3, "All workspaces: the focused one");
  assert.equal(C.workspaceFor(state, "default", 13), 3, "on any screen");
  assert.equal(C.workspaceFor(state, "default", 77), 2, "a focus no workspace of ours: the first one in use");
  assert.equal(C.workspaceFor({}, "default", -1), 1, "else workspace 1");
});

test("it asks first whom the capture is for, as the other edits do", () => {
  const q = plain(C.question(3));
  assert.equal(q.label, "Capture workspace 3: apply to (a)ll workspaces or (o)nly workspace 3?");
  assert.deepEqual(q.options, [
    { key: "a", label: "all workspaces", value: "all" },
    { key: "o", label: "only workspace 3", value: "workspace" },
  ]);
});

test("the preview shows on All workspaces for all of them from there, else on the captured workspace", () => {
  assert.equal(C.previewWorkspace("default", "all", 3), "default");
  assert.equal(C.previewWorkspace("default", "workspace", 3), 3);
  assert.equal(C.previewWorkspace(5, "all", 5), 5);
  assert.equal(C.previewWorkspace(5, "workspace", 5), 5);
});

test("the preview's trees by screen, a screen left with none as null", () => {
  assert.deepEqual(plain(C.previewTrees(reply())), { 1: "h[ghostty:2, chrome]", 2: null });
});

test("the preview's titles: each captured window's in its slot, new slots included", () => {
  assert.deepEqual(plain(C.titles(reply())), { ghostty: "notes | ~", chrome: "Inbox" });
});

test("the preview asks y/n, naming the slots it makes with their keys and how many windows go into slots", () => {
  assert.equal(C.previewText(reply()),
    "Capture workspace 3 (all workspaces): makes slots ghostty (g) and chrome (c), puts 2 windows into their slots. Apply it?");
  assert.equal(C.previewText(reply({ scope: "workspace" })),
    "Capture workspace 3 (this workspace only): makes slots ghostty (g) and chrome (c), puts 2 windows into their slots. Apply it?");
  const one = reply({ new_slots: [{ slot: "foot", key: "f" }], windows: [{ address: "0x1", class: "foot", slot: "foot", new: true }] });
  assert.equal(C.previewText(one), "Capture workspace 3 (all workspaces): makes slot foot (f), puts 1 window into its slot. Apply it?");
  const three = reply({ new_slots: [{ slot: "a", key: "a" }, { slot: "b", key: "b" }, { slot: "c", key: "" }] });
  assert.match(C.previewText(three), /makes slots a \(a\), b \(b\) and c,/, "a slot with no key: its name alone");
  const none = reply({ new_slots: [] });
  assert.equal(C.previewText(none),
    "Capture workspace 3 (all workspaces): uses the slots there are, puts 2 windows into their slots. Apply it?");
});

test("y applies the plan previewed: its workspace, scope and plan token", () => {
  assert.deepEqual(plain(C.applyArgs(reply())), { workspace: 3, scope: "all", apply: true, plan: "1a2b3c4d" });
  assert.deepEqual(plain(C.applyArgs(reply({ scope: "workspace", plan: "00000000" }))),
    { workspace: 3, scope: "workspace", apply: true, plan: "00000000" });
  assert.deepEqual(plain(C.applyArgs(reply({ plan: undefined }))), { workspace: 3, scope: "all", apply: true },
    "an engine of before sends no plan: none is sent back");
});

test("once applied it says what was made, unsaved", () => {
  assert.equal(C.appliedText(reply({ applied: true })),
    "Captured workspace 3 (all workspaces): made slots ghostty (g) and chrome (c); 2 windows are in their slots. Ctrl+S saves.");
  assert.equal(C.appliedText(reply({ applied: true, scope: "workspace", new_slots: [] })),
    "Captured workspace 3 (this workspace only): 2 windows are in their slots. Ctrl+S saves.");
});

test("its words are plain", () => {
  const text = [C.question(3).label, C.previewText(reply()), C.appliedText(reply())].join(" ").toLowerCase();
  for (const word of ["spec", "tree", "overflow", "default"]) assert.ok(!text.includes(word), word);
});
