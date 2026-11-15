// Dragging a slot in the Layout picture (Layout.js): a tile or a filmstrip
// column pressed and moved, let go on a tile (its centre swaps the two, an
// edge band puts the dragged slot beside it on that side), between two
// columns of a filmstrip (reorders), or on another screen's pane (moves it
// there, as the keys' cross-screen move does). The tree operations are the
// keys' own: a drop where hjkl/HJKL would put the slot makes the same tree.
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
const drafts = (texts) => {
  const out = {};
  for (const [k, text] of Object.entries(texts)) out[k] = { node: text === null ? null : tree(text), base: text };
  return out;
};
const texts = (d) => Object.fromEntries(Object.entries(d).map(([k, v]) => [k, v.node ? L.format(v.node) : null]));
// one drop on screen 1's own tree: its text after, or the refusal
const dropped = (text, from, to, opts) => {
  const out = L.slotDrop(drafts({ 1: text }), { screen: "1", key: from }, Object.assign({ screen: "1" }, to), opts);
  return out.error ? { error: out.error } : L.format(out.drafts["1"].node);
};
const keyed = (text, fn) => {
  const out = fn(tree(text));
  assert.equal(out.error, undefined, out.error);
  return L.format(out.node);
};

// --- where on a tile ----------------------------------------------------------

test("a tile's middle is its centre; a band a quarter of the tile deep along each edge is that side", () => {
  const r = { x: 100, y: 50, w: 400, h: 200 };
  assert.equal(L.tileZone(r, 300, 150), "centre");
  assert.equal(L.tileZone(r, 101, 150), "left");
  assert.equal(L.tileZone(r, 199, 150), "left", "just inside the left quarter");
  assert.equal(L.tileZone(r, 201, 150), "centre", "just past it");
  assert.equal(L.tileZone(r, 499, 150), "right");
  assert.equal(L.tileZone(r, 300, 51), "up");
  assert.equal(L.tileZone(r, 300, 249), "down");
});

test("in a corner, where two bands meet, the nearer edge wins (as a share of the tile)", () => {
  const r = { x: 0, y: 0, w: 400, h: 200 };
  assert.equal(L.tileZone(r, 10, 40), "left", "2.5% from the left, 20% from the top");
  assert.equal(L.tileZone(r, 80, 5), "up", "20% from the left, 2.5% from the top");
});

test("the leaf under the pointer, never a container's box", () => {
  const rects = [
    { kind: "v", x: 0, y: 0, w: 100, h: 100 },
    { kind: "slot", key: "a", x: 0, y: 0, w: 100, h: 50 },
    { kind: "overflow", key: "*", x: 0, y: 50, w: 100, h: 50 },
  ];
  assert.equal(L.leafAt(rects, 10, 10).key, "a");
  assert.equal(L.leafAt(rects, 10, 60).key, "*");
  assert.equal(L.leafAt(rects, 150, 10), null);
});

test("the band an edge drop previews is the half of the tile on that side; the centre's the whole tile", () => {
  const r = { x: 10, y: 20, w: 100, h: 60 };
  assert.deepEqual(plain(L.zoneRect(r, "left")), { x: 10, y: 20, w: 50, h: 60 });
  assert.deepEqual(plain(L.zoneRect(r, "right")), { x: 60, y: 20, w: 50, h: 60 });
  assert.deepEqual(plain(L.zoneRect(r, "up")), { x: 10, y: 20, w: 100, h: 30 });
  assert.deepEqual(plain(L.zoneRect(r, "down")), { x: 10, y: 50, w: 100, h: 30 });
  assert.deepEqual(plain(L.zoneRect(r, "centre")), r);
});

// --- between filmstrip columns --------------------------------------------------

test("the gap of a filmstrip under the pointer: the boundary nearest it, 0 before the first column", () => {
  const columns = [{ x: 0, w: 100 }, { x: 100, w: 100 }, { x: 200, w: 100 }];
  assert.equal(L.stripGap(columns, -30), 0);
  assert.equal(L.stripGap(columns, 40), 0);
  assert.equal(L.stripGap(columns, 60), 1);
  assert.equal(L.stripGap(columns, 149), 1);
  assert.equal(L.stripGap(columns, 151), 2);
  assert.equal(L.stripGap(columns, 290), 3);
  assert.equal(L.stripGap([], 10), 0);
  assert.equal(L.stripGapX(columns, 0), 0);
  assert.equal(L.stripGapX(columns, 2), 200);
  assert.equal(L.stripGapX(columns, 3), 300);
});

