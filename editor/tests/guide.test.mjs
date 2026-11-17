// The editor's guidance for someone new (Guide.js): the tab the panel
// opens on, what stands in each tab while there is nothing in it yet, and
// the line that says what to do next.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const G = load("Guide.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

const ASSIGNMENT = 0;
const LAYOUT = 1;
const DESK = 2;

// A fresh install: the starter config, zero slots, the desk the engine made.
function fresh(extra) {
  return {
    desk: "built-in",
    layout: "1-screen",
    slots: [],
    specs: {},
    config: { editable: true, read_only: [] },
    layouts: { "1-screen": { screens: 1, default: {}, workspaces: {} } },
    workspaces: {},
    windows: [],
    ...extra,
  };
}

const oneSlot = (extra) => fresh({ slots: [{ name: "main", key: "m" }], ...extra });

test("with zero slots the panel opens on the Layout tab", () => {
  assert.equal(G.openingTab(fresh(), {}), LAYOUT);
});

test("with slots it opens on the Assignment tab", () => {
  assert.equal(G.openingTab(oneSlot(), {}), ASSIGNMENT);
});

test("a tab asked for wins: Record's Layout tab, or one named", () => {
  assert.equal(G.openingTab(oneSlot(), { record: true }), LAYOUT);
  assert.equal(G.openingTab(fresh(), { tab: "Desk" }), DESK);
  assert.equal(G.openingTab(fresh(), { tab: "Assignment" }), ASSIGNMENT);
  assert.equal(G.openingTab(oneSlot(), { tab: "Nope" }), ASSIGNMENT, "an unknown name is no request");
  assert.equal(G.asksForTab({ record: true }), true);
  assert.equal(G.openingTab(oneSlot(), { capture: true }), LAYOUT, "Capture: the Layout tab");
  assert.equal(G.openingTab(null, { capture: true }), LAYOUT);
  assert.equal(G.asksForTab({ capture: true }), true);
  assert.equal(G.asksForTab({ tab: "Desk" }), true);
  assert.equal(G.asksForTab({}), false);
});

test("before the state is read the opening tab is not known yet", () => {
  assert.equal(G.openingTab(null, {}), null);
  assert.equal(G.openingTab(null, { record: true }), LAYOUT, "a request needs no state");
});

test("a state the engine could not run on opens on the Assignment tab, which says why", () => {
  assert.equal(G.openingTab(fresh({ config_error: "config.lua:3: oops" }), {}), ASSIGNMENT);
  assert.equal(G.openingTab(fresh({ refused: "o.workspaces is not loaded" }), {}), ASSIGNMENT);
});

test("the Layout tab explains slots in place of its picture while there are none", () => {
  const w = plain(G.layoutWelcome(fresh()));
  assert.equal(w.title, "Start with your slots");
  assert.deepEqual(w.lines, [
    "Slots are named places on your screens, like left, main and right. Each app you assign goes into its slot.",
    "Quickest: arrange your windows on a workspace the way you like them, then capture. Each window becomes a slot, and the arrangement is remembered.",
    "Or make them one by one: you choose the names, and how many. Arrange them here, then put windows into them in the Assignment tab.",
  ]);
});

test("it offers capturing your windows first, then making the first slot by hand", () => {
  const w = plain(G.layoutWelcome(fresh()));
  assert.deepEqual(w.actions, [
    { key: "c", label: "Capture my windows" },
    { key: "a", label: "Create your first slot" },
  ]);
});

test("the explanation uses plain words", () => {
  const w = G.layoutWelcome(fresh());
  const text = [w.title, ...w.lines, ...w.actions.map((a) => a.label)].join(" ").toLowerCase();
  for (const word of ["spec", "overflow", "tree", "default"]) assert.ok(!text.includes(word), word);
});

test("no explanation once there is a slot, or where none can be made", () => {
  assert.equal(G.layoutWelcome(oneSlot()), null);
  assert.equal(G.layoutWelcome(null), null);
  assert.equal(G.layoutWelcome(fresh({ config_error: "oops" })), null, "the problem line says why");
  assert.equal(G.layoutWelcome(fresh({ refused: "off" })), null);
  assert.equal(G.layoutWelcome(fresh({ config: { editable: false, read_only: [] } })), null);
  assert.equal(G.layoutWelcome(fresh({ config: { editable: true, read_only: ["slots"] } })), null);
});

