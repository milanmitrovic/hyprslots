// Swapping two screens' trees in the Layout view (Layout.js): a screen's
// pane dragged by its title onto another's, or p (the selected screen with
// the next). Slots move between monitors; the screens keep their numbers.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const L = load("Layout.js");

const plain = (value) => JSON.parse(JSON.stringify(value));
const tree = (text) => {
  const parsed = L.parse(text);
  assert.equal(parsed.error, undefined, parsed.error);
  return parsed.node;
};
// drafts as the view keeps them: screen key -> { node, base (the text in force) }
const drafts = (texts) => {
  const out = {};
  for (const [k, text] of Object.entries(texts)) out[k] = { node: text === null ? null : tree(text), base: text };
  return out;
};
const texts = (d) => Object.fromEntries(Object.entries(d).map(([k, v]) => [k, v.node ? L.format(v.node) : null]));

// --- the swap ------------------------------------------------------------------

test("swapping two screens trades their trees; each keeps the text in force as its base", () => {
  const before = drafts({ 1: "h[main:2, aside]", 2: "v[side, left]" });
  const out = L.swapScreens(before, "1", "2");
  assert.equal(out.error, undefined);
  assert.deepEqual(texts(out.drafts), { 1: "v[side, left]", 2: "h[main:2, aside]" });
  assert.equal(out.drafts["1"].base, "h[main:2, aside]", "screen 1 is edited: its draft is no longer what runs");
  assert.equal(out.drafts["2"].base, "v[side, left]");
});

test("the place for other windows goes with its tree, written or not", () => {
  const out = L.swapScreens(drafts({ 1: "h[main, *]", 2: "v[side, left]" }), "1", "2");
  assert.deepEqual(texts(out.drafts), { 1: "v[side, left]", 2: "h[main, *]" });
  // screen 1's tree now has no * leaf: the engine puts other windows at its right
  assert.equal(L.format(L.withOther(out.drafts["1"].node)), "h[v[side, left]:3, *]");
});

test("a scroll tree keeps its column width, and t's memory of the tiles it came from", () => {
  const start = drafts({ 1: "h[main, aside]", 2: "side" });
  const scrolled = L.cycleScroll(start["1"].node).node; // scroll:0.5[main, aside], remembering h[main, aside]
  start["1"] = { node: scrolled, base: "h[main, aside]" };
  const out = L.swapScreens(start, "1", "2");
  assert.equal(L.format(out.drafts["2"].node), "scroll:0.5[main, aside]");
  assert.equal(L.scrollMode(out.drafts["2"].node), "half");
  // two more t's on screen 2: full width, then the tiles it was made from
  const full = L.cycleScroll(out.drafts["2"].node).node;
  assert.equal(L.format(L.cycleScroll(full).node), "h[main, aside]");
});

test("the drafts given are not changed", () => {
  const before = drafts({ 1: "h[main, aside]", 2: "side" });
  L.swapScreens(before, "1", "2");
  assert.deepEqual(texts(before), { 1: "h[main, aside]", 2: "side" });
});

test("the other screens are left as they are", () => {
  const out = L.swapScreens(drafts({ 1: "a", 2: "b", 3: "c" }), "1", "3");
  assert.deepEqual(texts(out.drafts), { 1: "c", 2: "b", 3: "a" });
});

test("swapping back is where it started, and nothing is edited", () => {
  const start = drafts({ 1: "h[main, aside]", 2: "side" });
  const back = L.swapScreens(L.swapScreens(start, "1", "2").drafts, "2", "1").drafts;
  for (const k of ["1", "2"]) assert.equal(L.format(back[k].node), back[k].base);
});

test("a screen with no tree is not swapped", () => {
  assert.match(L.swapScreens(drafts({ 1: "main", 2: null }), "1", "2").error, /^Screen 2 has no tree/);
  assert.match(L.swapScreens(drafts({ 1: null, 2: "main" }), "1", "2").error, /^Screen 1 has no tree/);
});