// --- the centre: swap ------------------------------------------------------------

test("let go on a tile's centre, the two slots trade places, each keeping its share (×n) as h/l do", () => {
  assert.equal(dropped("h[main:2, right]", "right", { key: "main", zone: "centre" }), "h[right, main:2]");
  assert.equal(dropped("h[a, v[b, c]]", "a", { key: "c", zone: "centre" }), "h[c, v[b, a]]");
});

test("a centre drop on a neighbour is h/l's swap", () => {
  for (const [text, key, dir, other] of [
    ["h[a, b, c]", "b", "right", "c"], ["h[a, b, c]", "b", "left", "a"], ["v[a, b]", "a", "down", "b"],
    ["h[main:2, right]", "main", "right", "right"],
  ]) {
    assert.equal(dropped(text, key, { key: other, zone: "centre" }), keyed(text, (n) => L.move(n, key, dir)), `${text} ${key} ${dir}`);
  }
});

test("let go on its own tile, or where it already is, nothing changes", () => {
  const out = L.slotDrop(drafts({ 1: "h[a, b]" }), { screen: "1", key: "a" }, { screen: "1", key: "a", zone: "centre" });
  assert.equal(out.changed, false);
  assert.equal(L.slotDrop(drafts({ 1: "h[a, b]" }), { screen: "1", key: "a" }, { screen: "1", key: "b", zone: "left" }).changed, false);
  assert.equal(L.slotDropAction(drafts({ 1: "h[a, b]" }), { screen: "1", key: "a" }, { screen: "1", key: "b", zone: "left" }).kind, "none");
});

// --- an edge: beside it -----------------------------------------------------------

test("an edge along the target's split puts the slot beside it there, keeping its share", () => {
  assert.equal(dropped("h[a, b, c]", "a", { key: "c", zone: "left" }), "h[b, a, c]");
  assert.equal(dropped("h[a, b, c]", "a", { key: "c", zone: "right" }), "h[b, c, a]");
  assert.equal(dropped("h[a:2, b, c]", "a", { key: "c", zone: "right" }), "h[b, c, a:2]");
});

test("an edge across the target's split pairs them in a new split that way", () => {
  // a neighbour: the two take their shares into the pair (HJKL's pair)
  assert.equal(dropped("h[a, b, c]", "b", { key: "c", zone: "up" }), "h[a, v[b, c]:2]");
  assert.equal(dropped("h[a, b, c]", "b", { key: "c", zone: "down" }), "h[a, v[c, b]:2]");
  // from elsewhere: the target's tile is split in two
  assert.equal(dropped("h[a, v[b:3, c]]", "a", { key: "b", zone: "left" }), "v[h[a, b]:3, c]");
  assert.equal(dropped("v[h[a, b], c]", "c", { key: "a", zone: "down" }), "h[v[a, c], b]");
});

test("dropped across its own split's neighbour, the two are paired that way in place", () => {
  // b onto c's left edge, both in the right half's column: they stand side
  // by side in that half (the pair merged into the root split, a keeping
  // its half: 2 : 1 : 1)
  assert.equal(dropped("h[a, v[b, c]]", "b", { key: "c", zone: "left" }), "h[a:2, b, c]");
});

test("a tree of one tile beside which a slot lands becomes a split that way", () => {
  // the dragged slot's own split closes up first
  assert.equal(dropped("h[a, b]", "a", { key: "b", zone: "down" }), "v[b, a]");
  assert.equal(dropped("h[a, b]", "a", { key: "b", zone: "up" }), "v[a, b]");
});

test("an edge drop where HJKL would put the slot makes HJKL's tree", () => {
  const cases = [
    // along its split: paired with its neighbour across
    ["h[a, b, c]", "b", "right", { key: "c", zone: "up" }],
    ["h[a, b, c]", "b", "left", { key: "a", zone: "down" }],
    ["v[a, b, c]", "b", "down", { key: "c", zone: "left" }],
    ["h[a:2, b:3, c]", "b", "right", { key: "c", zone: "up" }],
    // across its split: out beside it
    ["h[a, v[b, c]]", "b", "left", { key: "a", zone: "right" }],
    ["h[a, v[b, c], d]", "c", "right", { key: "d", zone: "left" }],
    ["h[a, v[b:2, c]]", "b", "left", { key: "a", zone: "right" }],
    ["h[a, b]", "a", "down", { key: "b", zone: "down" }],
  ];
  for (const [text, key, dir, to] of cases) {
    assert.equal(dropped(text, key, to), keyed(text, (n) => L.forceMove(n, key, dir)), `${text} ${key} ${dir}`);
  }
});

