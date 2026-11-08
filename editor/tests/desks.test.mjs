// Desk keys (Desks.js), the same in the Layout and Assignment views: [ and ]
// step through desks 1 to 10, the digits jump (0 is desk 10), and a strip
// shows which desks have trees.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const D = load("Desks.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

test("] and [ step to the next and previous desk, round from 10 to 1 and back", () => {
  assert.equal(D.step(3, 1), 4);
  assert.equal(D.step(3, -1), 2);
  assert.equal(D.step(10, 1), 1);
  assert.equal(D.step(1, -1), 10);
});

test("a desk out of range steps from the nearest end", () => {
  assert.equal(D.step(0, 1), 1);
  assert.equal(D.step(0, -1), 10);
});

test("the digits jump to desks 1 to 9, and 0 to desk 10, as Super+N does", () => {
  assert.equal(D.ofDigit("1"), 1);
  assert.equal(D.ofDigit("9"), 9);
  assert.equal(D.ofDigit("0"), 10);
  assert.equal(D.ofDigit("a"), null);
  assert.equal(D.ofDigit(""), null);
  assert.equal(D.ofDigit("12"), null);
});

test("the strip marks the current desk and the desks an arrangement has trees for", () => {
  const state = { arrangements: { solo: { desks: { 3: { main: { tree: "a" } }, 10: { main: { tree: "b" } } } } } };
  const strip = plain(D.strip(state, "solo", 3));
  assert.equal(strip.length, 10);
  assert.deepEqual(strip[2], { desk: 3, label: "3", current: true, trees: true });
  assert.deepEqual(strip[0], { desk: 1, label: "1", current: false, trees: false });
  assert.deepEqual(strip[9], { desk: 10, label: "0", current: false, trees: true });
  assert.equal(plain(D.strip(null, "solo", 1)).filter((d) => d.trees).length, 0);
});
