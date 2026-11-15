// The Layout view's panes on a desk of several monitors (Layout.js): each a
// scale model of its monitor (the desk's geometry from state), one scale for
// all so a 2560-wide screen is drawn larger than a 1920 one, top-aligned,
// as large as the picture's area allows; a scroll screen's pane wider than
// its screen so the filmstrip around it shows (up to three screens'
// widths), never at the cost of shrinking the screens below a floor.
import { test } from "node:test";
import assert from "node:assert/strict";
import { load } from "./load.mjs";

const L = load("Layout.js");
const plain = (value) => JSON.parse(JSON.stringify(value));

const FHD = { w: 1920, h: 1080 };
const QHD = { w: 2560, h: 1440 };

test("panes take their monitors' sizes at one scale, side by side, top-aligned", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD }, { key: "2", ...QHD }], { w: 788, h: 400 }, { gap: 12 }));
  // width-limited: (788 - 12) / (1920 + 2560)
  const s = 776 / 4480;
  assert.equal(out.scale, s);
  assert.deepEqual(out.panes.map((p) => [p.key, p.x, p.w]), [["1", 0, 332], ["2", 344, 443]]);
  assert.deepEqual(out.panes[0].screen, { x: 0, y: 0, w: 332, h: 187 });
  assert.deepEqual(out.panes[1].screen, { x: 0, y: 0, w: 443, h: 249 });
});

test("limited by the height, the screens fill it and the row is centred across", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD }], { w: 1000, h: 300 }, { gap: 12 }));
  assert.deepEqual(out.panes[0].screen, { x: 0, y: 0, w: 533, h: 300 });
  assert.equal(out.panes[0].x, 233);
});

test("a monitor of another shape keeps its own aspect", () => {
  const out = plain(L.paneLayout([{ key: "1", w: 5120, h: 1440 }, { key: "2", w: 1080, h: 1920 }], { w: 1000, h: 400 }, { gap: 10 }));
  const [wide, tall] = out.panes.map((p) => p.screen);
  assert.ok(Math.abs(wide.w / wide.h - 5120 / 1440) < 0.05, `wide ${wide.w}x${wide.h}`);
  assert.ok(Math.abs(tall.w / tall.h - 1080 / 1920) < 0.05, `tall ${tall.w}x${tall.h}`);
  assert.ok(tall.h <= 400 && wide.w + tall.w + 10 <= 1000);
});

test("an unknown monitor is drawn as 16:9 at 1920", () => {
  const out = plain(L.paneLayout([{ key: "1" }, { key: "2", ...FHD }], { w: 410, h: 400 }, { gap: 10 }));
  assert.deepEqual(out.panes[0].screen, out.panes[1].screen);
});

test("a scroll screen's pane takes up to three of its screens' widths, the screen in its middle", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD, scroll: true }], { w: 2000, h: 300 }, { gap: 12 }));
  const p = out.panes[0];
  assert.equal(p.screen.w, 533);
  assert.equal(p.w, 1599, "three screens' widths");
  assert.equal(p.screen.x, 533);
  assert.equal(p.x, 200, "the rest of the width either side of the row");
});

test("short of width, a scroll pane shrinks the screens no further than the floor and takes what is left", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD }, { key: "2", ...QHD, scroll: true }], { w: 788, h: 400 },
    { gap: 12, floor: 0.7 }));
  const tiles = 776 / 4480;
  assert.equal(out.scale, 0.7 * tiles, "three widths would shrink them below 70% of the tiles' scale");
  const [one, two] = out.panes;
  assert.equal(one.screen.w, Math.floor(1920 * 0.7 * tiles));
  assert.equal(two.screen.w, Math.floor(2560 * 0.7 * tiles));
  assert.equal(one.w + 12 + two.w, 788, "the scroll pane takes the rest of the row");
  assert.ok(two.w > two.screen.w * 1.5);
  assert.equal(two.screen.x, Math.floor((two.w - two.screen.w) / 2));
});

test("with room for it, a scroll pane takes three widths at the tiles' own scale", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD }, { key: "2", ...FHD, scroll: true }], { w: 3000, h: 216 }, { gap: 0 }));
  assert.equal(out.scale, 0.2);
  assert.equal(out.panes[1].w, 384 * 3);
});

test("a scroll screen leaves room under it for its label", () => {
  const out = plain(L.paneLayout([{ key: "1", ...FHD, scroll: true }], { w: 5000, h: 300 }, { gap: 0, footer: 30 }));
  assert.equal(out.panes[0].screen.h, 270);
  assert.equal(out.panes[0].h, 300);
});

test("no panes, no layout", () => {
  assert.deepEqual(plain(L.paneLayout([], { w: 100, h: 100 }, {})), { scale: 0, panes: [] });
});

test("a screen's size is the active desk's geometry for it, by screen number", () => {
  const state = { desk: "dual", desks: { dual: { geometry: [
    { x: 1920, y: 0, w: 2560, h: 1440, screen: 2 }, { x: 0, y: 0, w: 1920, h: 1080, screen: 1 }] } } };
  assert.deepEqual(plain(L.screenSize(state, 1)), { w: 1920, h: 1080 });
  assert.deepEqual(plain(L.screenSize(state, 2)), { w: 2560, h: 1440 });
  assert.equal(L.screenSize(state, 3), null);
  assert.equal(L.screenSize({ desk: null, desks: {} }, 1), null);
  assert.equal(L.screenSize(null, 1), null);
});