test("other windows' place moves like a slot and is written into the tree as it goes", () => {
  // the engine's place for them without a * leaf: h[tree:3, *]
  // the engine's place for them without a * leaf, h[h[a, b]:3, *], written out: h[a:3, b:3, *:2]
  assert.equal(L.format(L.withOther(tree("h[a, b]"))), "h[a:3, b:3, *:2]");
  assert.equal(dropped("h[a, b]", "*", { key: "a", zone: "left" }), "h[*:2, a:3, b:3]");
  assert.equal(dropped("h[a, *]", "*", { key: "a", zone: "centre" }), "h[*, a]");
  assert.equal(dropped("h[a, b]", "a", { key: "*", zone: "up" }), "h[b:3, v[a:3, *:2]:5]");
});

// --- filmstrip columns -------------------------------------------------------------

test("a column let go between two others moves there, the order kept otherwise", () => {
  assert.equal(dropped("scroll:0.5[a, b, c, d]", "a", { gap: 3 }), "scroll:0.5[b, c, a, d]");
  assert.equal(dropped("scroll:0.5[a, b, c, d]", "d", { gap: 0 }), "scroll:0.5[d, a, b, c]");
  assert.equal(dropped("scroll[a, b, c]", "a", { gap: 3 }), "scroll[b, c, a]");
});

test("the gaps on either side of the column dragged change nothing", () => {
  for (const gap of [1, 2]) {
    const out = L.slotDrop(drafts({ 1: "scroll[a, b, c]" }), { screen: "1", key: "b" }, { screen: "1", gap });
    assert.equal(out.changed, false, "gap " + gap);
  }
});

test("a column moved one gap over is h/l's swap", () => {
  const text = "scroll:0.5[a, b, c]";
  assert.equal(dropped(text, "b", { gap: 3 }), keyed(text, (n) => L.move(n, "b", "right")));
  assert.equal(dropped(text, "b", { gap: 0 }), keyed(text, (n) => L.move(n, "b", "left")));
});

test("with other windows hidden, the gaps are the shown columns' and a trailing * stays last", () => {
  assert.equal(dropped("scroll[a, b, *]", "a", { gap: 2 }), "scroll[b, a, *]");
  assert.equal(dropped("scroll[a, b, *]", "a", { gap: 3 }, { showOther: true }), "scroll[b, *, a]");
});

// --- across screens ---------------------------------------------------------------

test("dropped on another screen's tile, the slot leaves its screen and lands there", () => {
  const out = L.slotDrop(drafts({ 1: "h[main:2, right]", 2: "v[side, chat]" }), { screen: "1", key: "right" },
    { screen: "2", key: "chat", zone: "right" });
  assert.equal(out.error, undefined);
  assert.deepEqual(texts(out.drafts), { 1: "main", 2: "v[side, h[chat, right]]" });
  assert.equal(out.screen, "2", "the selection goes with it");
  assert.equal(out.drafts["1"].base, "h[main:2, right]", "the bases stay the trees in force");
});

test("a centre drop on another screen's tile trades the two slots between the screens", () => {
  const out = L.slotDrop(drafts({ 1: "h[main, right]", 2: "v[side, chat]" }), { screen: "1", key: "right" },
    { screen: "2", key: "side", zone: "centre" });
  assert.deepEqual(texts(out.drafts), { 1: "h[main, side]", 2: "v[right, chat]" });
});

test("dropped at another screen's near edge it is the keys' move off the edge", () => {
  // l off screen 1's right edge: into screen 2's root split at its start
  const start = { 1: "h[main, right]", 2: "h[side, chat]" };
  const keys = L.crossMove(tree(start[1]), tree(start[2]), "right", "right");
  const out = L.slotDrop(drafts(start), { screen: "1", key: "right" }, { screen: "2", key: "side", zone: "left" });
  assert.deepEqual(texts(out.drafts), { 1: L.format(keys.source), 2: L.format(keys.target) });
  // and onto a filmstrip: its first gap
  const strip = { 1: "h[main, right]", 2: "scroll:0.5[side, chat]" };
  const keys2 = L.crossMove(tree(strip[1]), tree(strip[2]), "right", "right");
  const out2 = L.slotDrop(drafts(strip), { screen: "1", key: "right" }, { screen: "2", gap: 0 });
  assert.deepEqual(texts(out2.drafts), { 1: L.format(keys2.source), 2: L.format(keys2.target) });
  // h off screen 2's left edge: the last gap of screen 1's filmstrip
  const back = { 1: "scroll[a, b]", 2: "h[c, d]" };
  const keys3 = L.crossMove(tree(back[2]), tree(back[1]), "c", "left");
  const out3 = L.slotDrop(drafts(back), { screen: "2", key: "c" }, { screen: "1", gap: 2 });
  assert.deepEqual(texts(out3.drafts), { 1: L.format(keys3.target), 2: L.format(keys3.source) });
});

