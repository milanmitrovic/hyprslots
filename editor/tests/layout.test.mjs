// The Layout view's tree editing (Layout.js): tree text and the ratio grammar
// as the engine reads them (tree.lua, ratio.lua), and the edits the view's
// keys make, after aerolayout's tree_visualizer.py.
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
// Text in, text out: parse, edit, format.
const edited = (text, fn) => {
  const result = fn(tree(text));
  assert.equal(result.error, undefined, result.error);
  return L.format(result.node);
};
const refused = (text, fn) => {
  const result = fn(tree(text));
  assert.equal(typeof result.error, "string", "expected a refusal, got " + JSON.stringify(plain(result)));
  return result.error;
};

// --- tree text --------------------------------------------------------------

test("tree text reads back as the engine writes it: weights of 1 left out", () => {
  for (const text of ["main", "*", "h[a, b:2, c]", "v[top, h[a:3, b:5]:2]", "scroll[x, y, z]", "scroll[main]",
    "h[main:2, v[right, *]]", "h", "a", "scroll"]) {
    assert.equal(L.format(tree(text)), text);
  }
  assert.equal(L.format(tree(" h[ a:1 ,b ] ")), "h[a, b]");
});

test("tree text the engine would refuse is refused, with its message", () => {
  const error = (text) => L.parse(text).error;
  assert.match(error("h[a, a]"), /slot 'a' appears twice/);
  assert.match(error("h[a, *, *]"), /more than one place for other windows/);
  assert.match(error("a[x, y]"),
    /a\[\.\.\.\] \(an accordion, a Hyprland group with tabs\) is gone: write scroll\[x, y\] for full-width scrolling columns at position 1/);
  assert.match(error("scroll[x, v[y, z]]"), /scroll\[\.\.\.\] holds slots only, found 'v\[' inside it/);
  assert.match(error("scroll[x, *, *]"), /more than one place for other windows '\*'/);
  assert.match(error("a[x, *]"), /a\[\.\.\.\] holds slots only, found '\*' inside it/);
  assert.match(error("scroll[x:2, y]"), /columns of scroll\[\.\.\.\] take no weight/);
  assert.match(error("h[scroll[x, y], d]"), /scroll\[\.\.\.\] is a whole screen's tree, found it inside a split at position 3/);
  assert.match(error("h[a:0, b]"), /a weight must be a positive integer, got '0'/);
  assert.match(error("h[a, b]:2"), /the root of a tree takes no weight/);
  assert.match(error("h[a, b"), /expected '\]', found end of text/);
  assert.match(error(""), /expected a slot name/);
});

test("the leaves of a tree in reading order, the overflow leaf as *", () => {
  assert.deepEqual(plain(L.leaves(tree("h[main:2, v[right, *], x]"))), ["main", "right", "*", "x"]);
  assert.deepEqual(plain(L.leaves(tree("scroll[x, y]"))), ["x", "y"]);
  assert.deepEqual(plain(L.leaves(tree("scroll[x, *, y]"))), ["x", "*", "y"]);
});

// --- the ratio grammar (ratio.lua) -----------------------------------------

test("the ratio of a tree: every split below the root, reduced, scroll columns as *", () => {
  assert.equal(L.ratio(tree("h[a, b, c]")), "1:1:1");
  assert.equal(L.ratio(tree("h[v[a, h[b, c]], d]")), "1[1:1[1:1]]:1");
  assert.equal(L.ratio(tree("h[v[a, b]:2, c]")), "2[1:1]:1");
  assert.equal(L.ratio(tree("h[a:2, b:4, c:2]")), "1:2:1");
  assert.equal(L.ratio(tree("scroll[x, y, z]")), "*:*:*");
  assert.equal(L.ratio(tree("main")), "");
});

test("a ratio sets both levels of a nested tree", () => {
  assert.equal(edited("h[v[left, main], right]", (n) => L.applyRatio(n, "2[1:2]:1")), "h[v[left, main:2]:2, right]");
  assert.equal(edited("h[v[a, b], v[c, d]]", (n) => L.applyRatio(n, "3[1:3]:1[3:1]")), "h[v[a, b:3]:3, v[c:3, d]]");
  assert.equal(edited("h[v[left, main:2]:2, right]", (n) => L.applyRatio(n, "5:1")), "h[v[left, main:2]:5, right]");
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, " 3 1 ")), "h[a:3, b]");
});

test("decimals become the smallest integer ratio, and common factors go", () => {
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, "1.5:1")), "h[a:3, b:2]");
  assert.equal(edited("h[a, b, c]", (n) => L.applyRatio(n, "0.25:0.25:0.5")), "h[a, b, c:2]");
  assert.equal(edited("h[a, b]", (n) => L.applyRatio(n, "1.37:1")), "h[a:137, b:100]");
  assert.equal(edited("h[a, b, c]", (n) => L.applyRatio(n, "2:4:2")), "h[a, b:2, c]");
});

test("scroll columns take * or 1 and change nothing; numbers on them are refused", () => {
  assert.equal(edited("scroll[x, y, z]", (n) => L.applyRatio(n, "*:1:*")), "scroll[x, y, z]");
  assert.match(refused("scroll[x, y]", (n) => L.applyRatio(n, "2:1")),
    /ratios don't apply to the outer container — it's a scroll branch, and each of its columns is full width/);
  assert.match(refused("h[a, b]", (n) => L.applyRatio(n, "*:1")),
    /\* is a scroll column with no share of its own, and the outer container is tiled/);
});

