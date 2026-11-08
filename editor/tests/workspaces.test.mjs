// Workspace keys (Workspaces.js), the same in the Layout and Assignment views:
// [ and ] step through workspaces 1 to 10, the digits jump (0 is workspace
// 10), and a strip shows which workspaces have trees.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const W = load("Workspaces.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("] and [ step to the next and previous workspace, round from 10 to 1 and back", () => {
  assert.equal(W.step(3, 1), 4);
  assert.equal(W.step(3, -1), 2);
  assert.equal(W.step(10, 1), 1);
  assert.equal(W.step(1, -1), 10);
});

test("a workspace out of range steps from the nearest end", () => {
  assert.equal(W.step(0, 1), 1);
  assert.equal(W.step(0, -1), 10);
});

test("the digits jump to workspaces 1 to 9, and 0 to workspace 10, as Super+N does", () => {
  assert.equal(W.ofDigit("1"), 1);
  assert.equal(W.ofDigit("9"), 9);
  assert.equal(W.ofDigit("0"), 10);
  assert.equal(W.ofDigit("a"), null);
  assert.equal(W.ofDigit(""), null);
  assert.equal(W.ofDigit("12"), null);
});

test("the strip starts with All workspaces (the shared trees), then marks the workspaces with their own", () => {
  const state = { layouts: { solo: { screens: 1, own: [3, 10], default: { 1: { tree: "main" } },
    workspaces: { 3: { 1: { tree: "a" } }, 5: { 1: { tree: "main" } }, 10: { 1: { tree: "b" } } } } } };
  const strip = plain(W.strip(state, "solo", 3));
  assert.equal(strip.length, 11, "All workspaces, then workspaces 1 to 10");
  assert.deepEqual(strip[0], { workspace: "default", label: "All workspaces", current: false, own: false, shared: false });
  assert.deepEqual(strip[3], { workspace: 3, label: "3", current: true, own: true, shared: false });
  assert.deepEqual(strip[1], { workspace: 1, label: "1", current: false, own: false, shared: true },
    "a workspace with no trees of its own uses the shared ones");
  assert.deepEqual(strip[5], { workspace: 5, label: "5", current: false, own: false, shared: true });
  assert.deepEqual(strip[10], { workspace: 10, label: "0", current: false, own: true, shared: false });
  assert.equal(plain(W.strip(state, "solo", "default"))[0].current, true);
  assert.equal(plain(W.strip(null, "solo", 1)).filter((w) => w.own).length, 0);
});

test("a strip key reads as its label, a dot marking a workspace with its own trees", () => {
  assert.equal(W.stripText({ label: "3", own: true }), "3•");
  assert.equal(W.stripText({ label: "4", own: false }), "4");
  assert.equal(W.stripText({ label: "All workspaces", own: false }), "All workspaces");
});

test("stepping from the default trees goes to workspace 1 or 10", () => {
  assert.equal(W.step("default", 1), 1);
  assert.equal(W.step("default", -1), 10);
});

test("with workspace_count 9: ] steps round from 9 to 1, 0 is no key, the strip ends at 9", () => {
  assert.equal(W.count({ workspace_count: 9 }), 9);
  assert.equal(W.count({}), 10, "ten when the engine says nothing");
  assert.equal(W.count(null), 10);
  assert.equal(W.step(9, 1, 9), 1);
  assert.equal(W.step(1, -1, 9), 9);
  assert.equal(W.step("default", -1, 9), 9);
  assert.equal(W.ofDigit("0", 9), null);
  assert.equal(W.ofDigit("9", 9), 9);
  assert.equal(W.ofDigit("5", 4), null, "a digit past the count");
  const state = { workspace_count: 9, layouts: { solo: { screens: 1, own: [3], workspaces: {} } } };
  const strip = plain(W.strip(state, "solo", 3));
  assert.deepEqual(strip.map((w) => w.label), ["All workspaces", "1", "2", "3", "4", "5", "6", "7", "8", "9"]);
});

test("the help's jump keys follow the count", () => {
  assert.equal(W.jumpKeys(10), "1–9 0");
  assert.equal(W.jumpKeys(9), "1–9");
  assert.equal(W.jumpKeys(4), "1–4");
  assert.equal(W.jumpKeys(1), "1");
});
