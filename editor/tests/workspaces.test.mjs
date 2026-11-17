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

test("the Layout header is one strip: All workspaces, a dot, the workspaces; the current one in brackets as text", () => {
  const state = { workspace_count: 9, layouts: { solo: { screens: 1, own: [3], default: {}, workspaces: {} } } };
  assert.equal(W.stripLine(W.strip(state, "solo", "default")), "[All workspaces] · 1 2 3• 4 5 6 7 8 9");
  assert.equal(W.stripLine(W.strip(state, "solo", 3)), "All workspaces · 1 2 [3•] 4 5 6 7 8 9");
  assert.equal(W.stripLine(W.strip(state, "solo", 9)), "All workspaces · 1 2 3• 4 5 6 7 8 [9]");
});

test("the Assignment tab's switcher: the managed workspaces by their keys, no All workspaces, no dots", () => {
  const state = { workspace_count: 9, layouts: { solo: { own: [3] } } };
  const numbers = plain(W.numbers(state, 3));
  assert.deepEqual(numbers.map((w) => w.label), ["1", "2", "3", "4", "5", "6", "7", "8", "9"]);
  assert.deepEqual(numbers[2], { workspace: 3, label: "3", current: true, own: false, shared: false });
  assert.equal(numbers.filter((w) => w.current).length, 1);
  assert.equal(W.stripLine(W.numbers(state, 3)), "1 2 [3] 4 5 6 7 8 9");
  assert.deepEqual(plain(W.numbers(null, 10)).map((w) => w.label).slice(-1), ["0"], "workspace 10's key is 0");
});

// Workspace 3 shows on screen 1 as Hyprland workspace 3, on screen 2 as 13;
// the layout "dual" is active.
const live = {
  workspaces: { 3: { workspace: 3, screen: 1, monitor: "eDP-1" }, 13: { workspace: 3, screen: 2, monitor: "DP-1" }, 20: { screen: 1 } },
  used_workspaces: [2, 3],
  layout: "dual",
  layouts: { dual: { screens: 2, own: [3] }, solo: { screens: 1 } },
};

test("entry: a Hyprland workspace id's workspace and screen on the active desk", () => {
  assert.deepEqual(plain(W.entry(live, 3)), { workspace: 3, screen: 1, monitor: "eDP-1" });
  assert.deepEqual(plain(W.entry(live, "13")), { workspace: 3, screen: 2, monitor: "DP-1" }, "an id as text reads the same");
  assert.equal(W.entry(live, 77), null, "an id that is none of ours");
  assert.equal(W.entry(live, 20), null, "an entry with no workspace number");
  assert.equal(W.entry(live, -1), null, "no workspace focused");
  assert.equal(W.entry(live, null), null);
  assert.equal(W.entry(live, undefined), null);
  assert.equal(W.entry({ workspaces: { null: { workspace: 4 } } }, null), null, "a null id is never the key \"null\"");
  assert.equal(W.entry({}, 3), null, "a state with no workspaces");
  assert.equal(W.entry(null, 3), null, "no state");
});

test("focusedOrFirst: the focused workspace and its screen, else the first in use on screen 1, else 1", () => {
  assert.deepEqual(plain(W.focusedOrFirst(live, 3)), { workspace: 3, screen: 1 });
  assert.deepEqual(plain(W.focusedOrFirst(live, 13)), { workspace: 3, screen: 2 }, "on any screen");
  assert.deepEqual(plain(W.focusedOrFirst({ workspaces: { 5: { workspace: 5 } } }, 5)), { workspace: 5, screen: 1 }, "an entry with no screen: screen 1");
  assert.deepEqual(plain(W.focusedOrFirst(live, 77)), { workspace: 2, screen: 1 }, "a focus that is none of ours: the first in use");
  assert.deepEqual(plain(W.focusedOrFirst(live, 20)), { workspace: 2, screen: 1 }, "an entry with no workspace number: the first in use");
  assert.deepEqual(plain(W.focusedOrFirst({ used_workspaces: [] }, 3)), { workspace: 1, screen: 1 }, "none in use: workspace 1");
  assert.deepEqual(plain(W.focusedOrFirst(null, -1)), { workspace: 1, screen: 1 }, "no state: workspace 1");
});

test("activeLayout: the active layout's entry, or null", () => {
  assert.deepEqual(plain(W.activeLayout(live)), { screens: 2, own: [3] });
  assert.equal(W.activeLayout({ ...live, layout: "gone" }), null, "an active layout the state lists not");
  assert.equal(W.activeLayout({ ...live, layout: "" }), null, "no active layout");
  assert.equal(W.activeLayout({ layout: "dual" }), null, "no layouts");
  assert.equal(W.activeLayout(null), null, "no state");
});
