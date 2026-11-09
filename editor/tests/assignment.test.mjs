// The Assignment view's model (Assignment.js): which rows a workspace shows, in
// what order, and which slots `a` offers, from an api `state` reply.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const A = load("Assignment.js");
const P = load("Prompts.js");

// Plain copies, so deepEqual does not trip over the vm context's prototypes.
const plain = (value) => JSON.parse(JSON.stringify(value));

function window(address, cls, workspaceId, extra) {
  return { address, class: cls, title: cls + " title", workspace_id: workspaceId, floating: false, ...extra };
}

// Layout dual (2 screens): screen 1 = h[main:2, right:1], screen 2 = left;
// workspace 4 has one slot on screen 1.
function fixture() {
  return {
    ok: true,
    desk: "docked",
    layout: "dual",
    screens: ["HEADLESS-2", "HEADLESS-3"],
    used_workspaces: [3, 4],
    slots: [{ name: "left" }, { name: "mail" }, { name: "main" }, { name: "right" }],
    specs: { 3: { left: "t-left", main: "t-main", right: "t-right" }, 4: { mail: "thunderbird" } },
    layouts: {
      dual: {
        screens: 2,
        active: true,
        own: [3, 4],
        workspaces: {
          3: { 1: { tree: "h[main:2, right]", slots: ["main", "right"] }, 2: { tree: "left", slots: ["left"] } },
          4: { 1: { tree: "mail", slots: ["mail"] } },
        },
      },
    },
    workspaces: { 3: { workspace: 3, screen: 1, monitor: "HEADLESS-2" }, 13: { workspace: 3, screen: 2, monitor: "HEADLESS-3" },
      4: { workspace: 4, screen: 1, monitor: "HEADLESS-2" } },
    assignments: { "0xa": { workspace: 3, slot: "main" }, "0xe": { workspace: 3, slot: "right", manual: true } },
    overflow: { "0xb": { workspace: 3, slot: "main" } },
    unassigned: ["0xd"],
    windows: [
      window("0xa", "t-main", 3, { workspace: 3, slot: "main" }),
      window("0xb", "t-main", 3, { overflow: { workspace: 3, slot: "main" } }),
      window("0xc", "firefox", 1),
      window("0xd", "foot", 13, { unassigned: true }),
      window("0xe", "t-right", 3, { workspace: 3, slot: "right" }),
    ],
  };
}

const summary = (rows) => plain(rows).map((r) => [r.status, r.slot || "", r.address]);

test("pages are workspaces 1 to N, the managed ones, and no others", () => {
  const ten = plain(A.pages(fixture()));
  assert.deepEqual(ten.map((p) => p.workspace), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10], "ten without workspace_count");
  assert.deepEqual(ten[2], { workspace: 3, label: "Workspace 3" });
  const state = fixture();
  state.workspace_count = 9;
  assert.deepEqual(plain(A.pages(state)).map((p) => p.workspace), [1, 2, 3, 4, 5, 6, 7, 8, 9]);
  assert.ok(plain(A.pages(state)).every((p) => p.workspace !== null), "no every-window page");
});

test("a workspace lists its slots in tree order, screen by screen, a missing window as a placeholder, then every other global slot, then overflow and strays", () => {
  assert.deepEqual(summary(A.rows(fixture(), 3)), [
    ["slot", "main", "0xa"],
    ["manual", "right", "0xe"],
    ["missing", "left", null],
    ["empty", "mail", null],
    ["overflow", "main", "0xb"],
    ["unassigned", "", "0xd"],
  ]);
});

test("rows say which screen each slot or window is on, by the monitor there", () => {
  const state = fixture();
  const rows = plain(A.rows(state, 3));
  assert.deepEqual(rows.map((r) => r.screen), [1, 1, 2, null, 1, 2]);
  assert.deepEqual(rows.map((r) => A.screenText(state, r)), ["1 HEADLESS-2", "1 HEADLESS-2", "2 HEADLESS-3", "", "1 HEADLESS-2",
    "2 HEADLESS-3"]);
  assert.equal(A.screenText(state, { screen: null }), "");
});

test("no workspace means no rows", () => {
  assert.deepEqual(plain(A.rows(fixture(), null)), []);
});

test("the slot column reads like the TUI's", () => {
  const text = plain(A.rows(fixture(), 3)).map((r) => A.slotText(r));
  assert.deepEqual(text, ["main", "right (by hand)", "left", "mail", "other (main taken)", "unassigned"]);
  assert.equal(A.slotText({ status: "none" }), "—");
});