test("a ratio that does not fit the tree says where, as the engine does", () => {
  const H_WITH_V = "h[v[left, main], right]";
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "1:2:3")), /expected 2 values for the outer container, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2[1:2:3]:1")), /expected 2 values for cell 1, got 3/);
  assert.match(refused("h[v[a, h[b, c]], d]", (n) => L.applyRatio(n, "1[1:1[1:1:1]]:1")),
    /expected 2 values for cell 1 > cell 2, got 3/);
  assert.match(refused(H_WITH_V, (n) => L.applyRatio(n, "2:1[1:1]")), /right is a window, so it has nothing to split/);
  assert.match(refused("h[a, *]", (n) => L.applyRatio(n, "1:1[1:1]")), /the place for other windows is a window/);
  assert.match(refused("main", (n) => L.applyRatio(n, "1:1")), /the outer container is a window, not a split/);
  assert.match(refused("h[v[a], b]", (n) => L.applyRatio(n, "1[1:1]:1")), /expected 1 value for cell 1, got 2/);
});

test("ratio syntax errors, as ratio.lua words them", () => {
  const error = (text) => L.applyRatio(tree("h[a, b]"), text).error;
  assert.match(error("a:1"), /"a" is not a number/);
  assert.match(error("2[1:2"), /unclosed "\["/);
  assert.match(error("1:"), /stray ":"/);
  assert.match(error("1:2]"), /unexpected "\]"/);
  assert.match(error("1[]:2"), /expected a number, found "\]"/);
  assert.match(error("[1:2]:1"), /expected a number, found "\["/);
  assert.match(error(""), /the ratio is empty/);
  assert.match(error("0:1"), /ratios must be greater than zero/);
  assert.match(error("-1:1"), /ratios must be greater than zero/);
});

test("the ratio shown is one that can be typed back and changes nothing", () => {
  for (const [text, entry] of [["h[a, b, c]", null], ["h[a, b, c]", "1:2:1"], ["h[v[left, main], right]", "2[1:2]:1"],
    ["h[v[a, h[b, c]], d]", "2[1:3[1:2]]:1"], ["h[a, b, c]", "1:1.37:2.5"], ["v[top, h[a:3, b:5]:2]", null],
    ["scroll[x, y]", null]]) {
    let node = tree(text);
    if (entry) node = L.applyRatio(node, entry).node;
    const shown = L.ratio(node);
    const again = L.applyRatio(node, shown);
    assert.equal(again.error, undefined, again.error);
    assert.equal(L.ratio(again.node), shown);
    assert.equal(L.format(again.node), L.format(node), text + " at " + shown);
  }
});

test("clearing the ratios gives every split equal shares", () => {
  assert.equal(L.format(L.clearRatios(tree("h[v[a:3, b]:2, c:5]"))), "h[v[a, b], c]");
});

test("an edit never changes the tree it was given", () => {
  const node = tree("h[v[left, main], right]");
  L.applyRatio(node, "2[1:2]:1");
  assert.equal(L.format(node), "h[v[left, main], right]");
});

// --- selecting and moving (aerolayout's navigate_spatial, move_node,
// force_move_node, flip_tree, toggle_layout_mode) ----------------------------

test("arrows select the leaf that way, entering a container at its first leaf", () => {
  const t = tree("h[a, v[b, c], d]");
  assert.equal(L.navigate(t, "a", "right"), "b");
  assert.equal(L.navigate(t, "b", "down"), "c");
  assert.equal(L.navigate(t, "c", "up"), "b");
  assert.equal(L.navigate(t, "c", "right"), "d");
  assert.equal(L.navigate(t, "d", "left"), "b");
  assert.equal(L.navigate(t, "a", "left"), null);
  assert.equal(L.navigate(t, "a", "up"), null);
  // a scroll branch's columns sit side by side, in order
  const film = tree("scroll[p, q, r]");
  assert.equal(L.navigate(film, "p", "right"), "q");
  assert.equal(L.navigate(film, "r", "left"), "q");
  assert.equal(L.navigate(film, "q", "down"), null);
  assert.equal(L.navigate(tree("main"), "main", "right"), null);
});

test("h j k l swap a node with its neighbour along its container", () => {
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "left")), "h[b:2, a, c]");
  assert.equal(edited("h[a, b:2, c]", (n) => L.move(n, "b", "right")), "h[a, c, b:2]");
  assert.equal(edited("v[a, b]", (n) => L.move(n, "a", "down")), "v[b, a]");
  assert.equal(edited("scroll[x, y]", (n) => L.move(n, "x", "right")), "scroll[y, x]");
  assert.equal(edited("h[v[a, b], c]", (n) => L.move(n, "a", "right")), "h[v[a, b], c]", "across its container is no swap");
  assert.equal(L.move(tree("h[a, b]"), "a", "left").changed, false);
  assert.equal(L.move(tree("h[a, b]"), "a", "right").changed, true);
});

test("H J K L along the container pair a node with its neighbour across it", () => {
  assert.equal(edited("h[a, b, c]", (n) => L.forceMove(n, "b", "right")), "h[a, v[b, c]:2]");
  assert.equal(edited("h[a, b, c]", (n) => L.forceMove(n, "b", "left")), "h[v[a, b]:2, c]");
  // pairing c with the h above it merges into one row
  assert.equal(edited("v[h[a, b], c]", (n) => L.forceMove(n, "c", "up")), "h[a, b, c:2]");
  assert.equal(L.forceMove(tree("h[a, b]"), "b", "right").changed, false);
});

test("H J K L across the container move a node out of it, beside it", () => {
  assert.equal(edited("h[a, v[b, c]]", (n) => L.forceMove(n, "b", "left")), "h[a, b, c]");
  assert.equal(edited("h[a, v[b, c]:2]", (n) => L.forceMove(n, "c", "right")), "h[a, b:2, c]");
  assert.equal(edited("h[a, b]", (n) => L.forceMove(n, "a", "down")), "v[b, a]");
  assert.equal(edited("h[a, b]", (n) => L.forceMove(n, "a", "up")), "v[a, b]");

});

test("nothing pairs up or leaves a scroll branch: it holds slots only", () => {
  assert.match(refused("scroll[x, y]", (n) => L.forceMove(n, "x", "right")), /a scroll branch holds slots only/);
  assert.match(refused("scroll[x, y]", (n) => L.forceMove(n, "x", "down")), /a scroll branch holds slots only/);
});

