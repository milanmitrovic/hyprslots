// The Arrangements view's model (Arrangements.js): every arrangement with
// its screens, which one these monitors run, and what a new one for them
// would look like.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const A = load("Arrangements.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

function fixture() {
  return {
    arrangement: "dual",
    screens: { big: "HEADLESS-2", side: "HEADLESS-3" },
    pinned: ["side"],
    monitors: [
      { name: "HEADLESS-2", description: "Dell U2723QE ABC", serial: "", focused: true },
      { name: "HEADLESS-3", description: "", serial: "SER-3", focused: false },
    ],
    arrangements: {
      dual: {
        screens: { big: "Dell U2723QE ABC", side: "HEADLESS-3" },
        roles: ["big", "side"],
        active: true,
        read_only: false,
        desks: { 3: { big: { tree: "h[main:2, right]" }, side: { tree: "left" } }, 5: { big: { tree: "x" } } },
      },
      single: { screens: { big: "HEADLESS-2" }, roles: ["big"], active: false, read_only: false, desks: {} },
      work: { screens: { a: "DP-1", b: "SER-3" }, roles: ["a", "b"], active: false, read_only: true, desks: {} },
    },
  };
}

test("a selector finds its monitor by description, then serial, then connector", () => {
  const monitors = fixture().monitors;
  assert.equal(A.resolve("Dell U2723QE ABC", monitors), "HEADLESS-2");
  assert.equal(A.resolve("SER-3", monitors), "HEADLESS-3");
  assert.equal(A.resolve("HEADLESS-3", monitors), "HEADLESS-3");
  assert.equal(A.resolve("DP-1", monitors), null);
});

test("rows list every arrangement by name with its screens, what each finds, and whether these monitors fit it", () => {
  const rows = plain(A.rows(fixture()));
  assert.deepEqual(rows.map((r) => [r.name, r.active, r.fits, r.readOnly]), [
    ["dual", true, true, false],
    ["single", false, false, false],
    ["work", false, false, true],
  ]);
  assert.deepEqual(rows[0].screens, [
    { role: "big", selector: "Dell U2723QE ABC", monitor: "HEADLESS-2", pinned: false },
    { role: "side", selector: "HEADLESS-3", monitor: "HEADLESS-3", pinned: true },
  ]);
  assert.equal(rows[2].screens[0].monitor, null);
});

test("a row reads like the TUI's: name, screen count, the marker on the one in use", () => {
  const rows = A.rows(fixture());
  assert.equal(A.rowText(rows[0]), "dual   2 screens   ● in use here");
  assert.equal(A.rowText(rows[1]), "single   1 screen");
  assert.equal(A.rowText(rows[2]), "work   2 screens   (set in config.lua)");
});

test("the header names these monitors and what they run", () => {
  assert.deepEqual(plain(A.header(fixture())), [
    "These monitors: HEADLESS-2 (Dell U2723QE ABC) + HEADLESS-3 (SER-3)",
    "Running: dual",
  ]);
  const none = fixture();
  none.arrangement = null;
  assert.equal(A.header(none)[1], "Running: nothing — no arrangement names exactly these screens");
});

test("a new arrangement selects each monitor by description, else serial, else connector", () => {
  const monitors = fixture().monitors;
  assert.equal(A.selectorFor(monitors[0]), "Dell U2723QE ABC");
  assert.equal(A.selectorFor(monitors[1]), "SER-3");
  assert.equal(A.selectorFor({ name: "eDP-1", description: "", serial: "" }), "eDP-1");
});

test("a new arrangement's roles are suggested from what the running one calls each monitor", () => {
  const state = fixture();
  assert.equal(A.suggestedRole(state, state.monitors[0], 0, []), "big");
  state.screens = {};
  assert.equal(A.suggestedRole(state, state.monitors[1], 1, []), "screen2");
  assert.equal(A.suggestedRole(state, { name: "eDP-1" }, 0, []), "laptop");
  assert.equal(A.suggestedRole(state, { name: "eDP-1" }, 0, ["laptop"]), "laptop2");
});

test("every way to select a monitor is a suggestion", () => {
  assert.deepEqual(plain(A.selectorSuggestions(fixture().monitors)), ["Dell U2723QE ABC", "HEADLESS-2", "SER-3", "HEADLESS-3"]);
});

test("copying trees maps roles of the same name, and says which need asking", () => {
  assert.deepEqual(plain(A.roleMapping(["big", "side"], ["big", "laptop"])), { map: { big: "big" }, ask: ["laptop"] });
  assert.deepEqual(plain(A.roleMapping(["big"], ["big"])), { map: { big: "big" }, ask: [] });
});

test("copy sources are the default trees, then every other arrangement", () => {
  assert.deepEqual(plain(A.copySources(fixture(), "single")), [
    { label: "default", value: { default: true } },
    { label: "dual", value: { from: "dual" } },
    { label: "work", value: { from: "work" } },
  ]);
});

test("deleting says which trees go, and when these monitors will run nothing", () => {
  const rows = A.rows(fixture());
  assert.equal(A.deleteQuestion(rows[0]),
    "Delete arrangement 'dual'? It takes its trees for desks 3, 5; these monitors will run nothing until another matches them.");
  assert.equal(A.deleteQuestion(rows[1]), "Delete arrangement 'single'? It holds no trees.");
});

test("no state, no rows", () => {
  assert.deepEqual(plain(A.rows(null)), []);
});