test("the slots no tree of the active layout shows follow the shown ones by name, a spec making one Missing", () => {
  const state = fixture();
  state.slots.push({ name: "spare" });
  state.specs[3].spare = "t-spare";
  const rows = plain(A.rows(state, 3));
  assert.deepEqual(rows.map((r) => [r.kind, r.slot || ""]),
    [["window", "main"], ["window", "right"], ["missing", "left"], ["empty", "mail"],
      ["missing", "spare"], ["window", "main"], ["window", ""]]);
  assert.ok(rows.every((r) => !("placed" in r)), "no row is told apart as placed or not");
  assert.deepEqual([A.specText(rows[4]), A.titleText(rows[4])], ["t-spare", "Missing — waiting for it to open"]);
});

test("a slot a tree places but the workspace has no spec for is empty, not Missing: no spec, no Missing title", () => {
  const state = fixture();
  state.layouts.dual.workspaces[4][1] = { tree: "h[mail, main]", slots: ["mail", "main"] };
  const rows = plain(A.rows(state, 4));
  assert.deepEqual(rows.slice(0, 2).map((r) => [r.kind, r.status, r.slot, r.spec]), [
    ["missing", "missing", "mail", "thunderbird"],
    ["empty", "empty", "main", ""],
  ]);
  assert.deepEqual([A.slotText(rows[1]), A.specText(rows[1]), A.titleText(rows[1])], ["main", "—", "—"]);
  assert.deepEqual([A.slotText(rows[0]), A.specText(rows[0]), A.titleText(rows[0])], ["mail", "thunderbird", "Missing — waiting for it to open"]);
  assert.equal(A.titleText({ kind: "window", title: "" }), "No Title");
  assert.equal(A.titleText({ kind: "window", title: "vim" }), "vim");
});

test("every global slot is a row of every workspace: one no spec fills is empty", () => {
  const rows = plain(A.rows(fixture(), 4));
  assert.deepEqual(rows.map((r) => [r.kind, r.slot]),
    [["missing", "mail"], ["empty", "left"], ["empty", "main"], ["empty", "right"]]);
  assert.deepEqual([A.slotText(rows[1]), A.specText(rows[1]), A.titleText(rows[1])], ["left", "—", "—"]);
});

test("workspace 8's scroll[main, right] with a spec for main only: main Missing, right and left all empty alike", () => {
  const state = {
    ok: true, desk: "laptop", layout: "scroll", screens: ["eDP-1"], used_workspaces: [8],
    slots: [{ name: "left" }, { name: "main" }, { name: "right" }],
    specs: { 8: { main: "[Research]" } },
    layouts: { scroll: { screens: 1, active: true, own: [8], used_by: ["laptop"],
      workspaces: { 8: { 1: { tree: "scroll[main, right]", slots: ["main", "right"] } } } } },
    workspaces: { 8: { workspace: 8, screen: 1, monitor: "eDP-1" } },
    assignments: {}, overflow: {}, unassigned: [], windows: [],
  };
  const rows = plain(A.rows(state, 8));
  assert.deepEqual(rows.map((r) => [A.slotText(r), A.specText(r), A.titleText(r)]), [
    ["main", "[Research]", "Missing — waiting for it to open"],
    ["right", "—", "—"],
    ["left", "—", "—"],
  ]);
});

test("assign offers every global slot on the workspace: its own in tree order first, then the rest by name", () => {
  const options = plain(A.slotOptions(fixture(), 3));
  assert.deepEqual(options.map((o) => [o.key, o.workspace, o.slot, o.spec, o.holder]), [
    ["m", 3, "main", "t-main", "0xa"],
    ["r", 3, "right", "t-right", "0xe"],
    ["l", 3, "left", "t-left", null],
    ["1", 3, "mail", "", null],
  ]);
});

test("a first letter already taken falls back to the first free digit", () => {
  const state = fixture();
  state.slots = [{ name: "main" }, { name: "menu" }, { name: "mail" }];
  state.specs[3] = { main: "a", menu: "b", mail: "c" };
  state.layouts.dual.workspaces[3] = { 1: { slots: ["main", "menu", "mail"] } };
  assert.deepEqual(plain(A.slotOptions(state, 3)).map((o) => o.key), ["m", "1", "2"]);
});

test("assign offers the page's workspace's slots, none without one", () => {
  const state = fixture();
  assert.deepEqual(plain(A.slotOptions(state, 4)).map((o) => o.workspace + "/" + o.slot),
    ["4/mail", "4/left", "4/main", "4/right"]);
  assert.deepEqual(plain(A.slotOptions(state, null)), []);
});