test("a screen with no tree takes the slot as its whole tree", () => {
  const out = L.slotDrop(drafts({ 1: "h[main, right]", 2: null }), { screen: "1", key: "right" }, { screen: "2" });
  assert.deepEqual(texts(out.drafts), { 1: "main", 2: "right" });
  assert.equal(L.slotDropAction(drafts({ 1: "h[main, right]", 2: null }), { screen: "1", key: "right" }, { screen: "2" }).label,
    "Put on screen 2");
});

test("refused across screens as by the keys: other windows' place, and a screen's only slot", () => {
  const d = drafts({ 1: "h[main, *]", 2: "v[side, chat]" });
  assert.match(L.slotDrop(d, { screen: "1", key: "*" }, { screen: "2", key: "side", zone: "left" }).error, /other windows stay on their screen/);
  assert.match(L.slotDrop(drafts({ 1: "main", 2: "side" }), { screen: "1", key: "main" }, { screen: "2", key: "side", zone: "left" }).error,
    /only window on this screen/);
  // a swap leaves it a tree: allowed
  assert.deepEqual(texts(L.slotDrop(drafts({ 1: "main", 2: "h[side, chat]" }), { screen: "1", key: "main" },
    { screen: "2", key: "side", zone: "centre" }).drafts), { 1: "side", 2: "h[main, chat]" });
  // nor does a swap take another screen's * away
  assert.match(L.slotDrop(drafts({ 1: "h[a, b]", 2: "h[c, *]" }), { screen: "1", key: "a" }, { screen: "2", key: "*", zone: "centre" }).error,
    /other windows stay on their screen/);
  const refused = L.slotDropAction(d, { screen: "1", key: "*" }, { screen: "2", key: "side", zone: "left" });
  assert.equal(refused.kind, "none");
  assert.match(refused.reason, /other windows stay/);
});

test("the drafts given are not changed", () => {
  const d = drafts({ 1: "h[main, right]", 2: "v[side, chat]" });
  L.slotDrop(d, { screen: "1", key: "right" }, { screen: "2", key: "chat", zone: "up" });
  L.slotDrop(d, { screen: "1", key: "right" }, { screen: "1", key: "main", zone: "centre" });
  assert.deepEqual(texts(d), { 1: "h[main, right]", 2: "v[side, chat]" });
});

// --- what letting go does, said by the ghost -----------------------------------------

test("the label says what letting go does", () => {
  const d = drafts({ 1: "h[main, right, left]", 2: "scroll[side, chat, mail]" });
  const at = (from, to) => L.slotDropAction(d, from, to);
  const one = (key) => ({ screen: "1", key });
  assert.deepEqual(plain(at(one("right"), { screen: "1", key: "main", zone: "centre" })), { kind: "swap", label: "Swap with main" });
  assert.equal(at(one("right"), { screen: "1", key: "main", zone: "left" }).label, "Put left of main");
  assert.equal(at(one("left"), { screen: "1", key: "main", zone: "right" }).label, "Put right of main");
  assert.equal(at(one("right"), { screen: "1", key: "main", zone: "up" }).label, "Put above main");
  assert.equal(at(one("right"), { screen: "1", key: "main", zone: "down" }).label, "Put below main");
  assert.equal(at(one("right"), { screen: "2", gap: 1 }).label, "Put between side and chat");
  assert.equal(at(one("right"), { screen: "2", gap: 0 }).label, "Put before side");
  assert.equal(at(one("right"), { screen: "2", gap: 3 }).label, "Put after mail");
  assert.equal(at({ screen: "2", key: "side" }, { screen: "2", gap: 3 }).label, "Put after mail");
  assert.equal(at(one("right"), { screen: "1", key: "main", zone: "up" }).kind, "insert");
  assert.equal(L.slotDropAction(drafts({ 1: "h[a, *]" }), one("a"), { screen: "1", key: "*", zone: "centre" }, { showOther: true }).label,
    "Swap with other windows");
});
