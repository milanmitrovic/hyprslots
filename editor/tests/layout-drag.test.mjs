// The Layout picture's dividers (Layout.js): every boundary between two
// children of a tiled split, dragged by mouse; the whole split snaps to an
// arrangement of whole weights 1 to 5.
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

// --- where the dividers are --------------------------------------------------

test("a split's boundary is a divider along it, spanning the two children it parts", () => {
  const list = plain(L.dividers(tree("h[main:2, right]"), { x: 0, y: 0, w: 300, h: 100 }, {}));
  assert.deepEqual(list, [{ id: "main|right", axis: "h", x: 200, y: 0, length: 100, at: 200, start: 0, end: 300,
    before: ["main"], after: ["right"], split: ["main", "right"], depth: 1 }]);
});

test("a nested split's dividers sit inside its box, past its padding and title", () => {
  const list = plain(L.dividers(tree("h[main:2, v[right, side:3]]"), { x: 0, y: 0, w: 300, h: 200 }, { pad: 5, title: 10 }));
  assert.deepEqual(list.map((d) => [d.id, d.axis, d.x, d.y, d.length, d.at, d.start, d.end, d.depth]), [
    ["main|right", "h", 200, 0, 200, 200, 0, 300, 1],
    // the v box is x 200..300; its children 205..295, from y 15 to 195
    ["right|side", "v", 205, 60, 90, 60, 15, 195, 2],
  ]);
  assert.deepEqual(list[0].after, ["right", "side"], "the v split is one neighbour");
});

test("a split of three has a divider between each two neighbours", () => {
  const list = plain(L.dividers(tree("v[a, b, c]"), { x: 0, y: 0, w: 90, h: 300 }, {}));
  assert.deepEqual(list.map((d) => [d.id, d.at, d.start, d.end]), [["a|b", 100, 0, 200], ["b|c", 200, 100, 300]]);
});

test("a scroll tree and a single window have no dividers", () => {
  assert.deepEqual(plain(L.dividers(tree("scroll[a, b]"), { x: 0, y: 0, w: 300, h: 100 }, {})), []);
  assert.deepEqual(plain(L.dividers(tree("main"), { x: 0, y: 0, w: 300, h: 100 }, {})), []);
});

test("the pointer is on a divider within `slop` pixels of it, along its length; the nearest wins", () => {
  const list = L.dividers(tree("h[main:2, v[right, side:3]]"), { x: 0, y: 0, w: 300, h: 200 }, { pad: 5, title: 10 });
  const at = (x, y) => {
    const hit = L.dividerAt(list, x, y, 5);
    return hit ? hit.id : null;
  };
  assert.equal(at(200, 100), "main|right");
  assert.equal(at(196, 10), "main|right", "4 px off is on it");
  assert.equal(at(194, 10), null, "6 px off is not");
  assert.equal(at(200, 205), null, "past its end is not");
  assert.equal(at(250, 62), "right|side");
  assert.equal(at(203, 60), "main|right", "nearer the outer one than the inner one");
  assert.equal(at(207, 60), "right|side");
  assert.equal(at(100, 100), null);
});

test("a divider's fraction is where the pointer is between the two neighbours' far edges, 0 to 1", () => {
  const [d] = L.dividers(tree("h[main:2, right]"), { x: 0, y: 0, w: 300, h: 100 }, {});
  assert.equal(L.dividerFraction(d, 150), 0.5);
  assert.equal(L.dividerFraction(d, 75), 0.25);
  assert.equal(L.dividerFraction(d, -20), 0);
  assert.equal(L.dividerFraction(d, 999), 1);
});

// --- dragging one: the whole split snaps to an allowed arrangement ----------

// Drag the divider `id` of the picture of `text` (o: other windows shown
// when `showOther`) to `fraction` of its two neighbours: the draft's text,
// and the split's ratio as the label near the pointer says it. The draft is
// the one the drag started on, as the pane passes it on every move.
const AREA = { x: 0, y: 0, w: 1200, h: 600 };
function drag(text, id, fraction, showOther) {
  const draft = tree(text);
  const list = L.dividers(L.picture(draft, !!showOther), AREA, { pad: 5, title: 10 });
  const divider = list.find((d) => d.id === id);
  assert.ok(divider, `no divider ${id} in ${list.map((d) => d.id)}`);
  const result = L.dragDivider(draft, divider, fraction);
  assert.equal(result.error, undefined, result.error);
  assert.equal(L.format(draft), text, "the tree given is untouched");
  return { text: L.format(result.node), label: result.label, changed: result.changed };
}

test("the allowed arrangements: every child a whole 1 to 5, divided by their gcd", () => {
  assert.equal(L.arrangements(2).length, 19);
  assert.equal(L.arrangements(3).length, 115);
  assert.equal(L.arrangements(4).length, 607);
  const two = plain(L.arrangements(2)).map((t) => t.join(":"));
  assert.ok(two.includes("5:1") && two.includes("2:3") && !two.includes("2:2") && !two.includes("6:1"));
  // with five children 1 : 5 : 5 : 5 : 5 would leave the first under 5%
  const five = plain(L.arrangements(5));
  assert.ok(five.length > 0);
  assert.ok(five.every((t) => t.every((w) => 20 * w >= t.reduce((a, b) => a + b, 0))), "none below 5%");
  assert.ok(!five.some((t) => t.join(":") === "1:5:5:5:5"));
  assert.ok(five.some((t) => t.join(":") === "1:4:5:5:5"), "1/20 is still allowed");
});