test("after the first slot a line says what comes next, until a workspace fills one", () => {
  assert.equal(G.layoutHint(oneSlot()),
    "Add more slots (s, then a), or go to Assignment (Tab) to put windows into them.");
  assert.equal(G.layoutHint(oneSlot({ specs: { 3: { main: "foot" } } })), "");
  assert.equal(G.layoutHint(fresh()), "", "the explanation stands in its place");
  assert.equal(G.layoutHint(null), "");
});

test("the first slot's prompt and message speak to a newcomer", () => {
  assert.equal(G.firstSlotLabel(), "Name your first slot (main, left, notes…) [Enter] next  [Esc] cancel: ");
  assert.equal(G.firstSlotAdded("main"), "Made slot 'main': it shows in the picture. Ctrl+S saves.");
});

test("the Assignment tab with zero slots sends you to the Layout tab", () => {
  const e = plain(G.assignmentEmpty(fresh()));
  assert.equal(e.text, "Define slots in the Layout tab first: they are the places your windows go into.");
  assert.deepEqual(e.action, { key: "Tab", label: "Go to Layout" });
  assert.equal(G.assignmentEmpty(oneSlot()), null);
  assert.equal(G.assignmentEmpty(null), null);
  assert.equal(G.assignmentEmpty(fresh({ config_error: "oops" })), null);
});

const row = (status, extra) => ({ kind: status === "empty" || status === "missing" ? status : "window", status, ...extra });

test("a workspace with nothing assigned says how to assign a window", () => {
  const rows = [row("empty", { slot: "main" }), row("none", { cls: "foot" })];
  assert.equal(G.assignmentHint(oneSlot(), rows, 3), "Select a window and press a (or click assign) to put it into a slot.");
});

test("with no window on it, it says to open one first", () => {
  assert.equal(G.assignmentHint(oneSlot(), [row("empty", { slot: "main" })], 3),
    "Open an app on workspace 3, then select it here and press a (or click assign).");
});

test("no hint once something is assigned there, waited for, or there are no slots", () => {
  for (const status of ["slot", "manual", "missing", "overflow"]) {
    assert.equal(G.assignmentHint(oneSlot(), [row(status, { slot: "main" }), row("none")], 3), "", status);
  }
  assert.equal(G.assignmentHint(fresh(), [], 3), "", "the Layout tab comes first");
  assert.equal(G.assignmentHint(null, [], 3), "");
});

test("the Desk tab's opening line says what desks and layouts are", () => {
  assert.equal(G.deskIntro(),
    "A desk is a monitor setup; its layout is how your slots are arranged on its screens."
    + " The other tabs edit the active desk's (●).");
});

test("while the Layout tab explains slots, its help row offers capturing and making the first one", () => {
  assert.deepEqual(plain(G.welcomeHelp()), [
    [{ key: "c", label: "capture my windows" }, { key: "a", label: "create your first slot" }],
    [{ key: "s", label: "slots" }],
    [{ key: "Tab", label: "view" }, { key: "q", label: "close" }],
  ]);
});

test("while the first state read is in flight, a tab says it is reading hyprslots", () => {
  assert.equal(G.reading({ state: null, error: "" }), "Reading hyprslots…");
  assert.equal(G.reading({ state: null, error: "" }, {}), "Reading hyprslots…");
  assert.equal(G.reading({ state: null, error: "" }, { capture: false, record: false }), "Reading hyprslots…");
});

test("a Capture or Record owed on opening is named, so its prompt does not come out of nowhere", () => {
  assert.equal(G.reading({ state: null, error: "" }, { capture: true }), "Reading hyprslots… then capturing your windows");
  assert.equal(G.reading({ state: null, error: "" }, { record: true }), "Reading hyprslots… then recording your windows");
});

test("nothing is said to be reading once a state is there, on an error, or with no engine", () => {
  assert.equal(G.reading({ state: fresh(), error: "" }, { capture: true }), "");
  assert.equal(G.reading({ state: null, error: "hyprslots is not running" }, { capture: true }), "");
  assert.equal(G.reading({ state: fresh(), error: "timed out" }), "");
  assert.equal(G.reading(null, { record: true }), "");
  assert.equal(G.reading(undefined), "");
});
