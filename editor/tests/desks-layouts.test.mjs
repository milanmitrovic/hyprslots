// The Desks & Layouts view's model (DesksLayouts.js): every stored desk (a
// monitor setup) and every layout (a logical arrangement for N screens),
// which desk is active and which layout it uses, and what each key does on
// which row.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const D = load("DesksLayouts.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

const SAMSUNG = "Samsung Odyssey G95NC HNTW700044";

function fixture() {
  return {
    desk: "docked",
    layout: "docked",
    screens: ["eDP-1", "DP-2"],
    pinned: [1],
    monitors: [
      { name: "DP-2", description: SAMSUNG, serial: "HNTW700044", selector: SAMSUNG, x: 1920, y: 0 },
      { name: "eDP-1", description: "BOE 0x0BCA", serial: "", selector: "eDP-1", x: 0, y: 0, internal: true },
    ],
    desks: {
      docked: { monitors: ["eDP-1", SAMSUNG], connected: [true, true], layout: "docked", pinned: [1], active: true,
        screens: ["eDP-1", "DP-2"], read_only: false },
      laptop: { monitors: ["eDP-1"], connected: [true], layout: "laptop", pinned: [], active: false, read_only: false },
      office: { monitors: ["eDP-1", "Dell U2723QE ABC"], connected: [true, false], layout: "docked", pinned: [],
        active: false, read_only: true },
    },
    layouts: {
      docked: { screens: 2, default: { 1: { tree: "main" } }, workspaces: {}, own: [3], used_by: ["docked", "office"],
        active: true, read_only: false },
      "docked-2": { screens: 2, default: {}, workspaces: {}, own: [], used_by: [], active: false, read_only: false },
      laptop: { screens: 1, default: {}, workspaces: {}, own: [3], used_by: ["laptop"], active: false, read_only: false },
      wide: { screens: 2, default: {}, workspaces: {}, own: [], used_by: [], active: false, read_only: true },
    },
  };
}

test("rows are every desk by name, then every layout by name", () => {
  assert.deepEqual(plain(D.rows(fixture())).map((r) => [r.kind, r.name, r.active]), [
    ["desk", "docked", true],
    ["desk", "laptop", false],
    ["desk", "office", false],
    ["layout", "docked", true],
    ["layout", "docked-2", false],
    ["layout", "laptop", false],
    ["layout", "wide", false],
  ]);
  assert.deepEqual(plain(D.rows(null)), []);
});

test("a desk row has its monitors, whether each is connected and which monitor it is, its layout and pinned screens", () => {
  const rows = plain(D.rows(fixture()));
  assert.deepEqual(rows[0], {
    kind: "desk", key: "desk:docked", name: "docked", active: true, auto: false, readOnly: false, layout: "docked",
    screens: 2, pinned: [1],
    monitors: [
      { selector: "eDP-1", connected: true, connector: "eDP-1", description: "BOE 0x0BCA" },
      { selector: SAMSUNG, connected: true, connector: "DP-2", description: SAMSUNG },
    ],
  });
  assert.deepEqual(rows[2].monitors[1], { selector: "Dell U2723QE ABC", connected: false, connector: "", description: "" });
  assert.equal(rows[2].readOnly, true);
});

test("a desk the engine just made is marked new and unsaved", () => {
  const state = fixture();
  state.desks.laptop.auto = true;
  assert.equal(D.rows(state)[1].auto, true);
  assert.match(D.deskCells(D.rows(state)[1]).name, /^laptop \(new, unsaved\)$/);
});

test("a desk row reads: name, monitors with ● when connected, the layout, the pinned screens", () => {
  const rows = D.rows(fixture());
  assert.deepEqual(plain(D.deskCells(rows[0])), {
    mark: "● active",
    name: "docked",
    monitors: "● eDP-1 (BOE 0x0BCA) + ● " + SAMSUNG + " (DP-2)",
    layout: "layout docked",
    pinned: "pinned 1",
  });
  assert.deepEqual(plain(D.deskCells(rows[2])), {
    mark: "",
    name: "office (set in config.lua)",
    monitors: "● eDP-1 (BOE 0x0BCA) + ○ Dell U2723QE ABC",
    layout: "layout docked",
    pinned: "",
  });
});