test("the prompt names the workspace and each option the way aerolayout's does", () => {
  const ask = (state, workspace, row) =>
    P.display(P.choice(A.assignTitle(workspace, "kitty"), A.promptOptions(A.slotOptions(state, workspace))));
  assert.equal(ask(fixture(), 3, null), "Assign kitty to a slot on workspace 3: (m)ain, (r)ight, (l)eft, (1) mail? [Esc] cancel   → main");
  const picked = A.promptOptions(A.slotOptions(fixture(), 3))[1].value;
  assert.deepEqual([picked.workspace, picked.slot], [3, "right"], "an option's value is the slot option itself");
});

test("u on a window in a slot takes it out and clears the workspace's spec for the slot", () => {
  const state = fixture();
  const rows = A.rows(state, 3);
  assert.deepEqual(plain(A.unassignPlan(state, rows[0])), { address: "0xa", clearSpec: true,
    question: "Unassign t-main from main on workspace 3? The slot is left empty." });
  assert.deepEqual(plain(A.unassignPlan(state, rows[1])), { address: "0xe", clearSpec: true,
    question: "Unassign t-right from right on workspace 3? The slot is left empty." });
});

test("u on an overflowing window, or one in a slot with no spec, only takes it out", () => {
  const state = fixture();
  const rows = A.rows(state, 3);
  assert.deepEqual(plain(A.unassignPlan(state, rows.find((r) => r.address === "0xb"))), { address: "0xb", clearSpec: false,
    question: "Unassign t-main from main? It waits with the other windows while main is taken." });
  delete state.specs[3].right;
  assert.deepEqual(plain(A.unassignPlan(state, A.rows(state, 3)[1])), { address: "0xe", clearSpec: false,
    question: "Unassign t-right from right?" });
});

test("u on a Missing row clears the workspace's spec for the slot: the slot is left empty", () => {
  const state = fixture();
  const rows = A.rows(state, 3);
  assert.deepEqual(plain(A.unassignPlan(state, rows[2])), { clear: { workspace: 3, slot: "left", spec: "t-left" },
    question: "Unassign t-left from left on workspace 3? It is not open; the slot is left empty." });
});

test("u refuses an empty slot, a window in no slot and no selection", () => {
  const state = fixture();
  state.layouts.dual.workspaces[4][1] = { tree: "h[mail, main]", slots: ["mail", "main"] };
  assert.equal(A.unassignPlan(state, A.rows(state, 4)[1]).error,
    "Nothing is assigned to main on workspace 4: there is nothing to unassign.");
  const rows = A.rows(state, 3);
  assert.equal(A.unassignPlan(state, rows.find((r) => r.address === "0xd")).error, "foot is assigned to no slot.");
  assert.equal(A.unassignPlan(state, null).error, "Nothing selected.");
});

test("the first page shown is the focused workspace's, else workspace 1's", () => {
  const state = fixture();
  assert.equal(A.initialPage(state, 13), 2);
  assert.equal(A.initialPage(state, 4), 3);
  assert.equal(A.initialPage(state, 1), 0, "a workspace id the desk does not manage");
  assert.equal(A.initialPage(state, null), 0);
  state.workspace_count = 3;
  assert.equal(A.initialPage(state, 4), 0, "workspace 4 is not managed");
});

test("a workspace's page, for the digit keys; -1 for one not managed", () => {
  const state = fixture();
  assert.equal(A.pageOfWorkspace(state, 3), 2);
  assert.equal(A.pageOfWorkspace(state, 10), 9);
  state.workspace_count = 9;
  assert.equal(A.pageOfWorkspace(state, 10), -1);
});

test("no state yet means pages 1 to 10, and no rows", () => {
  assert.deepEqual(plain(A.pages(null)).map((p) => p.workspace), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
  assert.deepEqual(plain(A.rows(null, 3)), []);
});

test("the message after a says which slot the window took, whom it replaced and who gave it up; nothing of placing", () => {
  const state = { windows: [{ address: "0xf", class: "foot" }] };
  assert.equal(A.assignedText(state, "kitty", { slot: "main", workspace: 3, spec: "kitty", replaced: "foot", displaced: "0xf" }),
    "Assigned kitty to main on workspace 3 (instead of foot); foot gave it up. Ctrl+S saves.");
  assert.equal(A.assignedText(state, "kitty", { slot: "left", workspace: 8, spec: "kitty", replaced: "kitty" }),
    "Assigned kitty to left on workspace 8. Ctrl+S saves.");
  assert.equal(A.placeNote, undefined);
  assert.equal(A.placedText, undefined);
});