test("dragged to the middle, h[main:2, right] becomes h[main, right]", () => {
  assert.deepEqual(drag("h[main:2, right]", "main|right", 0.5), { text: "h[main, right]", label: "1 : 1", changed: true });
});

test("the nearest allowed ratio within 3% wins", () => {
  assert.equal(drag("h[main:2, right]", "main|right", 0.52).text, "h[main, right]");
  assert.equal(drag("h[main, right]", "main|right", 0.65).text, "h[main:2, right]", "2/3 is 0.667");
  assert.equal(drag("h[main, right]", "main|right", 0.41).text, "h[main:2, right:3]", "2/5");
  assert.equal(drag("h[main, right]", "main|right", 0.75).text, "h[main:3, right]");
  assert.equal(drag("h[main, right]", "main|right", 0.7).text, "h[main:5, right:2]", "5/7 is 0.714");
});

test("no child goes past 5 of its split, however far the divider goes", () => {
  assert.deepEqual(drag("h[main, right]", "main|right", 0), { text: "h[main, right:5]", label: "1 : 5", changed: true });
  assert.equal(drag("h[main, right]", "main|right", 1).text, "h[main:5, right]");
  // nothing keeping b|c at 2/3 comes near: b|c gives a little
  assert.equal(drag("h[a, b, c]", "a|b", 1).text, "h[a:4, b, c]");
});

test("the other dividers stay where the drag found them: 1 : 1 : 1's first divider leaves the second at 2/3", () => {
  // a | b is let go at a sixth of the split (a quarter of a and b)
  assert.deepEqual(drag("h[a, b, c]", "a|b", 0.25), { text: "h[a, b:3, c:2]", label: "1 : 3 : 2", changed: true });
  assert.equal(drag("h[a, b, c]", "a|b", 0.75).text, "h[a:3, b, c:2]");
  assert.equal(drag("h[a, b, c]", "a|b", 0.375).text, "h[a:3, b:5, c:4]", "a quarter of the split");
  assert.equal(drag("v[a, b, c, d]", "b|c", 0.75).text, "v[a:2, b:3, c, d:2]");
});

test("back where it started, the split is the ratio it started as", () => {
  for (const [text, id, at, label] of [
    ["h[a, b, c]", "a|b", 0.5, "1 : 1 : 1"], ["h[a:2, b:3, c]", "b|c", 0.75, "2 : 3 : 1"],
    ["v[a, b:5, c:2, d]", "a|b", 1 / 6, "1 : 5 : 2 : 1"],
  ]) {
    for (const away of [0.3, 0.9, 1]) assert.ok(drag(text, id, away).changed, `${text} dragged to ${away}`);
    assert.deepEqual(drag(text, id, at), { text, label, changed: false });
  }
});

test("with no such arrangement near, the nearest arrangement moves the other dividers least", () => {
  // a tenth of a and b is a fifteenth of the split; the nearest keeping b|c
  // at 2/3 is 1 : 5 : 3 (a ninth)
  assert.equal(drag("h[a, b, c]", "a|b", 0.1).text, "h[a, b:5, c:3]");
  assert.equal(drag("h[a, b, c]", "a|b", 0).text, "h[a, b:5, c:3]");
  // four, a at 1/40 of the split: the other two dividers give a little
  assert.equal(drag("h[a, b, c, d]", "a|b", 0.05).text, "h[a, b:5, c:3, d:3]");
});

test("typed weights over 5 still drag, to the nearest capped arrangement", () => {
  // 6 : 1 : 6: b|c at 7/13 suits no capped tuple; a|b let go mid a and b
  assert.deepEqual(drag("h[a:6, b, c:6]", "a|b", 0.5), { text: "h[a:3, b:3, c:5]", label: "3 : 3 : 5", changed: true });
  assert.equal(drag("h[main:7, right:3]", "main|right", 0.7).text, "h[main:5, right:2]");
  assert.deepEqual(drag("h[main:12, right]", "main|right", null), { text: "h[main:12, right]", label: "12 : 1", changed: false });
});

test("a split of more than six snaps only the dragged divider's two neighbours, 1 to 5, none below 5%", () => {
  assert.equal(drag("h[a, b, c, d, e, f, g]", "a|b", 0.25).text, "h[a, b:3, c:2, d:2, e:2, f:2, g:2]");
  // 1 : 5 of a and b would leave a 1/21 of the split
  assert.equal(drag("h[a, b, c, d, e, f, g]", "a|b", 0).text, "h[a:2, b:8, c:5, d:5, e:5, f:5, g:5]");
});

