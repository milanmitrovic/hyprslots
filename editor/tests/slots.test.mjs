// The slot list's model (Slots.js, the Layout view's list): the global
// slots, each with its description, the trees that place it and the workspaces
// that say which app fills it (which a delete names).
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const S = load("Slots.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

function fixture() {
  return {
    layout: "dual",
    used_workspaces: [3, 4, 5],
    slots: [{ name: "left" }, { name: "main", description: "the editor" }, { name: "right" }, { name: "spare" }],
    specs: { 3: { main: "t-main", right: "t-right", left: "t-left" }, 4: { main: "thunderbird" } },
    layouts: {
      dual: {
        screens: 2,
        active: true,
        own: [3, 4],
        default: {},
        workspaces: {
          3: { 1: { tree: "h[main:2, right]", slots: ["main", "right"] }, 2: { tree: "left", slots: ["left"] } },
          4: { 1: { tree: "main", slots: ["main"] } },
        },
      },
      // workspace 5 shows single's default trees, which are no tree of its own
      single: { screens: 1, active: false, own: [3], default: { 1: { tree: "main", slots: ["main"] } },
        workspaces: { 3: { 1: { tree: "h[left, main, right]", slots: ["left", "main", "right"] } },
          5: { 1: { tree: "main", slots: ["main"] } } } },
    },
  };
}

test("a row per global slot, by name, with its description", () => {
  const rows = plain(S.rows(fixture()));
  assert.deepEqual(rows.map((r) => [r.slot, r.description]), [
    ["left", ""],
    ["main", "the editor"],
    ["right", ""],
    ["spare", ""],
  ]);
});

test("each row says which trees place the slot, as layout/workspace/screen (or layout/default/screen)", () => {
  const rows = plain(S.rows(fixture()));
  assert.deepEqual(rows[1].places, ["dual/3/1", "dual/4/1", "single/default/1", "single/3/1"]);
  assert.deepEqual(rows[3].places, []);
});

test("each row says which workspaces fill the slot, and with what", () => {
  const rows = plain(S.rows(fixture()));
  assert.deepEqual(rows[1].specs, [{ workspace: 3, spec: "t-main" }, { workspace: 4, spec: "thunderbird" }]);
  assert.deepEqual(rows[3].specs, []);
});

test("deleting a slot says it goes from every tree, and from the workspaces that fill it", () => {
  const rows = S.rows(fixture());
  assert.equal(S.deleteQuestion(rows[3]), "Delete slot 'spare'? It goes from every tree.");
  assert.equal(
    S.deleteQuestion(rows[2]),
    "Delete slot 'right'? It goes from every tree and from the assignments of workspace 3.",
  );
  assert.equal(S.deleteQuestion(rows[1]),
    "Delete slot 'main'? It goes from every tree and from the assignments of workspaces 3, 4.");
});

test("no state, no rows", () => {
  assert.deepEqual(plain(S.rows(null)), []);
});

test("the slots are read-only when the config builds them in code, or there is no data file, and says why", () => {
  const state = fixture();
  state.config = { editable: true, read_only: ["specs.4"] };
  assert.equal(S.readOnlyReason(state), "");
  state.config.read_only = ["slots"];
  assert.equal(S.readOnlyReason(state), "the slots are set by code in your config; edit them there");
  state.config = { editable: false, read_only: [] };
  assert.equal(S.readOnlyReason(state), "your config loads no editor data, so there is nothing the editor may change");
});

test("a new slot is in every tree at once: the editor asks nothing about placing it, it says so", () => {
  assert.equal(S.newSlotLabel(), "New slot name (every tree gets it; an empty slot takes no room) [Enter] next  [Esc] cancel: ");
  assert.equal(S.addedText("notes"), "Added slot 'notes' to every tree. Ctrl+S saves.");
  assert.doesNotMatch(S.addedText("notes"), /\?|y\/n|Put it/);
});
