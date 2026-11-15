// The Assignment view's mini-maps: each slot row's thumbnail of its
// workspace's tree on the slot's screen, the slot lit (Layout.miniMap,
// Layout.miniMapSize, Assignment.miniMapSource). The boxes are the Layout
// tab picture's own geometry (Layout.rects, Layout.filmstrip) at thumbnail
// size.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const L = load("Layout.js");
const A = load("Assignment.js");

const plain = (value) => JSON.parse(JSON.stringify(value));
const boxes = (map) => plain(map.tiles).map((t) => [t.key, t.x, t.y, t.w, t.h, t.selected]);

test("a tiled tree's mini-map is its tiles in proportion, the slot lit and the others not", () => {
  const map = plain(L.miniMap("h[main:2, v[right, side]]", "right", { w: 56, h: 32 }));
  assert.equal(map.kind, "tiles");
  assert.deepEqual(boxes(map), [
    ["main", 0, 0, 37, 32, false],
    ["right", 37, 0, 19, 16, true],
    ["side", 37, 16, 19, 16, false],
  ]);
});

test("a mini-map leaves out the place for other windows, as the Layout picture does without o", () => {
  assert.deepEqual(boxes(L.miniMap("h[main:3, *]", "main", { w: 56, h: 32 })), [["main", 0, 0, 56, 32, true]]);
});

test("a scroll tree's mini-map is a filmstrip: the screen half the box across, scrolled to the slot's column, a column's width of strip beside it", () => {
  // the screen 28 x 16 (the box's shape) in the middle of 56 x 32
  const right = plain(L.miniMap("scroll:0.5[left, main, right]", "right", { w: 56, h: 32 }));
  assert.equal(right.kind, "scroll");
  assert.deepEqual(right.screen, { x: 14, y: 8, w: 28, h: 16 });
  assert.deepEqual(right.tiles.map((t) => [t.key, t.x, t.y, t.w, t.h, t.selected, t.visible]), [
    ["left", 0, 8, 14, 16, false, 0],
    ["main", 14, 8, 14, 16, false, 1],
    ["right", 28, 8, 14, 16, true, 1],
  ]);
  const left = plain(L.miniMap("scroll[left, main]", "left", { w: 56, h: 32 }));
  assert.deepEqual(left.tiles.map((t) => [t.key, t.x, t.w, t.selected, t.visible]), [
    ["left", 14, 28, true, 1],
    ["main", 42, 28, false, 0],
  ], "full-width columns: one screen each, the next peeking in at the side");
});

test("a tiled tree's mini-map screen is the whole box", () => {
  assert.deepEqual(plain(L.miniMap("h[main, right]", "main", { w: 56, h: 32 }).screen), { x: 0, y: 0, w: 56, h: 32 });
});

test("no tree, or one that does not parse, draws no mini-map", () => {
  assert.deepEqual(plain(L.miniMap(null, "main", { w: 56, h: 32 })), { kind: "none", screen: null, tiles: [] });
  assert.deepEqual(plain(L.miniMap("h[main", "main", { w: 56, h: 32 })), { kind: "none", screen: null, tiles: [] });
});

test("a mini-map is the screen's shape, as large as fits its column's box", () => {
  assert.deepEqual(plain(L.miniMapSize(16 / 9, 56, 32)), { w: 56, h: 32 });
  assert.deepEqual(plain(L.miniMapSize(32 / 9, 56, 32)), { w: 56, h: 16 }, "an ultrawide: flatter");
  assert.deepEqual(plain(L.miniMapSize(4 / 3, 56, 32)), { w: 43, h: 32 }, "4:3: narrower");
  assert.deepEqual(plain(L.miniMapSize(0, 56, 32)), { w: 56, h: 32 }, "an unknown screen: 16:9");
});

// Layout dual (2 screens): workspace 3 has h[main:2, right] on screen 1 and
// left on screen 2.
function state() {
  return {
    layout: "dual",
    screens: ["HEADLESS-2", "HEADLESS-3"],
    slots: [{ name: "left" }, { name: "mail" }, { name: "main" }, { name: "right" }],
    layouts: { dual: { screens: 2, workspaces: {
      3: { 1: { tree: "h[main:2, right]", slots: ["main", "right"] }, 2: { tree: "left", slots: ["left"] } },
    } } },
  };
}

test("a slot's mini-map is its workspace's tree on the slot's screen only, with that screen's monitor", () => {
  assert.deepEqual(plain(A.miniMapSource(state(), 3, "right")), { screen: 1, tree: "h[main:2, right]", connector: "HEADLESS-2" });
  assert.deepEqual(plain(A.miniMapSource(state(), 3, "left")), { screen: 2, tree: "left", connector: "HEADLESS-3" });
});

test("a slot no tree of the workspace places has no mini-map", () => {
  assert.equal(A.miniMapSource(state(), 3, "mail"), null);
  assert.equal(A.miniMapSource(state(), 4, "main"), null, "a workspace with no trees");
  assert.equal(A.miniMapSource(null, 3, "main"), null);
});