test("/ flips every split of the tree, and leaves a scroll branch as it is", () => {
  assert.equal(L.format(L.flip(tree("h[m, v[b, c:2]]"))), "v[m, h[b, c:2]]");
  assert.equal(L.format(L.flip(tree("scroll[x, y]"))), "scroll[x, y]");
});

test("/ is for tiles: refused on a scroll tree, with nothing to say on tiles or no tree", () => {
  assert.equal(L.flipError(tree("scroll[x, y]")),
    "Flip is for tiles: a scroll tree's columns always stand in a row. t cycles to tiles.");
  assert.equal(L.flipError(tree("scroll:0.5[x, y]")),
    "Flip is for tiles: a scroll tree's columns always stand in a row. t cycles to tiles.");
  assert.equal(L.flipError(tree("h[m, v[b, c]]")), "");
  assert.equal(L.flipError(tree("m")), "");
  assert.equal(L.flipError(null), "");
});

// t three times: tiles, then scroll half, then scroll full, then tiles.
const cycled = (node, times) => {
  for (let i = 0; i < times; i++) {
    const r = L.cycleScroll(node);
    assert.equal(r.error, undefined, r.error);
    node = r.node;
  }
  return node;
};

test("t cycles tiles, scroll half, scroll full and back to the tiles it was made from", () => {
  const tiles = tree("h[a, v[b:2, c]:3]");
  assert.equal(L.format(cycled(tiles, 1)), "scroll:0.5[a, b, c]");
  assert.equal(L.format(cycled(tiles, 2)), "scroll[a, b, c]");
  assert.equal(L.format(cycled(tiles, 3)), "h[a, v[b:2, c]:3]");
  // the overflow leaf becomes the column windows with no slot take, in
  // reading order, and comes back with the tree
  const withOverflow = tree("h[a, v[*, b]]");
  assert.equal(L.format(cycled(withOverflow, 1)), "scroll:0.5[a, *, b]");
  assert.equal(L.format(cycled(withOverflow, 2)), "scroll[a, *, b]");
  assert.equal(L.format(cycled(withOverflow, 3)), "h[a, v[*, b]]");
  assert.equal(edited("main", (n) => L.cycleScroll(n)), "scroll:0.5[main]");
});

test("t on a scroll tree keeps its columns in their order", () => {
  const half = cycled(tree("h[a, v[b, c]]"), 1);
  const moved = L.move(half, "a", "right").node;
  assert.equal(L.format(moved), "scroll:0.5[b, a, c]");
  assert.equal(L.format(cycled(moved, 1)), "scroll[b, a, c]");
  // columns no longer as they were: back to tiles side by side, in their order
  assert.equal(L.format(cycled(moved, 2)), "h[b, a, c]");
  // read as text, there is no tree to go back to
  assert.equal(edited("scroll:0.5[x, y]", (n) => L.cycleScroll(n)), "scroll[x, y]");
  assert.equal(edited("scroll[x, y]", (n) => L.cycleScroll(n)), "h[x, y]");
  assert.equal(edited("scroll[x]", (n) => L.cycleScroll(n)), "x");
});

test("t on a scroll tree of any other width makes it full width", () => {
  assert.equal(edited("scroll:0.33[x, y]", (n) => L.cycleScroll(n)), "scroll[x, y]");
  assert.equal(edited("scroll:0.75[x, *]", (n) => L.cycleScroll(n)), "scroll[x, *]");
});

test("what a tree is, and what t makes of it, as the view words them", () => {
  assert.equal(L.scrollMode(tree("h[a, b]")), "tiles");
  assert.equal(L.scrollMode(tree("a")), "tiles");
  assert.equal(L.scrollMode(tree("scroll:0.5[a]")), "half");
  assert.equal(L.scrollMode(tree("scroll[a]")), "full");
  assert.equal(L.scrollMode(tree("scroll:0.33[a]")), "other");
  assert.equal(L.modeLabel(tree("h[a, b]")), "tiles");
  assert.equal(L.modeLabel(tree("scroll:0.5[a]")), "scroll · half");
  assert.equal(L.modeLabel(tree("scroll[a]")), "scroll · full");
  assert.equal(L.modeLabel(tree("scroll:0.33[a]")), "scroll · 33%");
  assert.equal(L.cycleLabel(tree("h[a, b]")), "scroll half");
  assert.equal(L.cycleLabel(tree("scroll:0.5[a]")), "scroll full");
  assert.equal(L.cycleLabel(tree("scroll[a]")), "tiles");
  assert.equal(L.cycleLabel(tree("scroll:0.33[a]")), "scroll full");
  assert.equal(L.cycleLabel(null), "scroll half");
});

test("t refuses a tree with no slot to scroll", () => {
  assert.match(refused("*", (n) => L.cycleScroll(n)), /nothing to scroll/);
});

// --- other windows (windows assigned to no slot): o shows or hides their place --

test("every tree has a place for other windows: its * leaf, else where the engine puts them", () => {
  // tree.with_overflow: h[tree:3, *:1]; a scroll branch: a column after its own
  assert.equal(L.format(L.withOther(tree("v[a, b]"))), "h[v[a, b]:3, *]");
  assert.equal(L.format(L.withOther(tree("h[a, b]"))), "h[a:3, b:3, *:2]");
  assert.equal(L.format(L.withOther(tree("main"))), "h[main:3, *]");
  assert.equal(L.format(L.withOther(tree("scroll[x, y]"))), "scroll[x, y, *]");
  assert.equal(L.format(L.withOther(tree("h[main:2, v[right, *]]"))), "h[main:2, v[right, *]]", "its own * as it is");
  assert.equal(L.format(L.withOther(tree("scroll[x, *, y]"))), "scroll[x, *, y]");
});

