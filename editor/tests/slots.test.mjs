// The Slots view's model (Slots.js): a desk's slots with their specs,
// descriptions, where the trees place them and the window each holds.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const S = load("Slots.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

function fixture() {
  return {
    arrangement: "dual",
    desks: [3, 4],
    slots: { 3: { main: "t-main", right: "t-right", left: "t-left", spare: "t-spare" }, 4: { mail: "thunderbird" } },
    descriptions: { 3: { main: "the editor" } },
    arrangements: {
      dual: {
        roles: ["big", "side"],
        active: true,
        desks: { 3: { big: { tree: "h[main:2, right]", slots: ["main", "right"] }, side: { tree: "left", slots: ["left"] } } },
      },
      single: { roles: ["big"], active: false, desks: { 3: { big: { tree: "h[left, main, right]", slots: ["left", "main", "right"] } } } },
    },
    workspaces: { 3: { desk: 3, role: "big" }, 13: { desk: 3, role: "side" }, 4: { desk: 4, role: "big" } },
    windows: [
      { address: "0xa", class: "t-main", title: "main title", workspace: 3, desk: 3, slot: "main" },
      { address: "0xb", class: "kitty", title: "deltaf | nvim", workspace: 13 },
      { address: "0xc", class: "firefox", title: "Mozilla", workspace: 1 },
      { address: "0xd", class: "kitty", title: "other", workspace: 1 },
    ],
  };
}

test("pages are desks 1 to 10, saying which have slots", () => {
  const pages = plain(S.pages(fixture()));
  assert.equal(pages.length, 10);
  assert.deepEqual(pages[2], { desk: 3, label: "Desk 3", count: 4 });
  assert.deepEqual(pages[0], { desk: 1, label: "Desk 1", count: 0 });
});

test("the first page is the focused workspace's desk, else the first desk with slots", () => {
  assert.equal(S.initialPage(fixture(), 13), 2);
  assert.equal(S.initialPage(fixture(), 4), 3);
  assert.equal(S.initialPage(fixture(), 1), 2);
  assert.equal(S.initialPage(null, 1), 0);
});

test("a desk's rows are its slots by name (the order windows claim them in), each with spec, description, screen and window", () => {
  const rows = plain(S.rows(fixture(), 3));
  assert.deepEqual(rows.map((r) => [r.slot, r.spec, r.description, r.role, r.holder && r.holder.cls]), [
    ["left", "t-left", "", "side", null],
    ["main", "t-main", "the editor", "big", "t-main"],
    ["right", "t-right", "", "big", null],
    ["spare", "t-spare", "", null, null],
  ]);
});

test("each row says which arrangements' trees place the slot", () => {
  const rows = plain(S.rows(fixture(), 3));
  assert.equal(S.placesText(rows[1]), "dual/big, single/big");
  assert.equal(S.placesText(rows[3]), "no tree");
});

test("take spec offers the desk's windows first, then the rest", () => {
  const options = plain(S.windowOptions(fixture(), 3));
  assert.deepEqual(options.map((o) => [o.key, o.value]), [["1", "0xa"], ["2", "0xb"], ["3", "0xc"], ["4", "0xd"]]);
  assert.equal(options[1].label, "kitty — deltaf | nvim");
});

test("spec suggestions are the classes of the windows, the desk's first, once each", () => {
  assert.deepEqual(plain(S.specSuggestions(fixture(), 3)), ["t-main", "kitty", "firefox"]);
});

test("deleting a slot says which trees lose it", () => {
  const rows = S.rows(fixture(), 3);
  assert.equal(S.deleteQuestion(rows[1], 3), "Delete slot 'main' from desk 3? It goes from dual/big, single/big.");
  assert.equal(S.deleteQuestion(rows[3], 3), "Delete slot 'spare' from desk 3?");
});

test("no state, no rows", () => {
  assert.deepEqual(plain(S.rows(null, 3)), []);
});

test("a desk whose slots config.lua builds in code, or no data file, is read-only, and says why", () => {
  const state = fixture();
  state.config = { editable: true, read_only: ["slots.4"] };
  assert.equal(S.readOnlyReason(state, 3), "");
  assert.equal(S.readOnlyReason(state, 4), "desk 4's slots are set by code in config.lua; edit them there");
  state.config.read_only = ["slots"];
  assert.equal(S.readOnlyReason(state, 3), "desk 3's slots are set by code in config.lua; edit them there");
  state.config = { editable: false, read_only: [] };
  assert.equal(S.readOnlyReason(state, 3), "config.lua loads no slots.lua, so there is nothing the editor may change");
});