test("a layout row has its screen count and the desks that use it", () => {
  const rows = D.rows(fixture());
  assert.deepEqual(plain(rows[3]), { kind: "layout", key: "layout:docked", name: "docked", active: true, readOnly: false,
    screens: 2, usedBy: ["docked", "office"] });
  assert.deepEqual(plain(D.layoutCells(rows[3])), { mark: "● active", name: "docked", screens: "2 screens",
    usedBy: "used by docked, office" });
  assert.deepEqual(plain(D.layoutCells(rows[5])), { mark: "", name: "laptop", screens: "1 screen", usedBy: "used by laptop" });
  assert.deepEqual(plain(D.layoutCells(rows[6])), { mark: "", name: "wide (set in config.lua)", screens: "2 screens",
    usedBy: "unused" });
});

test("the keys that act on a row: a desk takes p, a layout does not", () => {
  const rows = D.rows(fixture());
  assert.deepEqual(plain(D.actions(rows[0]).map((a) => a.key)), ["a", "f", "n", "r", "x", "p"]);
  assert.deepEqual(plain(D.actions(rows[3]).map((a) => a.key)), ["a", "f", "n", "r", "x"]);
  assert.deepEqual(plain(D.actions(rows[3]).map((a) => a.label)), ["apply to the active desk", "fork", "new layout",
    "rename", "delete"]);
  assert.deepEqual(plain(D.actions(rows[0]).map((a) => a.label)), ["apply a layout", "fork its layout", "new layout",
    "rename", "delete", "pin a screen"]);
  assert.deepEqual(plain(D.actions(null).map((a) => a.key)), ["n"]);
});

test("a desk may use the layouts with as many screens as it has monitors", () => {
  const state = fixture();
  assert.deepEqual(plain(D.layoutsFor(state, "docked")), ["docked", "docked-2", "wide"]);
  assert.deepEqual(plain(D.layoutsFor(state, "laptop")), ["laptop"]);
  assert.deepEqual(plain(D.layoutsFor(state, "nope")), []);
});

test("applying a layout to the active desk is refused when the screen counts differ, or there is no active desk", () => {
  const state = fixture();
  assert.equal(D.applyBlock(state, "docked-2"), "");
  assert.equal(D.applyBlock(state, "laptop"), "Layout 'laptop' has 1 screen; desk 'docked' has 2 monitors.");
  state.desk = null;
  assert.equal(D.applyBlock(state, "docked-2"), "No desk is active: these monitors have none yet.");
});

test("a fork is suggested as <name>-2, or the next free number", () => {
  const state = fixture();
  assert.equal(D.forkName(state, "laptop"), "laptop-2");
  assert.equal(D.forkName(state, "docked"), "docked-3", "docked-2 is taken");
  assert.equal(D.forkName(state, "docked-2"), "docked-3", "a fork of a fork counts on");
  assert.equal(D.forkName(null, "x"), "x-2");
});

test("the layout a fork copies: the selected one, or on a desk row that desk's", () => {
  const rows = D.rows(fixture());
  assert.equal(D.forkSource(rows[1]), "laptop");
  assert.equal(D.forkSource(rows[4]), "docked-2");
  assert.equal(D.forkSource(null), null);
});

test("a fork's reply says whether the active desk now uses the copy", () => {
  assert.equal(D.forkMessage({ layout: "docked", to: "docked-3", desk: "docked" }),
    "Forked 'docked' as 'docked-3'; desk 'docked' uses it now. Ctrl+S saves.");
  assert.equal(D.forkMessage({ layout: "laptop", to: "laptop-2", desk: null }),
    "Forked 'laptop' as 'laptop-2'; the active desk has another screen count, so it keeps its layout. Ctrl+S saves.");
});

test("a new layout's screen count is suggested from the active desk", () => {
  assert.equal(D.suggestedScreens(fixture()), 2);
  const none = fixture();
  none.desk = null;
  none.screens = [];
  assert.equal(D.suggestedScreens(none), 1);
});