test("the picture shows that place only when o says so; the tree keeps it either way", () => {
  const own = tree("h[main:2, v[right, *]]");
  assert.equal(L.format(L.picture(own, false)), "h[main:2, right]");
  assert.equal(L.format(L.picture(own, true)), "h[main:2, v[right, *]]");
  assert.equal(L.format(own), "h[main:2, v[right, *]]", "the tree given is untouched");
  assert.equal(L.format(L.picture(tree("h[a, b]"), false)), "h[a, b]");
  assert.equal(L.format(L.picture(tree("h[a, b]"), true)), "h[a:3, b:3, *:2]");
  assert.equal(L.format(L.picture(tree("scroll[x, *, y]"), false)), "scroll[x, y]");
  assert.equal(L.format(L.picture(tree("scroll[x, y]"), true)), "scroll[x, y, *]");
  assert.equal(L.format(L.picture(tree("*"), false)), "*", "a tree that is only the place stays drawn");
  assert.equal(L.picture(null, true), null);
});

test("moving other windows' place writes it into the tree where it goes", () => {
  const moved = L.move(L.withOther(tree("h[a, b]")), "*", "left");
  assert.equal(L.format(moved.node), "h[a:3, *:2, b:3]");
  assert.equal(edited("scroll[x, y]", (n) => L.move(L.withOther(n), "*", "left")), "scroll[x, *, y]");
});

// --- moving a leaf to another screen of the workspace ----------------------------

test("a leaf moved off the edge of its screen joins the next screen's tree there", () => {
  let moved = L.crossMove(tree("h[a, b]"), tree("c"), "b", "right");
  assert.equal(L.format(moved.source), "a");
  assert.equal(L.format(moved.target), "h[b, c]");
  moved = L.crossMove(tree("v[c, d]"), tree("h[a, b]"), "c", "left");
  assert.equal(L.format(moved.source), "d");
  assert.equal(L.format(moved.target), "h[a, b, c]");
  moved = L.crossMove(tree("h[a, b]"), null, "a", "left");
  assert.equal(L.format(moved.target), "a");
});

test("a leaf moved onto a scroll branch becomes its column at the near edge, and one leaves its columns", () => {
  let moved = L.crossMove(tree("h[a, b]"), tree("scroll[c, d]"), "b", "right");
  assert.equal(L.format(moved.source), "a");
  assert.equal(L.format(moved.target), "scroll[b, c, d]");
  moved = L.crossMove(tree("scroll[c, d]"), tree("e"), "d", "right");
  assert.equal(L.format(moved.source), "scroll[c]");
  assert.equal(L.format(moved.target), "h[d, e]");
});

test("a screen keeps at least one leaf; other windows' place stays on its screen", () => {
  assert.match(L.crossMove(tree("c"), tree("h[a, b]"), "c", "left").error, /only window/);
  assert.match(L.crossMove(tree("h[a, *]"), tree("scroll[c]"), "*", "right").error, /other windows stay on their screen/);
  assert.match(L.crossMove(tree("h[a, *]"), tree("h[b, *]"), "*", "right").error, /other windows stay on their screen/);
});

// --- the mirror holds: the engine's own modules give the same answers -------

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const LUA = ["lua5.4", "lua5.5", "lua"].find((bin) => spawnSync(bin, ["-v"]).status === 0);

