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
    arrangement: "dual",
    used_workspaces: [3, 4],
    slots: [{ name: "left" }, { name: "main", description: "the editor" }, { name: "right" }, { name: "spare" }],
    specs: { 3: { main: "t-main", right: "t-right", left: "t-left" }, 4: { main: "thunderbird" } },
    arrangements: {
      dual: {
        roles: ["big", "side"],
        active: true,
        workspaces: {
          3: { big: { tree: "h[main:2, right]", slots: ["main", "right"] }, side: { tree: "left", slots: ["left"] } },
          4: { big: { tree: "main", slots: ["main"] } },
        },
      },
      single: { roles: ["big"], active: false, workspaces: { 3: { big: { tree: "h[left, main, right]", slots: ["left", "main", "right"] } } } },
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

test("each row says which trees place the slot, as arrangement/workspace/role", () => {
  const rows = plain(S.rows(fixture()));
  assert.deepEqual(rows[1].places, ["dual/3/big", "dual/4/big", "single/3/big"]);
  assert.deepEqual(rows[3].places, []);
});

test("each row says which workspaces fill the slot, and with what", () => {
  const rows = plain(S.rows(fixture()));
  assert.deepEqual(rows[1].specs, [{ workspace: 3, spec: "t-main" }, { workspace: 4, spec: "thunderbird" }]);
  assert.deepEqual(rows[3].specs, []);
});

test("deleting a slot asks plainly when nothing uses it, else names every tree and workspace it goes from", () => {
  const rows = S.rows(fixture());
  assert.equal(S.deleteQuestion(rows[3]), "Delete slot 'spare'?");
  assert.equal(
    S.deleteQuestion(rows[2]),
    "Delete slot 'right'? It goes from the trees dual/3/big, single/3/big and the specs of workspace 3.",
  );
  assert.equal(S.deleteQuestion(rows[1]),
    "Delete slot 'main'? It goes from the trees dual/3/big, dual/4/big, single/3/big and the specs of workspaces 3, 4.");
});

test("no state, no rows", () => {
  assert.deepEqual(plain(S.rows(null)), []);
});

test("the slots are read-only when config.lua builds them in code, or there is no data file, and says why", () => {
  const state = fixture();
  state.config = { editable: true, read_only: ["specs.4"] };
  assert.equal(S.readOnlyReason(state), "");
  state.config.read_only = ["slots"];
  assert.equal(S.readOnlyReason(state), "the slots are set by code in config.lua; edit them there");
  state.config = { editable: false, read_only: [] };
  assert.equal(S.readOnlyReason(state), "config.lua loads no slots.lua, so there is nothing the editor may change");
});