test("a screen is not swapped with itself, nor with one that is not there", () => {
  assert.match(L.swapScreens(drafts({ 1: "a", 2: "b" }), "1", "1").error, /itself/);
  assert.match(L.swapScreens(drafts({ 1: "a", 2: "b" }), "1", "3").error, /^There is no screen 3/);
});

test("what a swap says", () => {
  assert.equal(L.swappedText("1", "2"), "Swapped screens 1 and 2: screen 1's slots are on screen 2 now, and screen 2's on screen 1.");
});

// --- p: the selected screen with the next -------------------------------------

test("p swaps with the next screen, round from the last to the first", () => {
  const panes = [{ key: "1" }, { key: "2" }, { key: "3" }];
  assert.equal(L.nextScreen(panes, "1"), "2");
  assert.equal(L.nextScreen(panes, "3"), "1");
  assert.equal(L.nextScreen([{ key: "1" }, { key: "2" }], "2"), "1");
});

test("one screen has none to swap with", () => {
  assert.equal(L.nextScreen([{ key: "1" }], "1"), null);
  assert.equal(L.nextScreen([], ""), null);
});

// --- drag and drop -----------------------------------------------------------------

test("letting a screen go over another swaps them, and the label says so", () => {
  const d = drafts({ 1: "a", 2: "b", 3: "c" });
  assert.deepEqual(plain(L.screenDropAction(d, "1", "2")), { kind: "swap", label: "Swap with screen 2" });
  assert.deepEqual(plain(L.screenDropAction(d, "3", "1")), { kind: "swap", label: "Swap with screen 1" });
});

test("over itself, outside the panes or onto a screen with no tree it does nothing", () => {
  const d = drafts({ 1: "a", 2: null });
  assert.deepEqual(plain(L.screenDropAction(d, "1", "1")), { kind: "none" });
  assert.deepEqual(plain(L.screenDropAction(d, "1", null)), { kind: "none" });
  assert.deepEqual(plain(L.screenDropAction(d, "1", "2")), { kind: "none" });
  assert.deepEqual(plain(L.screenDropAction(d, "2", "1")), { kind: "none" });
});

test("the pane under the pointer: each pane's width and half the gap either side", () => {
  // three panes of 100 (gaps of 10): 0..100, 110..210, 220..320
  const row = [{ x: 0, w: 100 }, { x: 110, w: 100 }, { x: 220, w: 100 }];
  assert.equal(L.paneAt(0, row, 10), 0);
  assert.equal(L.paneAt(104, row, 10), 0);
  assert.equal(L.paneAt(106, row, 10), 1);
  assert.equal(L.paneAt(214, row, 10), 1);
  assert.equal(L.paneAt(216, row, 10), 2);
  assert.equal(L.paneAt(319, row, 10), 2);
  assert.equal(L.paneAt(-1, row, 10), -1);
  assert.equal(L.paneAt(320, row, 10), -1);
  assert.equal(L.paneAt(5, [], 10), -1);
  // panes of their screens' sizes: 0..300 and 312..712
  assert.equal(L.paneAt(305, [{ x: 0, w: 300 }, { x: 312, w: 400 }], 12), 0);
  assert.equal(L.paneAt(307, [{ x: 0, w: 300 }, { x: 312, w: 400 }], 12), 1);
});

// --- the help row ---------------------------------------------------------------

const keys = (groups) => plain(groups).flat().map((item) => item.key + (item.enabled === false ? " (off)" : ""));

test("the help row offers p on a desk of more than one screen", () => {
  const node = tree("h[a, b]");
  assert.ok(keys(L.pictureHelp({ node, screens: 2, jumpKeys: "1–9" })).includes("p"));
  assert.ok(!keys(L.pictureHelp({ node, screens: 1, jumpKeys: "1–9" })).includes("p"));
  assert.ok(keys(L.pictureHelp({ node, screens: 2, readOnly: true, jumpKeys: "1–9" })).includes("p (off)"));
});