test("tree text and ratios read as tree.lua, serialize.lua and ratio.lua read them", { skip: !LUA && "no lua" }, () => {
  const cases = [
    ["h[a, b:2, c]", "1:1:1"], ["h[v[left, main], right]", "2[1:2]:1"], ["h[v[a, b], v[c, d]]", "3[1:3]:1[3:1]"],
    ["h[a, b]", "1.5:1"], ["h[a, b, c]", "0.25:0.25:0.5"], ["h[a, b]", "1.37:1"], ["scroll[x, y, z]", "*:1:*"],
    ["scroll[x, y]", "2:1"], ["h[a, b]", "*:1"], ["h[v[a, h[b, c]], d]", "1[1:1[1:1:1]]:1"], ["h[a, *]", "1:1[1:1]"],
    ["main", "1:1"], ["h[a, b]", "1:"], ["h[a, b]", "[1:2]:1"], ["h[a, b]", "2[1:2"], ["h[a, b]", "x:1"],
    ["h[a, b]", "0:1"], ["h[a, b]", ""], ["h[a, b]", " 3  1 "], ["v[top, h[a:3, b:5]:2]", "1:1[1:1]"],
    ["h[main:2, v[right, *]]", "1:2[3:1]"], ["h[a, a]", "1:1"], ["scroll[x, v[y]]", "1"], ["h[a:0, b]", "1"],
    ["h[a, b]:2", "1"], ["h[a, b", "1"], ["", "1"], ["h[a, *, *]", "1"], ["scroll[x:2, y]", "1"], ["h[a, b]", "1:2]"],
    ["a[x, y]", "1"], ["h[a[x, y], d]", "1"], ["h[scroll[x], y]", "1"], ["scroll[x, *]", "1"], ["scroll[main]", "1"],
    ["scroll[x, y]", "*[1]:*"], ["scroll[x, *, y]", "*:*:*"], ["scroll[*, x]", "1:1"], ["scroll[x, *, *]", "1"],
    ["scroll[x, *:2]", "1"], ["scroll[x, *]", "2:1"],
    ["scroll:0.5[x, y]", "*:*"], ["scroll:1[x]", "1"], ["scroll:1.0[x, *]", "*:1"], ["scroll:2[x]", "1"],
    ["scroll:x[a]", "1"], ["scroll:[a]", "1"], ["h[scroll:0.5[x], y]", "1"], ["h[scroll:2, b]", "1:1"],
    ["scroll : .5 [a, *]", "1:1"], ["scroll:0.33333[a]", "1"], ["scroll:0.05[a]", "1"], ["scroll:0.5[a]:2", "1"],
    ["scroll:0.25[a, v[b]]", "1"],
  ];
  const here = dirname(fileURLToPath(import.meta.url));
  const root = join(here, "..", "..");
  const script = `
package.path = "${root}/lua/?.lua;" .. package.path
local tree, ratio, serialize = require("hyprslots.tree"), require("hyprslots.ratio"), require("hyprslots.serialize")
for line in io.lines() do
  local text, entry = line:match("^(.-)\\t(.*)$")
  local node, err = tree.parse(text)
  if not node then
    print("tree error: " .. err)
  else
    local applied, aerr = ratio.apply(node, entry)
    print(serialize.tree(node) .. " | " .. ratio.format(node) .. " | "
      .. (applied and serialize.tree(applied) or ("error: " .. aerr)))
  end
end`;
  const run = spawnSync(LUA, ["-e", script], { input: cases.map((c) => c.join("\t")).join("\n") + "\n", encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const lua = run.stdout.trimEnd().split("\n");
  cases.forEach(([text, entry], i) => {
    const parsed = L.parse(text);
    let js;
    if (parsed.error) {
      js = "tree error: " + parsed.error;
    } else {
      const applied = L.applyRatio(parsed.node, entry);
      js = L.format(parsed.node) + " | " + L.ratio(parsed.node) + " | "
        + (applied.error ? "error: " + applied.error : L.format(applied.node));
    }
    assert.equal(js, lua[i], `${text} at ${JSON.stringify(entry)}`);
  });
});

test("appendSlots adds slots as the engine's tree.append does: root split children, or columns before a trailing *", () => {
  assert.equal(edited("h[a, b:2]", (n) => ({ node: L.appendSlots(n, ["x", "y"]) })), "h[a, b:2, x, y]");
  assert.equal(edited("v[a, h[b, c]]", (n) => ({ node: L.appendSlots(n, ["x"]) })), "v[a, h[b, c], x]");
  assert.equal(edited("main", (n) => ({ node: L.appendSlots(n, ["x"]) })), "h[main, x]");
  assert.equal(edited("scroll:0.5[a, *]", (n) => ({ node: L.appendSlots(n, ["x"]) })), "scroll:0.5[a, x, *]");
  assert.equal(edited("scroll[*, a]", (n) => ({ node: L.appendSlots(n, ["x"]) })), "scroll[*, a, x]");
  assert.equal(edited("h[a, *]", (n) => ({ node: L.appendSlots(n, ["x"]) })), "h[a, *, x]");
  assert.equal(edited("h[a, b]", (n) => ({ node: L.appendSlots(n, []) })), "h[a, b]");
  const given = tree("h[a, b]");
  L.appendSlots(given, ["x"]);
  assert.equal(L.format(given), "h[a, b]", "the tree given is untouched");
});

test("appendSlots gives what tree.append gives", { skip: !LUA && "no lua" }, () => {
  const cases = [["h[a, b:2]", "x,y"], ["v[a, h[b, c]]", "x"], ["main", "x"], ["*", "x"], ["scroll:0.5[a, *]", "x,y"],
    ["scroll[*, a]", "x"], ["scroll[a]", "x"], ["h[a, *]", "x"], ["h[a:3, v[b, c]:2]", "x"], ["h[a, b]", ""]];
  const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  const script = `
package.path = "${root}/lua/?.lua;" .. package.path
local tree, serialize = require("hyprslots.tree"), require("hyprslots.serialize")
for line in io.lines() do
  local text, list = line:match("^(.-)\\t(.*)$")
  local slots = {}
  for s in list:gmatch("[^,]+") do slots[#slots + 1] = s end
  print(serialize.tree(tree.append(assert(tree.parse(text)), slots)))
end`;
  const run = spawnSync(LUA, ["-e", script], { input: cases.map((c) => c.join("\t")).join("\n") + "\n", encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  const lua = run.stdout.trimEnd().split("\n");
  cases.forEach(([text, list], i) => {
    assert.equal(L.format(L.appendSlots(tree(text), list ? list.split(",") : [])), lua[i], `${text} + ${list}`);
  });
});

// --- the view's model: which trees, drawn how --------------------------------

// Desk "docked" (eDP-1 left, DP-2 right) uses layout "dual", which office
// shares; dual has default trees (screen 1: main) and workspaces 3 and 4 of
// its own; workspace 5 shows the default trees.
function fixture() {
  return {
    ok: true,
    desk: "docked",
    layout: "dual",
    dirty: false,
    used_workspaces: [3, 4],
    screens: ["eDP-1", "DP-2"],
    monitors: [
      { name: "DP-2", description: "Samsung G95NC", width: 5120, height: 1440 },
      { name: "eDP-1", description: "BOE 0x0BCA", width: 1920, height: 1200 },
    ],
    workspaces: { 3: { workspace: 3, screen: 1 }, 13: { workspace: 3, screen: 2 }, 4: { workspace: 4, screen: 1 } },
    desks: { docked: { monitors: ["eDP-1", "Samsung G95NC"], layout: "dual", active: true },
      office: { monitors: ["eDP-1", "Dell"], layout: "dual", active: false } },
    layouts: {
      dual: {
        screens: 2, active: true, read_only: false, used_by: ["docked", "office"], own: [3, 4],
        default: { 1: { tree: "main", ratio: "", slots: ["main"] } },
        workspaces: {
          3: { 1: { tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", slots: ["main", "right"], resized: true },
            2: { tree: "left", ratio: "", slots: ["left"] } },
          4: { 1: { tree: "mail", ratio: "", slots: ["mail"] } },
          5: { 1: { tree: "main", ratio: "", slots: ["main"] } },
        },
      },
      single: { screens: 1, active: false, read_only: true, used_by: [], own: [], default: {}, workspaces: {} },
    },
    windows: [
      { address: "0xa", class: "t-main", title: "editor", workspace_id: 3, workspace: 3, slot: "main" },
      { address: "0xb", class: "t-left", title: "notes", workspace_id: 13, workspace: 3, slot: "left" },
    ],
    config: { editable: true, read_only: ["layouts.single"] },
  };
}

test("a workspace shows one pane per screen of the layout, with the tree it shows", () => {
  assert.deepEqual(plain(L.panes(fixture(), "dual", 3)), [
    { screen: 1, key: "1", tree: "h[main:2, v[right, *]]", ratio: "2:1[1:1]", resized: true, connector: "eDP-1" },
    { screen: 2, key: "2", tree: "left", ratio: "", resized: false, connector: "DP-2" },
  ]);
  assert.deepEqual(plain(L.panes(fixture(), "dual", 4))[1], { screen: 2, key: "2", tree: null, ratio: "", resized: false,
    connector: "DP-2" });
  assert.deepEqual(plain(L.panes(fixture(), "nope", 3)), []);
});

test("the default trees are a workspace of their own to the panes", () => {
  assert.deepEqual(plain(L.panes(fixture(), "dual", "default")).map((p) => [p.screen, p.tree]), [[1, "main"], [2, null]]);
});

test("a pane is labelled with the display name of the active desk's monitor at its position", () => {
  const state = fixture();
  state.monitors[0].display = "Samsung";
  state.monitors[1].display = "Built-in";
  assert.equal(L.screenLabel(state, 1), "Screen 1 · Built-in");
  assert.equal(L.screenLabel(state, 2), "Screen 2 · Samsung");
  assert.equal(L.screenLabel(fixture(), 1), "Screen 1 · eDP-1", "an engine of before: the connector");
  assert.equal(L.screenLabel(fixture(), 3), "Screen 3");
  assert.equal(L.screenLabel(null, 1), "Screen 1");
});

test("a workspace on the shared trees says it uses them, and whom its edits are for once asked", () => {
  assert.equal(L.defaultNote(fixture(), "dual", 5), "(uses the shared tree)");
  assert.equal(L.defaultNote(fixture(), "dual", 7), "(uses the shared tree)", "the shared tree may be empty");
  assert.equal(L.defaultNote(fixture(), "dual", 5, "all"), "(uses the shared tree: editing it for all workspaces)");
  assert.equal(L.defaultNote(fixture(), "dual", 5, "only"), "(uses the shared tree: w gives workspace 5 its own)");
  assert.equal(L.defaultNote(fixture(), "dual", 3), "", "trees of its own");
  assert.equal(L.defaultNote(fixture(), "dual", "default"), "");
});

test("a workspace has trees of its own, or uses the shared ones", () => {
  assert.equal(L.hasOwn(fixture(), "dual", 3), true);
  assert.equal(L.hasOwn(fixture(), "dual", 5), false);
  assert.equal(L.hasOwn(fixture(), "dual", "default"), false);
  assert.equal(L.hasOwn(null, "dual", 3), false);
});

test("the first edit of a workspace on the shared trees asks whom it is for", () => {
  assert.equal(L.needsScope(fixture(), "dual", 5, ""), true);
  assert.equal(L.needsScope(fixture(), "dual", 5, "all"), false, "asked already");
  assert.equal(L.needsScope(fixture(), "dual", 5, "only"), false);
  assert.equal(L.needsScope(fixture(), "dual", 3, ""), false, "its own trees");
  assert.equal(L.needsScope(fixture(), "dual", "default", ""), false, "All workspaces edits the shared trees");
  const P = load("Prompts.js");
  const scope = L.scopeQuestion(5);
  const prompt = P.choice(scope.label, scope.options, { inline: true });
  assert.equal(P.display(prompt), "Apply to (a)ll workspaces or (o)nly workspace 5? [Esc] cancel");
  assert.deepEqual(plain(P.key(prompt, "", "a").result), { value: "all" });
  assert.deepEqual(plain(P.key(prompt, "", "o").result), { value: "only" });
  assert.equal(P.key(prompt, "", "x").result, null);
});

test("an edit goes to the shared trees for all workspaces, else to the workspace", () => {
  assert.equal(L.editTarget(5, "all"), "default");
  assert.equal(L.editTarget(5, "only"), 5);
  assert.equal(L.editTarget(3, ""), 3);
  assert.equal(L.editTarget("default", ""), "default");
});

test("the view opens at the focused workspace's number and screen", () => {
  assert.deepEqual(plain(L.initialTarget(fixture(), 13)), { workspace: 3, screen: 2 });
  assert.deepEqual(plain(L.initialTarget(fixture(), 1)), { workspace: 3, screen: 1 }, "an unknown id: the first used workspace");
  const none = fixture();
  none.used_workspaces = [];
  assert.deepEqual(plain(L.initialTarget(none, 1)), { workspace: 1, screen: 1 });
});

test("what may not be edited says why", () => {
  assert.equal(L.editBlock(fixture(), "dual"), "");
  assert.equal(L.editBlock(fixture(), "single"), "layout 'single' is set by code in your config; edit it there");
  const noData = fixture();
  noData.config.editable = false;
  assert.equal(L.editBlock(noData, "dual"), "your config loads no editor data, so there is nothing the editor may change");
  const off = fixture();
  off.refused = "hyprmoncfg's workspace planner is on";
  assert.match(L.editBlock(off, "dual"), /hyprslots is off: hyprmoncfg/);
  assert.match(L.editBlock(null, "dual"), /no state/);
  assert.match(L.editBlock(fixture(), ""), /no desk is active/);
});

test("the slot -> window title map for a pane: what sits in each slot on that screen", () => {
  assert.deepEqual(plain(L.titles(fixture(), 3, 1)), { main: "editor" });
  assert.deepEqual(plain(L.titles(fixture(), 3, 2)), { left: "notes" });
});

test("boxes are proportional to the weights, the remainder to the last child", () => {
  const rects = plain(L.rects(tree("h[a:2, b]"), { x: 0, y: 0, w: 301, h: 100 }, { pad: 0 }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key, r.x, r.y, r.w, r.h, r.label]), [
    ["slot", "a", 0, 0, 200, 100, "a ×2"],
    ["slot", "b", 200, 0, 101, 100, "b"],
  ]);
});

test("a nested container is drawn as a titled box, its children inside it", () => {
  const rects = plain(L.rects(tree("h[main:2, v[right, *]]"), { x: 0, y: 0, w: 300, h: 100 }, { pad: 4, title: 10 }));
  assert.deepEqual(rects.map((r) => [r.kind, r.key || "", r.x, r.y, r.w, r.h, r.label, r.depth]), [
    ["slot", "main", 0, 0, 200, 100, "main ×2", 1],
    ["v", "", 200, 0, 100, 100, "v 1:1", 1],
    ["slot", "right", 204, 14, 92, 41, "right", 2],
    ["overflow", "*", 204, 55, 92, 41, "other windows", 2],
  ]);
});

// A pane 1800 x 300 for a 2:1 screen, three screen widths across it: the
// screen (the viewport) is 600 x 300 in the middle, a screen's width of the
// strip on each side of it.
const PANE = { x: 0, y: 0, w: 1800, h: 300 };
const film = (text, opts) => plain(L.filmstrip(tree(text), PANE, Object.assign({ aspect: 2, span: 3 }, opts)));
const columns = (strip) => strip.columns.map((c) => [c.key, c.x, c.w, c.visible, !!c.selected]);

test("a scroll tree is a filmstrip: columns of the screen's width in slot order, the screen a viewport over them", () => {
  const strip = film("scroll[a, b]", { selected: "a" });
  assert.deepEqual(strip.viewport, { x: 600, y: 0, w: 600, h: 300 });
  assert.deepEqual(columns(strip), [["a", 600, 600, 1, true], ["b", 1200, 600, 0, false]]);
  assert.equal(strip.label, "scroll · full");
  assert.deepEqual([strip.columns[0].y, strip.columns[0].h], [0, 300]);
});

test("half-width columns take half the screen each, two to a screen", () => {
  const strip = film("scroll:0.5[a, b, c]", { selected: "a" });
  assert.deepEqual(columns(strip), [["a", 600, 300, 1, true], ["b", 900, 300, 1, false], ["c", 1200, 300, 0, false]]);
  assert.equal(strip.label, "scroll · half");
});

test("the selected column is scrolled into the screen, the least that shows it", () => {
  assert.deepEqual(columns(film("scroll:0.5[a, b, c, d]", { selected: "c" })),
    [["a", 300, 300, 0, false], ["b", 600, 300, 1, false], ["c", 900, 300, 1, true], ["d", 1200, 300, 0, false]]);
  assert.deepEqual(columns(film("scroll[a, b, c]", { selected: "b" })),
    [["a", 0, 600, 0, false], ["b", 600, 600, 1, true], ["c", 1200, 600, 0, false]]);
  assert.deepEqual(columns(film("scroll[a, b, c]", { selected: "" })).map((c) => c[1]), [600, 1200, 1800],
    "nothing selected: the strip starts at the screen's left edge");
});

test("a column partly on the screen says how much of it shows", () => {
  const strip = film("scroll:0.4[a, b, c]", { selected: "a" });
  assert.deepEqual(columns(strip), [["a", 600, 240, 1, true], ["b", 840, 240, 1, false], ["c", 1080, 240, 0.5, false]]);
  assert.equal(strip.label, "scroll · 40%");
});

test("filmstrip columns are labelled as slots are: name and window title; other windows' column where it stands", () => {
  const strip = film("scroll:0.5[main, *, right]", { selected: "*", titles: { main: "editor" } });
  assert.deepEqual(strip.columns.map((c) => [c.kind, c.key, c.label, c.title || ""]),
    [["slot", "main", "main", "editor"], ["overflow", "*", "other windows", ""], ["slot", "right", "right", ""]]);
});

test("three screen widths across: the screen is a third of a tall pane's width, centred", () => {
  const strip = plain(L.filmstrip(tree("scroll[a]"), { x: 10, y: 20, w: 900, h: 400 }, { aspect: 16 / 9, span: 3 }));
  assert.deepEqual(strip.viewport, { x: 310, y: 136, w: 300, h: 168 });
});

test("the screen fits the pane's height when the pane is wide", () => {
  const strip = plain(L.filmstrip(tree("scroll[a]"), { x: 10, y: 20, w: 1000, h: 100 }, { aspect: 2, span: 3 }));
  assert.deepEqual(strip.viewport, { x: 410, y: 20, w: 200, h: 100 });
});

test("the ratio prompt names the current ratio, and refuses a tree with nothing to divide", () => {
  assert.equal(L.ratioPrompt(tree("h[main:2, v[right, *]]")).text,
    "Ratios for the whole tree (current 2:1[1:1]; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.equal(L.ratioPrompt(tree("h[a, b]")).text,
    "Ratios for the whole tree (current 1:1; empty clears all) [Enter] set  [Esc] cancel: ");
  assert.match(L.ratioPrompt(tree("main")).error, /Nothing to divide/);
  assert.equal(L.ratioPrompt(tree("scroll[x, y]")).error,
    "Ratios are for tiles: each column of a scroll tree is a set width of the screen (full here). t cycles to tiles.");
  assert.equal(L.ratioPrompt(tree("scroll:0.5[x, y]")).error,
    "Ratios are for tiles: each column of a scroll tree is a set width of the screen (half here). t cycles to tiles.");
});

// --- drafts follow the slot list (global slots) -----------------------------

test("a deleted slot leaves a draft tidied; the last leaf leaves no tree; other windows keep their place", () => {
  assert.equal(edited("h[a, v[b, c]:2]", (n) => L.removeSlot(n, "b")), "h[a, c:2]");
  assert.equal(edited("scroll[a, b]", (n) => L.removeSlot(n, "a")), "scroll[b]");
  assert.equal(L.removeSlot(tree("a"), "a").node, null);
  assert.match(refused("h[a, *]", (n) => L.removeSlot(n, "*")), /other windows always have a place/);
});

test("an edited draft follows a new slot onto the screen whose tree in force has it now", () => {
  const drafts = {
    1: { node: tree("h[b, a]"), base: "h[a, b]" }, // edited
    2: { node: tree("c"), base: "c" }, // not edited: it takes the engine's tree on the re-read
    3: { node: null, base: null },
  };
  const panes = [{ key: "1", tree: "h[a, b, notes]" }, { key: "2", tree: "c" }, { key: "3", tree: null }];
  const out = L.followNewSlot(drafts, panes, "notes");
  assert.equal(L.format(out[1].node), "h[b, a, notes]");
  assert.equal(out[1].base, "h[a, b]", "still edited against what it started from");
  assert.equal(out[2], drafts[2]);
  assert.equal(out[3], drafts[3]);
  assert.equal(L.format(drafts[1].node), "h[b, a]", "the drafts given are untouched");
  const scroll = { 1: { node: tree("scroll:0.5[b, a, *]"), base: "scroll:0.5[a, b, *]" } };
  assert.equal(L.format(L.followNewSlot(scroll, [{ key: "1", tree: "scroll:0.5[a, b, notes, *]" }], "notes")[1].node),
    "scroll:0.5[b, a, notes, *]");
  const has = { 1: { node: tree("h[notes, a]"), base: "h[a]" } };
  assert.equal(L.format(L.followNewSlot(has, [{ key: "1", tree: "h[a, notes]" }], "notes")[1].node), "h[notes, a]",
    "a draft that has it already keeps it where it is");
});

test("the screen whose draft places a slot, null when no screen of the workspace does", () => {
  const drafts = { 1: { node: tree("h[main, right]") }, 2: { node: null }, 3: { node: tree("left") } };
  assert.equal(L.placedIn(drafts, "right"), "1");
  assert.equal(L.placedIn(drafts, "left"), "3");
  assert.equal(L.placedIn(drafts, "notes"), null);
  assert.equal(L.placedIn(drafts, "*"), null);
});

test("a slot renamed in a draft keeps its place and weight", () => {
  assert.equal(edited("h[main:2, v[right, *]]", (n) => ({ node: L.renameSlot(n, "right", "aside") })), "h[main:2, v[aside, *]]");
  assert.equal(edited("scroll[a, b]", (n) => ({ node: L.renameSlot(n, "a", "x") })), "scroll[x, b]");
  assert.equal(edited("main", (n) => ({ node: L.renameSlot(n, "other", "x") })), "main");
});

// --- the help row: one line at the panel's width ----------------------------

const H = load("Help.js");
// The row as it reads on screen: StyledText collapses runs of spaces.
const helpLine = (groups) => H.plain(H.row(groups, "#fff")).replace(/\s+/g, " ");
// What fits on one line of the panel (1100 px wide, its 11 px font).
const ONE_LINE = 150;

test("the picture's help row: no add, take out or fork; d reverts; t says what it makes next", () => {
  const line = helpLine(L.pictureHelp({ node: tree("h[a, b]"), hasOwn: true, jumpKeys: "1–9 0" }));
  assert.equal(line, "←↑↓→ select hjkl/HJKL move / flip t scroll half ratios other windows · w apply d revert Record "
    + "use shared · slots · [ ] 1–9 0 - workspace · Tab view");
  assert.ok(line.length <= ONE_LINE, `${line.length} characters: ${line}`);
  assert.doesNotMatch(line, /add|take out|fork|\.lua/);
});

test("/ flip and r ratios show on tiles only; t names the next of tiles, scroll half, scroll full", () => {
  const half = helpLine(L.pictureHelp({ node: tree("scroll:0.5[a, b]"), hasOwn: false, jumpKeys: "1–9" }));
  assert.equal(half, "←↑↓→ select hjkl/HJKL move t scroll full other windows · w apply d revert Record · slots · "
    + "[ ] 1–9 - workspace · Tab view");
  const full = helpLine(L.pictureHelp({ node: tree("scroll[a, b]"), hasOwn: false, jumpKeys: "1–9" }));
  assert.match(full, / t tiles /);
  assert.doesNotMatch(full, /flip|ratios/);
  assert.match(helpLine(L.pictureHelp({ node: null, hasOwn: false, jumpKeys: "1–9" })), / \/ flip t scroll half ratios /);
});

test("the trigger keys are highlighted in the help row", () => {
  const styled = H.row(L.pictureHelp({ node: tree("h[a, b]"), hasOwn: true, jumpKeys: "1–9" }), "#fff");
  const k = (key) => `<b><font color="#fff">${key}</font></b>`;
  for (const part of [k("t") + " scroll half", k("r") + "atios", k("o") + "ther windows", k("d") + " revert",
    k("R") + "ecord", k("u") + "se shared", k("s") + "lots", k("hjkl/HJKL") + " move", k("[ ] 1–9 -") + " workspace"]) {
    assert.ok(styled.includes(part), `${part} in ${styled}`);
  }
});

test("the slot list's help row: add, rename, describe, delete, Return shows it in the picture, one line", () => {
  const line = helpLine(L.slotListHelp({ jumpKeys: "1–9 0" }));
  assert.equal(line, "↑/↓ select add rename describe delete Return show in the picture · s/Esc back · [ ] 1–9 0 - workspace · Tab view");
  assert.ok(line.length <= ONE_LINE);
});

test("d reverts a tree to how it was last saved, asking first, in words with no file names", () => {
  assert.equal(L.revertQuestion(3, "1"), "Revert workspace 3's tree on screen 1 to how it was last saved? Its unsaved edits go.");
  assert.equal(L.revertQuestion("default", "2"),
    "Revert the shared tree on screen 2 to how it was last saved? Its unsaved edits go.");
  assert.equal(L.revertedText(3, "1", "h[a, b]"), "Reverted workspace 3's tree on screen 1: h[a, b].");
  assert.equal(L.revertedText("default", "1", null), "Reverted the shared tree on screen 1: no tree.");
});
