// The read-only summaries the not-yet-built tabs show (Summary.js).
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const S = load("Summary.js");

const state = {
  arrangement: "dual",
  desks: [3],
  slots: { 3: { main: "t-main", left: "t-left" } },
  arrangements: {
    dual: {
      roles: ["big", "side"],
      screens: { big: "HEADLESS-2", side: "HEADLESS-3" },
      active: true,
      read_only: false,
      desks: { 3: { big: { tree: "h[main:2, right]", ratio: "2:1" }, side: { tree: "left", ratio: "1", resized: true } } },
    },
    single: { roles: ["big"], screens: { big: "HEADLESS-2" }, active: false, read_only: true, desks: {} },
  },
};

test("Layout lists each desk's tree per screen of the active arrangement", () => {
  assert.deepEqual(Array.from(S.lines(state, "Layout")), [
    "desk 3  big   h[main:2, right]   ratio 2:1",
    "desk 3  side  left   ratio 1   (resized, unsaved)",
  ]);
});

test("Slots lists each desk's slots and specs by name", () => {
  assert.deepEqual(Array.from(S.lines(state, "Slots")), ["desk 3  left  t-left", "desk 3  main  t-main"]);
});

test("Arrangements lists each with its screens, the active one marked", () => {
  assert.deepEqual(Array.from(S.lines(state, "Arrangements")), [
    "dual  (active)  big = HEADLESS-2, side = HEADLESS-3",
    "single  (set in config.lua)  big = HEADLESS-2",
  ]);
});

test("no state, no lines", () => {
  assert.deepEqual(Array.from(S.lines(null, "Layout")), []);
});