test("a screen count must be a whole number from 1", () => {
  assert.deepEqual(plain(D.parseScreens(" 2 ")), { screens: 2 });
  assert.match(D.parseScreens("0").error, /whole number/);
  assert.match(D.parseScreens("two").error, /whole number/);
  assert.match(D.parseScreens("1.5").error, /whole number/);
});

test("deleting a desk asks, and warns when it is the active one", () => {
  const rows = D.rows(fixture());
  assert.equal(D.deleteDeskQuestion(rows[1]), "Delete desk 'laptop'? Its layout 'laptop' stays.");
  assert.equal(D.deleteDeskQuestion(rows[0]), "Delete desk 'docked'? It is the active desk: these monitors get a new desk "
    + "(the layout used last with 2 screens) in a second. Its layout 'docked' stays.");
});

test("deleting a used layout offers the layouts with as many screens to move its desks to", () => {
  const state = fixture();
  const rows = D.rows(state);
  const used = plain(D.deleteLayoutPlan(state, rows[3]));
  assert.equal(used.question, "Layout 'docked' is used by desks docked, office: move them to");
  assert.deepEqual(used.remap, ["docked-2", "wide"]);
  assert.deepEqual(plain(D.deleteLayoutPlan(state, rows[4])), { question: "Delete layout 'docked-2'? No desk uses it.", remap: [] });
  // laptop is used, and no other 1-screen layout can take its desk: the engine says why
  assert.deepEqual(plain(D.deleteLayoutPlan(state, rows[5])), { question: "Delete layout 'laptop'? Desk laptop uses it.",
    remap: [] });
});

test("the screens p offers: on the active desk the monitor at each position, else the selector", () => {
  const state = fixture();
  const rows = D.rows(state);
  assert.deepEqual(plain(D.pinOptions(state, rows[0])), [
    { key: "1", label: "screen 1: eDP-1 (BOE 0x0BCA) — pinned", value: 1 },
    { key: "2", label: "screen 2: DP-2 (" + SAMSUNG + ")", value: 2 },
  ]);
  assert.deepEqual(plain(D.pinOptions(state, rows[2])), [
    { key: "1", label: "screen 1: eDP-1", value: 1 },
    { key: "2", label: "screen 2: Dell U2723QE ABC", value: 2 },
  ]);
});

test("pinning toggles the screen in the desk's list", () => {
  assert.deepEqual(plain(D.togglePinned([1], 2)), [1, 2]);
  assert.deepEqual(plain(D.togglePinned([1, 2], 1)), [2]);
  assert.deepEqual(plain(D.togglePinned([], 1)), [1]);
});

test("the panel's header names the desk, its layout and the other desks that share it", () => {
  const state = fixture();
  assert.equal(D.header(state), "Desk: docked · Layout: docked (also used by: office)");
  state.layout = "laptop";
  state.desk = "laptop";
  assert.equal(D.header(state), "Desk: laptop · Layout: laptop");
  state.desks.laptop.auto = true;
  assert.equal(D.header(state), "Desk: laptop (new, unsaved) · Layout: laptop");
  state.desk = null;
  state.layout = null;
  assert.equal(D.header(state), "Desk: none");
  assert.equal(D.header(null), "Desk: none");
});

test("the other desks that use a layout, for the warning that an edit changes it for them too", () => {
  assert.deepEqual(plain(D.sharedWith(fixture(), "docked", "docked")), ["office"]);
  assert.deepEqual(plain(D.sharedWith(fixture(), "laptop", "laptop")), []);
  assert.deepEqual(plain(D.sharedWith(fixture(), "nope", "docked")), []);
});

test("a read-only row refuses edits, saying where it is set", () => {
  const rows = D.rows(fixture());
  assert.equal(D.readOnlyError(rows[2]), "Desk 'office' is set in config.lua.");
  assert.equal(D.readOnlyError(rows[6]), "Layout 'wide' is set in config.lua.");
  assert.equal(D.readOnlyError(rows[0]), "");
});
