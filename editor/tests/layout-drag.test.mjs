// The Layout picture's dividers (Layout.js): every boundary between two
// children of a tiled split, dragged by mouse to a new ratio of the two,
// snapped to simple integer weights.
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
    before: ["main"], after: ["right"], depth: 1 }]);
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

// --- dragging one: the two neighbours' new ratio, snapped -------------------

// Drag the divider `id` of the picture of `text` (o: other windows shown
// when `showOther`) to `fraction` of its two neighbours: the draft's text,
// and the split's ratio as the label near the pointer says it.
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

test("dragged to the middle, h[main:2, right] becomes h[main, right]", () => {
  assert.deepEqual(drag("h[main:2, right]", "main|right", 0.5), { text: "h[main, right]", label: "1 : 1", changed: true });
});

test("the smallest whole pair within 2% of the pair wins: a little off the middle is still 1 : 1", () => {
  assert.equal(drag("h[main:2, right]", "main|right", 0.519).text, "h[main, right]");
  assert.equal(drag("h[main:2, right]", "main|right", 0.481).text, "h[main, right]");
  assert.equal(drag("h[main, right]", "main|right", 0.65).text, "h[main:2, right]", "2/3 is 0.667");
  assert.equal(drag("h[main, right]", "main|right", 0.41).text, "h[main:2, right:3]", "2/5 before 5/12");
  assert.equal(drag("h[main, right]", "main|right", 0.43).text, "h[main:3, right:4]", "3/7");
  assert.equal(drag("h[main, right]", "main|right", 0.75).text, "h[main:3, right]");
});

test("with none within 2%, the nearest pair of twelfths or less", () => {
  // 0.477: 1/2 is 0.023 away, 5/11 0.0225
  assert.equal(drag("h[main, right]", "main|right", 0.477).text, "h[main:5, right:6]");
});

test("no child of the split drops below 5% of it; with two, a twelfth of it is the least", () => {
  assert.equal(drag("h[main, right]", "main|right", 0).text, "h[main, right:11]");
  assert.equal(drag("h[main, right]", "main|right", 1).text, "h[main:11, right]");
  // a and b are a fifth of the split: a twelfth of them would be under 5% of it
  assert.equal(drag("h[a, b, c:8]", "a|b", 0).text, "h[a, b:3, c:16]", "a: 1/20 of the split");
  // a and b together a tenth: each needs half of it
  assert.deepEqual(drag("h[a, b, c:18]", "a|b", 0.1), { text: "h[a, b, c:18]", label: "1 : 1 : 18", changed: false });
});

test("only the two neighbours change: the split's other children keep their size", () => {
  assert.deepEqual(drag("h[a, b, c]", "a|b", 0.25), { text: "h[a, b:3, c:2]", label: "1 : 3 : 2", changed: true });
  assert.equal(drag("v[a, b, c, d]", "b|c", 0.75).text, "v[a:2, b:3, c, d:2]");
});

test("a nested split's divider changes that split only, at any depth", () => {
  assert.deepEqual(drag("h[main:2, v[right, side:3]]", "right|side", 0.5),
    { text: "h[main:2, v[right, side]]", label: "1 : 1", changed: true });
  assert.equal(drag("h[main:2, v[right, side:3]]", "main|right", 0.5).text, "h[main, v[right, side:3]]");
  assert.equal(drag("v[top, h[a, v[b, c:2]]:3]", "b|c", 0.5).text, "v[top, h[a, v[b, c]]:3]");
  assert.equal(drag("v[top, h[a, v[b, c:2]]:3]", "a|b", 0.25).text, "v[top, h[a, v[b, c:2]:3]:3]");
});

test("a drag that snaps to the ratio there already changes nothing", () => {
  assert.deepEqual(drag("h[main:2, right]", "main|right", 0.66), { text: "h[main:2, right]", label: "2 : 1", changed: false });
});

test("other windows' place hidden from the picture keeps its size", () => {
  // the picture is h[a, b]; * sits between them in the tree
  assert.equal(drag("h[a, *, b]", "a|b", 0.75).text, "h[a:3, *:2, b]");
});

test("other windows' place shown where the engine puts it: dragging next to it writes it into the tree", () => {
  // the picture is h[a:3, b:3, *:2]
  assert.equal(drag("h[a, b]", "b|*", 0.5, true).text, "h[a:6, b:5, *:5]", "a keeps its 3/8");
  assert.equal(drag("h[a, b]", "a|b", 0.25, true).text, "h[a, b:3]", "a divider away from it leaves it out");
});

// --- the engine reads a dragged tree as the same ratio typed with r ---------

import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const LUA = ["lua5.4", "lua5.5", "lua"].find((bin) => spawnSync(bin, ["-v"]).status === 0);

test("a drag is the whole tree's ratio as ratio.lua writes it in, and tree.lua reads it back", { skip: !LUA && "no lua" }, () => {
  const cases = [
    ["h[main:2, right]", "main|right", 0.5], ["h[main, right]", "main|right", 0.43], ["h[main, right]", "main|right", 0.477],
    ["h[main, right]", "main|right", 0], ["h[a, b, c:8]", "a|b", 0], ["h[a, b, c]", "a|b", 0.25],
    ["v[a, b, c, d]", "b|c", 0.75], ["h[main:2, v[right, side:3]]", "right|side", 0.5],
    ["h[main:2, v[right, side:3]]", "main|right", 0.3], ["v[top, h[a, v[b, c:2]]:3]", "a|b", 0.25],
    ["h[a, *, b]", "a|b", 0.75], ["h[main:2, v[right, *]]", "right|*", 0.9, true], ["h[a, b]", "b|*", 0.5, true],
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
  const run = spawnSync(LUA, ["-e", script], {
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