test("a nested split's divider changes that split only, at any depth", () => {
  assert.deepEqual(drag("h[main:2, v[right, side:3]]", "right|side", 0.5),
    { text: "h[main:2, v[right, side]]", label: "1 : 1", changed: true });
  assert.equal(drag("h[main:2, v[right, side:3]]", "main|right", 0.5).text, "h[main, v[right, side:3]]");
  assert.equal(drag("v[top, h[a, v[b, c:2]]:3]", "b|c", 0.5).text, "v[top, h[a, v[b, c]]:3]");
  assert.equal(drag("v[top, h[a, v[b, c:2]]:3]", "a|b", 0.25).text, "v[top, h[a, v[b, c:2]:3]:3]");
  assert.deepEqual(drag("h[main, v[aside, side:3, left]]", "aside|side", 0.5),
    { text: "h[main, v[aside:2, side:2, left]]", label: "2 : 2 : 1", changed: true });
});

test("a drag that snaps to the ratio there already changes nothing", () => {
  assert.deepEqual(drag("h[main:2, right]", "main|right", 0.66), { text: "h[main:2, right]", label: "2 : 1", changed: false });
});

test("other windows' place hidden from the picture keeps its size", () => {
  // the picture is h[a, b]; * sits between them in the tree
  assert.equal(drag("h[a, *, b]", "a|b", 0.75).text, "h[a:3, *:2, b]");
  // the picture is h[a, b, c]: its dividers keep to their places in it
  assert.equal(drag("h[a, b, c, *]", "a|b", 0.25).text, "h[a, b:3, c:2, *:2]");
});

test("other windows' place shown: one of the split's children like any other", () => {
  // the picture is h[a:3, b:3, *:2]
  assert.deepEqual(drag("h[a, b]", "b|*", 0.8, true), { text: "h[a:3, b:4, *]", label: "3 : 4 : 1", changed: true });
  assert.equal(drag("h[a, b]", "a|b", 0.25, true).text, "h[a, b:3]", "a divider away from it leaves it out");
  // its * leaf in the tree, shown: it takes part
  assert.equal(drag("h[a, b, *]", "a|b", 0.25, true).text, "h[a, b:3, *:2]");
});

// --- the engine reads a dragged tree as the same ratio typed with r ---------

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { luaBin, skipWithoutLua } from "./lua.mjs";

test("a drag is the whole tree's ratio as ratio.lua writes it in, and tree.lua reads it back", { skip: skipWithoutLua }, () => {
  const cases = [
    ["h[main:2, right]", "main|right", 0.5], ["h[main, right]", "main|right", 0.43], ["h[main, right]", "main|right", 0.477],
    ["h[main, right]", "main|right", 0], ["h[a, b, c:8]", "a|b", 0], ["h[a, b, c]", "a|b", 0.25],
    ["v[a, b, c, d]", "b|c", 0.75], ["h[main:2, v[right, side:3]]", "right|side", 0.5],
    ["h[main:2, v[right, side:3]]", "main|right", 0.3], ["v[top, h[a, v[b, c:2]]:3]", "a|b", 0.25],
    ["h[a, *, b]", "a|b", 0.75], ["h[main:2, v[right, *]]", "right|*", 0.9, true], ["h[a, b]", "b|*", 0.8, true],
    ["h[a, b, c]", "a|b", 1], ["h[a, b, c, d]", "a|b", 0.05], ["h[a:6, b, c:6]", "a|b", 0.5],
    ["h[a, b, c, *]", "a|b", 0.25], ["h[a, b, c, d, e, f, g]", "a|b", 0],
  ];
  const results = cases.map(([text, id, f, shown]) => drag(text, id, f, shown).text);
  const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
  const script = `
package.path = "${root}/lua/?.lua;" .. package.path
local tree, ratio, serialize = require("hyprslots.tree"), require("hyprslots.ratio"), require("hyprslots.serialize")
for line in io.lines() do
  local text, dragged = line:match("^(.-)\\t(.*)$")
  local node = assert(tree.parse(text))
  local after = assert(tree.parse(dragged))
  local applied = assert(ratio.apply(node, ratio.format(after)))
  print(serialize.tree(applied) .. " | " .. serialize.tree(after))
end`;
  const run = spawnSync(luaBin(), ["-e", script], {
    // other windows' place shown: the drag writes it in, so the ratio is the
    // tree's with it (withOther)
    input: cases.map(([text, , , shown], i) => (shown ? L.format(L.withOther(tree(text))) : text) + "\t" + results[i])
      .join("\n") + "\n", encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  run.stdout.trimEnd().split("\n").forEach((line, i) => {
    assert.equal(line, results[i] + " | " + results[i], `${cases[i].join(" ")}`);
  });
});

test("a divider held where it is (no fraction yet) changes nothing and names its split's ratio", () => {
  const draft = tree("h[main:4, v[right, side:3]:2]");
  const [outer, inner] = L.dividers(L.picture(draft, false), AREA, { pad: 5, title: 10 });
  assert.deepEqual(plain(L.dragDivider(draft, outer, null)).label, "2 : 1");
  assert.deepEqual(plain(L.dragDivider(draft, inner, null)).label, "1 : 3");
  assert.equal(L.dragDivider(draft, inner, null).changed, false);
  assert.equal(L.dragDivider(draft, inner, null).node, draft);
});
