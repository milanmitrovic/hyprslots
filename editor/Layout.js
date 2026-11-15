.pragma library

// The Layout view's model (docs/design.md §9): one workspace's trees, edited
// as a draft before they are applied. Ported from aerolayout's
// tree_visualizer.py (move, force move, flip, toggle, overflow, the nested
// ratio editor) onto hyprslots' tree text (tree.lua) and ratio grammar
// (ratio.lua), which are mirrored here so the draft can be edited, shown and
// checked without a round trip; the engine validates again on apply. Pure, so
// node can test it (editor/tests/layout.test.mjs).
//
// A node is
//   { kind: "slot", slot, weight }          a slot
//   { kind: "overflow", weight }            where other windows go (windows
//                                           assigned to no slot), written *
//   { kind: "h" | "v", weight, children }   a split
//   { kind: "scroll", weight, children, width?, was? }  a scroll branch:
//                                           the whole tree, slots only,
//                                           scrolling columns in order, each
//                                           `width` of the screen (none: full
//                                           width, scroll:0.5[...]: half); `was`
//                                           remembers the tree t made it from
// A leaf is named by its key: the slot's name, or "*" for other windows.
// Every tree has a place for other windows: its * leaf, or, without one,
// where the engine puts them (withOther). The editor never takes it away;
// it only shows it in the picture or not (picture).
// Every edit returns { node } (a new tree) or { error }; the tree given is
// never changed.

var OVERFLOW = "*"

// --- tree text (tree.lua) ---------------------------------------------------

var NAME = /^[A-Za-z0-9_\-.]+/
// The narrowest column a scroll branch may ask for (a fraction of the screen).
var MIN_WIDTH = 0.1
var CONTAINER = { h: true, v: true, a: true, scroll: true }

function TreeError(message) {
  this.treeError = message
}

// Parse tree text: { node } or { error } with tree.lua's own message.
function parse(text) {
  if (typeof text !== "string") return { error: "a tree must be a string, got " + typeof text }
  var pos = 0
  var overflow = false

  function fail(message) {
    throw new TreeError(message + " at position " + (pos + 1) + " in '" + text + "'")
  }
  function skip() {
    while (pos < text.length && /\s/.test(text.charAt(pos))) pos++
  }
  function peek() {
    skip()
    return text.charAt(pos)
  }
  function expect(c) {
    if (peek() !== c) fail("expected '" + c + "', found " + (pos >= text.length ? "end of text" : "'" + peek() + "'"))
    pos++
  }
  function name() {
    skip()
    var m = NAME.exec(text.slice(pos))
    if (!m) fail("expected a slot name, found " + (pos >= text.length ? "end of text" : "'" + text.charAt(pos) + "'"))
    pos += m[0].length
    return m[0]
  }
  function weight() {
    if (peek() !== ":") return 1
    pos++
    skip()
    var m = /^[0-9.\-]+/.exec(text.slice(pos))
    var digits = m ? m[0] : null
    var w = digits && /^\d+$/.test(digits) ? parseInt(digits, 10) : NaN
    if (!(w >= 1)) fail("a weight must be a positive integer, got '" + (digits || text.charAt(pos)) + "'")
    pos += digits.length
    return w
  }
  // `weightless` is the error a weight on a child is.
  function children(child, weightless) {
    pos++
    var out = []
    var more
    do {
      var n = child()
      if (weightless && peek() === ":") fail(weightless)
      n.weight = weight()
      out.push(n)
      more = peek() === ","
      if (more) pos++
    } while (more)
    expect("]")
    return out
  }
  // A member of a slots-only container (`what` names it in errors); the
  // overflow leaf only where `overflow` says it may be (a scroll branch's
  // column for windows with no slot).
  function member(what, overflowOk) {
    return function() {
      if (peek() === "*") {
        if (overflowOk) return node(false)
        fail(what + " holds slots only, found '*' inside it")
      }
      skip()
      var start = pos
      var n = name()
      if (CONTAINER[n] && peek() === "[") {
        pos = start
        fail(what + " holds slots only, found '" + n + "[' inside it")
      }
      return { kind: "slot", slot: n }
    }
  }
  // After `scroll`: `:<width>[` gives a scroll branch's column width (a
  // fraction of the screen, 1 = full width, kept as none). Returns
  // { width } (null for full) with the position at its '[', or null when
  // `scroll` is no container with a width.
  function scrollWidth() {
    var m = /^\s*:\s*([^\[\]\s,]*)\s*\[/.exec(text.slice(pos))
    if (!m) return null
    var given = m[1]
    var w = /^\d*\.?\d+$/.test(given) ? parseFloat(given) : NaN
    if (!(w >= MIN_WIDTH && w <= 1)) {
      pos = text.indexOf(":", pos) + 1
      skip()
      fail("a scroll width must be a fraction of the screen from " + MIN_WIDTH + " to 1, got '" + given + "'")
    }
    pos += m[0].length - 1
    return { width: w < 1 ? w : null }
  }
  // `root` when the node is the whole tree (where scroll[...] may be).
  function node(root) {
    if (peek() === "*") {
      if (overflow) fail("more than one place for other windows '*'")
      overflow = true
      pos++
      return { kind: "overflow" }
    }
    skip()
    var start = pos
    var n = name()
    var sized = null
    if (n === "scroll") {
      var probe = pos
      sized = scrollWidth()
      if (sized && !root) {
        pos = start
        fail("scroll[...] is a whole screen's tree, found it inside a split")
      }
      if (!sized) pos = probe
    }
    if (CONTAINER[n] && peek() === "[") {
      if (n === "a") {
        var slots = children(member("a[...]"), "a[...] is gone").map(function(c) { return c.slot })
        pos = start
        fail("a[...] (an accordion, a Hyprland group with tabs) is gone: write scroll[" + slots.join(", ")
          + "] for full-width scrolling columns" + (root ? "" : " (as a screen's whole tree)"))
      }
      if (n === "scroll") {
        if (!root) {
          pos = start
          fail("scroll[...] is a whole screen's tree, found it inside a split")
        }
        var branch = { kind: "scroll", children: children(member("scroll[...]", true), "columns of scroll[...] take no weight (each is full width)") }
        if (sized && sized.width) branch.width = sized.width
        return branch
      }
      return { kind: n, children: children(function() { return node(false) }, false) }
    }
    return { kind: "slot", slot: n }
  }

  var root
  try {
    root = node(true)
    if (peek() === ":") fail("the root of a tree takes no weight")
    if (pos < text.length) fail("unexpected '" + text.charAt(pos) + "'")
  } catch (e) {
    if (e instanceof TreeError) return { error: e.treeError }
    throw e
  }
  root.weight = 1
  var seen = {}
  var slots = leaves(root)
  for (var i = 0; i < slots.length; i++) {
    if (slots[i] === OVERFLOW) continue
    if (seen[slots[i]]) return { error: "slot '" + slots[i] + "' appears twice in '" + text + "'" }
    seen[slots[i]] = true
  }
  return { node: root }
}

function isLeaf(node) {
  return node.kind === "slot" || node.kind === "overflow"
}

function keyOf(node) {
  return node.kind === "overflow" ? OVERFLOW : node.slot
}

// Tree text as serialize.lua writes it: weights of 1 left out.
function format(node) {
  if (node.kind === "slot") return node.slot
  if (node.kind === "overflow") return OVERFLOW
  var parts = node.children.map(function(child) {
    var text = format(child)
    return child.weight && child.weight !== 1 ? text + ":" + child.weight : text
  })
  var kind = node.kind === "scroll" && node.width ? "scroll:" + formatWidth(node.width) : node.kind
  return kind + "[" + parts.join(", ") + "]"
}

// A scroll branch's column width as serialize.lua writes it (%.4g).
function formatWidth(width) {
  return String(Number(width.toPrecision(4)))
}

// The keys of a tree's leaves in reading order.
function leaves(node, out) {
  out = out || []
  if (isLeaf(node)) out.push(keyOf(node))
  else for (var i = 0; i < node.children.length; i++) leaves(node.children[i], out)
  return out
}

// A deep copy (the `was` memory of a scroll branch included).
function copy(node) {
  var out = {}
  for (var key in node) out[key] = node[key]
  if (node.children) out.children = node.children.map(copy)
  if (node.was) out.was = { text: node.was.text, columns: node.was.columns }
  return out
}

// --- the ratio grammar (ratio.lua) ------------------------------------------

var STAR = "*"
var ROOT_SUBJECT = "the outer container"

function RatioError(message) {
  this.ratioError = message
}

function ratioFail(message) {
  throw new RatioError(message)
}

function tokenize(text) {
  var normalized = text.split(/\s+/).filter(function(w) { return w !== "" }).join(":")
  var tokens = []
  var word = ""
  for (var i = 0; i < normalized.length; i++) {
    var c = normalized.charAt(i)
    if (c === ":" || c === "[" || c === "]") {
      if (word !== "") {
        tokens.push(word)
        word = ""
      }
      if (c !== ":" || (tokens.length > 0 && tokens[tokens.length - 1] !== ":")) tokens.push(c)
    } else {
      word += c
    }
  }
  if (word !== "") tokens.push(word)
  return tokens
}

// [{ weight: number | "*", nested?: [...] }, ...]; throws RatioError.
function parseRatio(text) {
  if (typeof text !== "string") ratioFail("a ratio must be a string, got " + typeof text)
  var tokens = tokenize(text)
  if (tokens.length === 0) ratioFail("the ratio is empty")
  var pos = 0

  function term() {
    var token = tokens[pos]
    if (token === undefined) ratioFail('ratio ends with a stray ":"')
    if (token === ":" || token === "[" || token === "]") ratioFail('expected a number, found "' + token + '"')
    var weight
    if (token === STAR) {
      weight = STAR
    } else {
      weight = /^[0-9.\-+eE]+$/.test(token) ? Number(token) : NaN
      if (isNaN(weight)) ratioFail('"' + token + '" is not a number')
      if (weight <= 0 || !isFinite(weight)) ratioFail("ratios must be greater than zero")
    }
    pos++
    var t = { weight: weight }
    if (tokens[pos] === "[") {
      pos++
      t.nested = list()
      if (tokens[pos] !== "]") ratioFail('unclosed "["')
      pos++
    }
    return t
  }
  function list() {
    var out = [term()]
    while (tokens[pos] === ":") {
      pos++
      out.push(term())
    }
    return out
  }

  var result = list()
  if (pos < tokens.length) ratioFail('unexpected "' + tokens[pos] + '"')
  return result
}

function gcd(a, b) {
  while (b !== 0) {
    var t = a % b
    a = b
    b = t
  }
  return a
}

// The integer ratio positive numbers state (ratio.integers): decimals become
// exact fractions (denominators up to 1000), then common factors go.
function integers(values) {
  var denominator = 1
  var fractions = values.map(function(value) {
    var num = value
    var den = 1
    while (!Number.isInteger(num) && den < 1000) {
      var rounded = Math.floor(num + 0.5)
      if (Math.abs(num - rounded) < 1e-9 * Math.max(1, Math.abs(num))) {
        num = rounded
        break
      }
      num = num * 10
      den = den * 10
    }
    num = Math.floor(num + 0.5)
    denominator = denominator * den / gcd(denominator, den)
    return { num: num, den: den }
  })
  var common = 0
  var out = fractions.map(function(f) {
    var n = f.num * (denominator / f.den)
    common = gcd(common, n)
    return n
  })
  return out.map(function(n) { return Math.max(1, common > 1 ? n / common : n) })
}

function cellLabel(child, index, parent) {
  var own = child.kind === "slot" ? child.slot : child.kind === "overflow" ? "the place for other windows" : "cell " + index
  return parent === ROOT_SUBJECT ? own : parent + " > " + own
}

function validate(node, list, path) {
  if (isLeaf(node)) ratioFail(path + " is a window, not a split")
  var count = node.children.length
  if (list.length !== count) {
    ratioFail("expected " + count + " value" + (count === 1 ? "" : "s") + " for " + path + ", got " + list.length)
  }
  for (var i = 0; i < list.length; i++) {
    if (node.kind === "scroll") {
      if (list[i].weight !== STAR && list[i].weight !== 1) {
        ratioFail("ratios don't apply to " + path + " — it's a scroll branch, and each of its columns "
          + "is full width. Write * for every column")
      }
    } else if (list[i].weight === STAR) {
      ratioFail("* is a scroll column with no share of its own, and " + path
        + " is tiled — every cell here needs a number")
    }
  }
  for (var j = 0; j < node.children.length; j++) {
    var nested = list[j].nested
    if (nested) {
      var child = node.children[j]
      var label = cellLabel(child, j + 1, path)
      if (isLeaf(child)) ratioFail(label + " is a window, so it has nothing to split")
      validate(child, nested, label)
    }
  }
}

function writeRatio(node, list) {
  if (isLeaf(node) || !list) return
  var weights = node.kind === "scroll" ? null : integers(list.map(function(t) { return t.weight }))
  for (var i = 0; i < node.children.length; i++) {
    if (weights) node.children[i].weight = weights[i]
    writeRatio(node.children[i], list[i].nested)
  }
}

// The tree with a whole-tree ratio (`2[1:2]:1`) written in: { node } or
// { error } in ratio.lua's words.
function applyRatio(node, text) {
  try {
    var list = parseRatio(text)
    validate(node, list, ROOT_SUBJECT)
    var out = copy(node)
    writeRatio(out, list)
    return { node: out }
  } catch (e) {
    if (e instanceof RatioError) return { error: e.ratioError }
    throw e
  }
}

// The ratio of a tree, e.g. "2[1:2]:1"; "" for a single window.
function ratio(node) {
  if (isLeaf(node) || node.children.length === 0) return ""
  var cells = node.kind === "scroll"
    ? node.children.map(function() { return STAR })
    : integers(node.children.map(function(c) { return c.weight || 1 }))
  return node.children.map(function(child, i) {
    var inner = ratio(child)
    return String(cells[i]) + (inner !== "" ? "[" + inner + "]" : "")
  }).join(":")
}

// Every split's shares equal (aerolayout: an empty ratio entry clears all).
function clearRatios(node) {
  var out = copy(node)
  ;(function walk(n) {
    if (isLeaf(n)) return
    for (var i = 0; i < n.children.length; i++) {
      n.children[i].weight = 1
      walk(n.children[i])
    }
  })(out)
  return out
}

// --- finding nodes ----------------------------------------------------------

// [{ node, index }] from the root down to the leaf `key` (the root first,
// index -1), or null.
function pathTo(node, key, path) {
  path = path || [{ node: node, index: -1 }]
  if (isLeaf(node)) return keyOf(node) === key ? path : null
  for (var i = 0; i < node.children.length; i++) {
    var found = pathTo(node.children[i], key, path.concat([{ node: node.children[i], index: i }]))
    if (found) return found
  }
  return null
}

// The axis a container lays its children along; a scroll branch's columns
// sit side by side.
function axisOf(node) {
  return node.kind === "v" ? "v" : "h"
}

var AXIS = { left: "h", right: "h", up: "v", down: "v" }
var STEP = { left: -1, right: 1, up: -1, down: 1 }

function firstLeaf(node) {
  while (!isLeaf(node)) node = node.children[0]
  return keyOf(node)
}

// The leaf an arrow selects from `key` (navigate_spatial): the nearest
// container along that axis with a sibling that way, entered at its first
// leaf. null when there is none.
function navigate(root, key, direction) {
  var path = pathTo(root, key)
  if (!path) return null
  for (var depth = path.length - 1; depth > 0; depth--) {
    var parent = path[depth - 1].node
    var index = path[depth].index + STEP[direction]
    if (axisOf(parent) === AXIS[direction] && index >= 0 && index < parent.children.length) {
      return firstLeaf(parent.children[index])
    }
  }
  return null
}

// --- tidying (prune_and_hoist, normalize_alternation) ------------------------

// A container left with one child is replaced by it (which takes its
// share), except a scroll branch, which may hold one column; a child split of
// the same kind is merged in, its children's shares scaled so nothing moves
// on screen. Empty containers go. Changes `node` in place and returns its
// replacement, or null when nothing is left.
function tidy(node) {
  if (isLeaf(node)) return node
  var kept = []
  for (var i = 0; i < node.children.length; i++) {
    var child = tidy(node.children[i])
    if (child) kept.push(child)
  }
  var mergeable = function(c) { return !isLeaf(c) && c.kind === node.kind && c.kind !== "scroll" }
  var sumOf = function(list) { return list.reduce(function(s, c) { return s + c.weight }, 0) }
  // Shares stay integers: everything is scaled by the lcm of the merged
  // splits' totals, a merged child's share spread over its children.
  var lcm = 1
  kept.forEach(function(c) {
    if (mergeable(c)) {
      var total = sumOf(c.children)
      lcm = lcm * total / gcd(lcm, total)
    }
  })
  var children = []
  kept.forEach(function(c) {
    if (!mergeable(c)) {
      c.weight = c.weight * lcm
      children.push(c)
      return
    }
    var total = sumOf(c.children)
    c.children.forEach(function(gc) {
      gc.weight = gc.weight * c.weight * (lcm / total)
      children.push(gc)
    })
  })
  if (lcm > 1 || children.length !== kept.length) {
    var common = children.reduce(function(g, c) { return gcd(g, c.weight) }, 0)
    if (common > 1) children.forEach(function(c) { c.weight = c.weight / common })
  }
  node.children = children
  if (children.length === 0) return null
  if (children.length === 1 && node.kind !== "scroll") {
    children[0].weight = node.weight
    return children[0]
  }
  return node
}

function rooted(node) {
  var out = tidy(node)
  if (out) out.weight = 1
  return out
}

// --- edits ------------------------------------------------------------------

// h j k l: swap the leaf with its neighbour that way in its own container
// (move_node). { node, changed }.
function move(root, key, direction) {
  var out = copy(root)
  var path = pathTo(out, key)
  if (!path || path.length < 2) return { node: out, changed: false }
  var parent = path[path.length - 2].node
  var index = path[path.length - 1].index
  var other = index + STEP[direction]
  if (axisOf(parent) !== AXIS[direction] || other < 0 || other >= parent.children.length) {
    return { node: out, changed: false }
  }
  var swap = parent.children[other]
  parent.children[other] = parent.children[index]
  parent.children[index] = swap
  return { node: out, changed: true }
}

var SCROLL_SLOTS = "a scroll branch holds slots only (its columns in order); t cycles to tiles"

// H J K L (force_move_node). Along its container: pair the leaf with its
// neighbour that way in a new container across it. Across its container:
// take the leaf out and put it beside the container, on that side (a new
// root when the container is the root). { node, changed } or { error }.
function forceMove(root, key, direction) {
  var out = copy(root)
  var path = pathTo(out, key)
  if (!path || path.length < 2) return { node: out, changed: false }
  var leaf = path[path.length - 1].node
  var index = path[path.length - 1].index
  var parent = path[path.length - 2].node
  var after = STEP[direction] > 0
  if (parent.kind === "scroll") return { error: SCROLL_SLOTS }
  if (axisOf(parent) === AXIS[direction]) {
    var other = index + STEP[direction]
    if (other < 0 || other >= parent.children.length) return { node: out, changed: false }
    var neighbour = parent.children[other]
    var first = Math.min(index, other)
    var pair = {
      kind: AXIS[direction] === "h" ? "v" : "h",
      weight: leaf.weight + neighbour.weight,
      children: [parent.children[first], parent.children[first + 1]],
    }
    parent.children.splice(first, 2, pair)
  } else if (path.length === 2) {
    parent.children.splice(index, 1)
    var moved = { kind: leaf.kind, slot: leaf.slot, weight: 1 }
    if (leaf.kind === "overflow") delete moved.slot
    parent.weight = 1
    out = { kind: AXIS[direction], weight: 1, children: after ? [parent, moved] : [moved, parent] }
  } else {
    var grand = path[path.length - 3].node
    var at = path[path.length - 2].index
    parent.children.splice(index, 1)
    grand.children.splice(after ? at + 1 : at, 0, leaf)
  }
  return { node: rooted(out), changed: true }
}

// /: every split turned the other way (flip_tree). Tiles only: a scroll
// tree's columns stand in a row whatever happens (flipError says so).
function flipError(root) {
  return root && root.kind === "scroll" ? "Flip is for tiles: a scroll tree's columns always stand in a row. t cycles to tiles." : ""
}

function flip(root) {
  var out = copy(root)
  ;(function walk(n) {
    if (n.kind === "h") n.kind = "v"
    else if (n.kind === "v") n.kind = "h"
    if (n.children) n.children.forEach(walk)
  })(out)
  return out
}

// The width t gives a tiled tree first: half the screen per column.
var HALF = 0.5

// What a tree is to t: "tiles", a scroll branch of "half" or "full"
// screen-width columns, or one of an "other" width.
function scrollMode(node) {
  if (!node || node.kind !== "scroll") return "tiles"
  if (!node.width) return "full"
  return node.width === HALF ? "half" : "other"
}

// What the view calls a tree: "tiles", "scroll · half", "scroll · full",
// "scroll · 33%".
function modeLabel(node) {
  var mode = scrollMode(node)
  if (mode === "tiles") return "tiles"
  if (mode === "other") return "scroll · " + Math.round(node.width * 100) + "%"
  return "scroll · " + mode
}

// What t makes of a tree, for the help row.
function cycleLabel(node) {
  var mode = scrollMode(node)
  return mode === "tiles" ? "scroll half" : mode === "full" ? "tiles" : "scroll full"
}

// t: tiles -> scroll half -> scroll full -> tiles. The whole tree becomes a
// scroll branch of its leaves in reading order, half-width columns (the
// overflow leaf as the column windows with no slot take); then the same
// columns full width (a scroll branch of any other width goes to full);
// then back to the tree it was made from when its columns are as they were,
// else its columns side by side. { node } or { error }.
function cycleScroll(root) {
  var mode = scrollMode(root)
  if (mode === "half" || mode === "other") {
    var full = copy(root)
    delete full.width
    return { node: full }
  }
  if (mode === "full") {
    var columns = leaves(root).join(",")
    if (root.was && root.was.columns === columns) {
      var back = parse(root.was.text)
      if (back.node) return { node: back.node }
    }
    var tiled = copy(root)
    tiled.kind = "h"
    delete tiled.was
    if (tiled.children.length === 1) return { node: rooted(tiled) }
    return { node: tiled }
  }
  var keys = leaves(root)
  if (!keys.some(function(key) { return key !== OVERFLOW })) return { error: "this tree has only other windows: nothing to scroll" }
  return { node: {
    kind: "scroll", weight: 1, width: HALF,
    children: keys.map(function(key) {
      return key === OVERFLOW ? { kind: "overflow", weight: 1 } : { kind: "slot", slot: key, weight: 1 }
    }),
    was: { text: format(root), columns: keys.join(",") },
  } }
}

// The leaf `key` taken out of the tree, tidied: { node } (null when it was
// the whole tree), and where it sat as { key, side } of a leaf beside it.
function takeOut(root, key) {
  var out = copy(root)
  var path = pathTo(out, key)
  if (path.length < 2) return { node: null, anchor: null }
  var parent = path[path.length - 2].node
  var index = path[path.length - 1].index
  var anchor = null
  if (index > 0) {
    var before = leaves(parent.children[index - 1])
    anchor = { key: before[before.length - 1], side: "after" }
  } else if (index + 1 < parent.children.length) {
    anchor = { key: leaves(parent.children[index + 1])[0], side: "before" }
  }
  parent.children.splice(index, 1)
  return { node: rooted(out), anchor: anchor }
}

// Where the engine puts windows when a tree has no overflow leaf
// (tree.with_overflow): a column at the right, h[tree:3, *:1].
function withOverflow(root) {
  var kept = copy(root)
  kept.weight = 3
  return rooted({ kind: "h", weight: 1, children: [kept, { kind: "overflow", weight: 1 }] })
}

// The tree with its place for other windows written out: as it is when it
// has its * leaf, else where the engine puts them without one (a scroll
// branch: a column after its own; any other tree: a column at the right,
// withOverflow). Moving * first writes it out so.
function withOther(root) {
  if (leaves(root).indexOf(OVERFLOW) >= 0) return root
  if (root.kind === "scroll") {
    var last = copy(root)
    last.children.push({ kind: "overflow", weight: 1 })
    return last
  }
  return withOverflow(root)
}

// The tree the picture draws: with its place for other windows (withOther)
// when `showOther` (o), else without it (a * leaf that is the whole tree
// stays). null for no tree.
function picture(root, showOther) {
  if (!root) return null
  if (showOther) return withOther(root)
  if (isLeaf(root) || leaves(root).indexOf(OVERFLOW) < 0) return root
  return takeOut(root, OVERFLOW).node
}

// A leaf moved off the left or right edge of its screen's tree onto the
// next screen's (`target`, null when that screen has no tree for the
// workspace), arriving at the near edge (aerolayout's cross-pane move).
// { source, target } or { error }.
function crossMove(source, target, key, direction) {
  if (key === OVERFLOW) {
    return { error: "other windows stay on their screen: every screen's tree has its own place for them" }
  }
  if (isLeaf(source)) {
    return { error: key + " is the only window on this screen; moving it would leave the screen empty" }
  }
  var path = pathTo(source, key)
  var leaf = path[path.length - 1].node
  var moved = leaf.kind === "overflow" ? { kind: "overflow", weight: 1 } : { kind: "slot", slot: leaf.slot, weight: 1 }
  var rest = takeOut(source, key).node
  if (!target) return { source: rest, target: moved }
  var into = copy(target)
  var atStart = STEP[direction] > 0
  if (into.kind === "h" || into.kind === "scroll") {
    into.children.splice(atStart ? 0 : into.children.length, 0, moved)
  } else {
    into.weight = 1
    into = { kind: "h", weight: 1, children: atStart ? [moved, into] : [into, moved] }
  }
  return { source: rest, target: rooted(into) }
}

// --- swapping screens ------------------------------------------------------------

// The drafts (screen key -> { node, base }) with screens `a` and `b`'s trees
// traded: a pane dragged onto another by its title, or p. The screens keep
// their numbers (left to right) and their bases (the trees in force there),
// so both are edited until applied; each tree goes whole, its place for
// other windows (its * leaf, or none: the engine's column at its right),
// a scroll branch's column width and t's memory of the tiles it came from
// included. { drafts } or { error }.
function swapScreens(drafts, a, b) {
  a = String(a)
  b = String(b)
  if (a === b) return { error: "Screen " + a + " cannot be swapped with itself." }
  var missing = [a, b].filter(function(k) { return !drafts || !drafts[k] })
  if (missing.length) return { error: "There is no screen " + missing[0] + " in this layout." }
  var empty = [a, b].filter(function(k) { return !drafts[k].node })
  if (empty.length) return { error: "Screen " + empty[0] + " has no tree here, so there is nothing to swap with it." }
  var out = {}
  for (var k in drafts) out[k] = drafts[k]
  out[a] = { node: copy(drafts[b].node), base: drafts[a].base }
  out[b] = { node: copy(drafts[a].node), base: drafts[b].base }
  return { drafts: out }
}

function swappedText(a, b) {
  return "Swapped screens " + a + " and " + b + ": screen " + a + "'s slots are on screen " + b + " now, and screen "
    + b + "'s on screen " + a + "."
}

// The screen p swaps the selected one (`key`) with: the next of `panes`
// (panes()), round from the last to the first; null with one screen.
function nextScreen(panes, key) {
  var list = panes || []
  if (list.length < 2) return null
  for (var i = 0; i < list.length; i++) {
    if (list[i].key === key) return list[(i + 1) % list.length].key
  }
  return null
}

// What letting screen `from`'s pane go over screen `to`'s does (`to`: null
// outside the panes): { kind: "swap", label } or { kind: "none" } (itself,
// outside, or a screen with no tree on either side).
function screenDropAction(drafts, from, to) {
  if (to === null || to === undefined || String(to) === String(from)) return { kind: "none" }
  var d = drafts || {}
  if (!d[from] || !d[from].node || !d[to] || !d[to].node) return { kind: "none" }
  return { kind: "swap", label: "Swap with screen " + to }
}

// The index of the pane under x in a row of panes (`panes`: [{ x, w }] left
// to right, `gap` between them): each pane its width and half the gap
// either side; -1 outside the row.
function paneAt(x, panes, gap) {
  var list = panes || []
  if (list.length === 0) return -1
  var last = list[list.length - 1]
  if (x < list[0].x || x >= last.x + last.w) return -1
  for (var i = 0; i < list.length; i++) if (x < list[i].x + list[i].w + gap / 2) return i
  return list.length - 1
}

// --- the panes on a desk of several monitors -----------------------------------

// A screen's size as the active desk's geometry has it (its monitor's
// logical box): { w, h }, or null when state has none for that screen.
function screenSize(state, screen) {
  var d = state && state.desks && state.desk ? state.desks[state.desk] : null
  var boxes = d && Array.isArray(d.geometry) ? d.geometry : []
  for (var i = 0; i < boxes.length; i++) {
    if (boxes[i].screen === screen && boxes[i].w > 0 && boxes[i].h > 0) return { w: boxes[i].w, h: boxes[i].h }
  }
  return null
}

// The Layout picture's panes laid out in `area` ({ w, h }: the row, and the
// height under the panes' titles), one per screen of `screens` ([{ key, w,
// h (the monitor's size; 1920 x 1080 when unknown), scroll (its tree is a
// filmstrip) }], left to right, `gap` between): every screen at one scale,
// so their sizes compare as the monitors' do, the largest that fits the
// width and the height (a scroll screen's label, `footer` high, under it),
// top-aligned. A scroll screen's pane is wider than its screen, the screen
// in the middle and the filmstrip either side, up to `span` (3) screens'
// widths: the screens shrink for it no further than `floor` (0.7) of the
// scale they would have without, and the scroll panes share what width is
// left. The row is centred across what is left after that. Returns {
// scale, panes: [{ key, x, w, h (the pane's picture: the screen, and a
// scroll screen's footer), screen: { x, y, w, h } (in the pane) }] }.
function paneLayout(screens, area, opts) {
  opts = opts || {}
  var list = screens || []
  if (list.length === 0) return { scale: 0, panes: [] }
  var gap = opts.gap || 0
  var span = opts.span >= 1 ? opts.span : 3
  var floor = opts.floor > 0 ? opts.floor : 0.7
  var footer = opts.footer || 0
  var sizes = list.map(function(s) {
    return { key: s.key, w: s.w > 0 ? s.w : 1920, h: s.h > 0 ? s.h : 1080, scroll: !!s.scroll }
  })
  var room = Math.max(0, area.w - gap * (sizes.length - 1))
  var sumW = 0
  var scrollW = 0
  var byHeight = Infinity
  sizes.forEach(function(s) {
    sumW += s.w
    if (s.scroll) scrollW += s.w
    byHeight = Math.min(byHeight, Math.max(0, area.h - (s.scroll ? footer : 0)) / s.h)
  })
  var tiles = Math.min(room / sumW, byHeight)
  var scale = tiles
  if (scrollW > 0) scale = Math.max(Math.min(room / (sumW + (span - 1) * scrollW), byHeight), floor * tiles)
  var boxes = sizes.map(function(s) { return { w: Math.floor(s.w * scale), h: Math.floor(s.h * scale) } })
  var used = boxes.reduce(function(sum, b) { return sum + b.w }, 0)
  var scrollUsed = sizes.reduce(function(sum, s, i) { return sum + (s.scroll ? boxes[i].w : 0) }, 0)
  var extra = Math.max(0, room - used)
  var panes = sizes.map(function(s, i) {
    var b = boxes[i]
    var w = b.w
    if (s.scroll && scrollUsed > 0) w += Math.min(Math.floor(extra * b.w / scrollUsed), Math.floor((span - 1) * b.w))
    return { key: s.key, x: 0, w: w, h: b.h + (s.scroll ? footer : 0),
      screen: { x: Math.floor((w - b.w) / 2), y: 0, w: b.w, h: b.h } }
  })
  var total = panes.reduce(function(sum, p) { return sum + p.w }, 0) + gap * (panes.length - 1)
  var x = Math.floor(Math.max(0, area.w - total) / 2)
  panes.forEach(function(p) {
    p.x = x
    x += p.w + gap
  })
  return { scale: scale, panes: panes }
}

// --- dragging a slot ----------------------------------------------------------

// A tile's edge band, as a share of the tile across that axis: a drop
// there puts the dragged slot beside the tile on that side; nearer the
// middle it swaps the two.
var EDGE_BAND = 0.25

// Where on tile `rect` ({ x, y, w, h }) the point x, y is: "centre", or the
// side ("left", "right", "up", "down") whose edge band holds it; in a corner
// the nearer edge, as a share of the tile.
function tileZone(rect, x, y) {
  var fx = rect.w > 0 ? (x - rect.x) / rect.w : 0.5
  var fy = rect.h > 0 ? (y - rect.y) / rect.h : 0.5
  var sides = [["left", fx], ["right", 1 - fx], ["up", fy], ["down", 1 - fy]]
  var best = sides[0]
  for (var i = 1; i < sides.length; i++) if (sides[i][1] < best[1]) best = sides[i]
  return best[1] < EDGE_BAND ? best[0] : "centre"
}

// The leaf (slot or other windows' place) of `rects` (rects()) under x, y,
// or null: a container's box is never one.
function leafAt(rects, x, y) {
  for (var i = 0; i < (rects || []).length; i++) {
    var r = rects[i]
    if ((r.kind === "slot" || r.kind === "overflow") && x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h) return r
  }
  return null
}

// The part of tile `rect` a drop in `zone` lights: the half on that side,
// the whole tile for the centre.
function zoneRect(rect, zone) {
  var hw = Math.round(rect.w / 2)
  var hh = Math.round(rect.h / 2)
  if (zone === "left") return { x: rect.x, y: rect.y, w: hw, h: rect.h }
  if (zone === "right") return { x: rect.x + rect.w - hw, y: rect.y, w: hw, h: rect.h }
  if (zone === "up") return { x: rect.x, y: rect.y, w: rect.w, h: hh }
  if (zone === "down") return { x: rect.x, y: rect.y + rect.h - hh, w: rect.w, h: hh }
  return { x: rect.x, y: rect.y, w: rect.w, h: rect.h }
}

// The gap between a filmstrip's columns (filmstrip().columns, in order)
// nearest x: 0 before the first, n after the last.
function stripGap(columns, x) {
  var gap = 0
  for (var i = 0; i < (columns || []).length; i++) if (columns[i].x + columns[i].w / 2 < x) gap = i + 1
  return gap
}

// Where gap `index` of a filmstrip is along it (its insertion marker's x).
function stripGapX(columns, index) {
  if (!columns || columns.length === 0) return 0
  if (index >= columns.length) return columns[columns.length - 1].x + columns[columns.length - 1].w
  return columns[Math.max(0, index)].x
}

// The leaf as a node of its own, its share kept or `weight`.
function leafNode(leaf, weight) {
  var out = { kind: leaf.kind, weight: weight === undefined ? leaf.weight : weight }
  if (leaf.kind === "slot") out.slot = leaf.slot
  return out
}

// The two leaves `a` and `b` of one tree trade places, each keeping its
// share (×n) as h/l's swap does. { node, changed } or { error }.
function swapLeaves(root, a, b) {
  var out = copy(root)
  if (a === b) return { node: out, changed: false }
  var pa = pathTo(out, a)
  var pb = pathTo(out, b)
  if (!pa || !pb) return { error: "There is no " + (pa ? b : a) + " in this tree." }
  var la = pa[pa.length - 1].node
  var lb = pb[pb.length - 1].node
  pa[pa.length - 2].node.children[pa[pa.length - 1].index] = lb
  pb[pb.length - 2].node.children[pb[pb.length - 1].index] = la
  return { node: out, changed: true }
}

// `leaf` (a node in no tree) put beside the leaf `target` of `root`, on
// `side`: along the target's split, a child beside it there (its share
// kept); across it, the target's tile split in two that way (the target's
// share the new split's); a tree of one tile becomes a split that way.
// { node } or { error }.
function placeBeside(root, leaf, target, side) {
  var out = copy(root)
  var path = pathTo(out, target)
  if (!path) return { error: "There is no " + target + " in this tree." }
  var axis = AXIS[side]
  var before = STEP[side] < 0
  if (path.length < 2) {
    var alone = leafNode(out, 1)
    var moved = leafNode(leaf, 1)
    return { node: rooted({ kind: axis, weight: 1, children: before ? [moved, alone] : [alone, moved] }) }
  }
  var parent = path[path.length - 2].node
  var index = path[path.length - 1].index
  if (axisOf(parent) === axis) {
    parent.children.splice(before ? index : index + 1, 0, copy(leaf))
    return { node: rooted(out) }
  }
  if (parent.kind === "scroll") return { error: SCROLL_SLOTS }
  var tile = parent.children[index]
  var mine = leafNode(leaf, 1)
  var theirs = leafNode(tile, 1)
  parent.children[index] = { kind: axis, weight: tile.weight, children: before ? [mine, theirs] : [theirs, mine] }
  return { node: rooted(out) }
}

// The leaf `key` dragged onto the `side` edge of the leaf `target` of the
// same tree: beside it there (placeBeside), out of where it was, which
// closes up. Next to the target in its split and dropped across it, the
// two are paired in a new split that way taking both their shares (HJKL's
// pair). { node, changed } or { error }.
function insertBeside(root, key, target, side) {
  if (key === target) return { node: copy(root), changed: false }
  var out = copy(root)
  var pk = pathTo(out, key)
  var pt = pathTo(out, target)
  if (!pk || !pt) return { error: "There is no " + (pk ? target : key) + " in this tree." }
  var axis = AXIS[side]
  var parent = pk.length > 1 ? pk[pk.length - 2].node : null
  var result
  if (parent && pt.length > 1 && pt[pt.length - 2].node === parent && axisOf(parent) !== axis) {
    if (parent.kind === "scroll") return { error: SCROLL_SLOTS }
    var leaf = pk[pk.length - 1].node
    var tile = pt[pt.length - 1].node
    var pair = { kind: axis, weight: leaf.weight + tile.weight, children: STEP[side] < 0 ? [leaf, tile] : [tile, leaf] }
    parent.children[pt[pt.length - 1].index] = pair
    parent.children.splice(pk[pk.length - 1].index, 1)
    result = { node: rooted(out) }
  } else {
    result = placeBeside(takeOut(out, key).node, pk[pk.length - 1].node, target, side)
    if (result.error) return result
  }
  return { node: result.node, changed: format(result.node) !== format(root) }
}

// The columns of a scroll tree as the picture shows them (picture: o's
// other windows or not), in order; null for a tree that is no filmstrip.
function stripKeys(node, showOther) {
  var shown = picture(node, showOther)
  return shown && shown.kind === "scroll" ? shown.children.map(keyOf) : null
}

// `leaf` (in no tree) into scroll tree `root` at gap `gap` of its shown
// columns (`keys`): before the column after the gap, else after the last.
// { node } or { error }.
function placeInStrip(root, leaf, keys, gap) {
  if (!keys || keys.length === 0) {
    var all = copy(root)
    all.children.push(copy(leaf))
    return { node: all }
  }
  return gap < keys.length ? placeBeside(root, leaf, keys[gap], "left")
    : placeBeside(root, leaf, keys[keys.length - 1], "right")
}

var OTHER_STAYS = "other windows stay on their screen: every screen's tree has its own place for them"

// What letting a dragged slot go does: `from` { screen, key } (the leaf
// dragged, "*" for other windows' place), `to` the place under the pointer
// on a pane: { screen, key, zone } a tile (tileZone: "centre" swaps the
// two, a side puts it beside the tile there), { screen, gap } a gap of a
// filmstrip (its shown columns', stripGap), { screen } a screen with no
// tree. On its own screen the tree is edited as the keys would (other
// windows' place written in first when it is either end); on another
// screen the slot leaves its tree (closing up) and lands in that one, a
// share of 1 (the keys' cross-screen move), or a centre drop trades the
// two slots between the screens. Other windows' place never leaves its
// screen, and a screen's only slot only goes in a trade. `opts`: {
// showOther (o: whether the picture shows other windows' place) }.
// { drafts, screen (where the slot is now), changed } or { error }.
function slotDrop(drafts, from, to, opts) {
  opts = opts || {}
  var a = String(from.screen)
  var b = String(to.screen)
  var src = drafts && drafts[a]
  if (!src || !src.node) return { error: "Screen " + a + " has no tree here." }
  var out = {}
  for (var k in drafts) out[k] = drafts[k]
  var key = from.key
  var result
  if (a === b) {
    var node = key === OVERFLOW || to.key === OVERFLOW ? withOther(src.node) : src.node
    if (to.gap !== undefined && to.gap !== null) {
      var keys = stripKeys(node, opts.showOther)
      if (!keys) return { error: "Screen " + a + "'s tree is no filmstrip." }
      var anchor = to.gap < keys.length ? keys[to.gap] : keys[keys.length - 1]
      if (anchor === key) return { drafts: out, screen: a, changed: false }
      var leaf = pathTo(node, key)
      if (!leaf) return { error: "There is no " + key + " in this tree." }
      var rest = takeOut(node, key).node
      result = placeInStrip(rest, leaf[leaf.length - 1].node, keys.filter(function(k2) { return k2 !== key }),
        to.gap > keys.indexOf(key) ? to.gap - 1 : to.gap)
    } else if (to.key === undefined || to.key === null) {
      return { drafts: out, screen: a, changed: false }
    } else if (to.zone === "centre") {
      result = swapLeaves(node, key, to.key)
    } else {
      result = insertBeside(node, key, to.key, to.zone)
    }
    if (result.error) return { error: result.error }
    if (format(result.node) === format(node)) return { drafts: out, screen: a, changed: false }
    out[a] = { node: result.node, base: src.base }
    return { drafts: out, screen: a, changed: true }
  }

  if (key === OVERFLOW || (to.key === OVERFLOW && to.zone === "centre")) return { error: OTHER_STAYS }
  var dst = drafts[b] || { node: null, base: null }
  var path = pathTo(src.node, key)
  if (!path) return { error: "There is no " + key + " in this tree." }
  var dragged = path[path.length - 1].node
  if (to.zone === "centre" && to.key !== undefined && to.key !== null) {
    if (!dst.node) return { error: "Screen " + b + " has no tree here." }
    var there = pathTo(dst.node, to.key)
    if (!there) return { error: "There is no " + to.key + " on screen " + b + "." }
    var theirs = there[there.length - 1].node
    var mine = copy(src.node)
    var yours = copy(dst.node)
    var pm = pathTo(mine, key)
    var py = pathTo(yours, to.key)
    if (pm.length < 2) mine = leafNode(theirs, 1)
    else pm[pm.length - 2].node.children[pm[pm.length - 1].index] = leafNode(theirs)
    if (py.length < 2) yours = leafNode(dragged, 1)
    else py[py.length - 2].node.children[py[py.length - 1].index] = leafNode(dragged)
    out[a] = { node: mine, base: src.base }
    out[b] = { node: yours, base: dst.base }
    return { drafts: out, screen: b, changed: true }
  }
  if (isLeaf(src.node)) return { error: key + " is the only window on this screen; moving it would leave the screen empty" }
  var moved = leafNode(dragged, 1)
  var landed
  if (!dst.node) {
    landed = { node: moved }
  } else if (to.gap !== undefined && to.gap !== null) {
    var strip = stripKeys(dst.node, opts.showOther)
    if (!strip) return { error: "Screen " + b + "'s tree is no filmstrip." }
    landed = placeInStrip(dst.node, moved, strip, to.gap)
  } else if (to.key === undefined || to.key === null) {
    return { error: "Let go on a tile of screen " + b + " to put " + key + " there." }
  } else {
    landed = placeBeside(to.key === OVERFLOW ? withOther(dst.node) : dst.node, moved, to.key, to.zone)
  }
  if (landed.error) return { error: landed.error }
  out[a] = { node: takeOut(src.node, key).node, base: src.base }
  out[b] = { node: landed.node, base: dst.base }
  return { drafts: out, screen: b, changed: true }
}

var SIDE_LABEL = { left: "Put left of ", right: "Put right of ", up: "Put above ", down: "Put below " }

function leafLabel(key) {
  return key === OVERFLOW ? "other windows" : key
}

// What letting go there does (slotDrop's arguments), for the ghost's label
// and the drop preview: { kind: "swap" | "insert", label } ("Swap with
// main", "Put left of main", "Put between side and chat", "Put on screen
// 2"), or { kind: "none" } where it changes nothing, with the `reason`
// when it is refused (said on letting go).
function slotDropAction(drafts, from, to, opts) {
  var result = slotDrop(drafts, from, to, opts)
  if (result.error) return { kind: "none", reason: result.error }
  if (!result.changed) return { kind: "none" }
  if (to.gap !== undefined && to.gap !== null) {
    // the columns either side of the gap, the dragged one (when it is in
    // this strip) left out
    var shown = stripKeys(drafts[String(to.screen)].node, (opts || {}).showOther) || []
    var at = String(to.screen) === String(from.screen) ? shown.indexOf(from.key) : -1
    var keys = shown.filter(function(k) { return k !== from.key })
    var gap = at >= 0 && to.gap > at ? to.gap - 1 : to.gap
    var left = gap > 0 ? keys[gap - 1] : null
    var right = gap < keys.length ? keys[gap] : null
    var label = left && right ? "Put between " + leafLabel(left) + " and " + leafLabel(right)
      : right ? "Put before " + leafLabel(right) : "Put after " + leafLabel(left)
    return { kind: "insert", label: label }
  }
  if (to.key === undefined || to.key === null) return { kind: "insert", label: "Put on screen " + to.screen }
  if (to.zone === "centre") return { kind: "swap", label: "Swap with " + leafLabel(to.key) }
  return { kind: "insert", label: SIDE_LABEL[to.zone] + leafLabel(to.key) }
}

// The slot `key` taken out of a tree, tidied ({ node: null } when it was
// all of it): an edited draft following the slot list's delete. Never the
// place for other windows. { node } or { error }.
function removeSlot(root, key) {
  if (key === OVERFLOW) return { error: "other windows always have a place in the tree: o only hides it from the picture" }
  if (isLeaf(root)) return { node: null }
  return { node: takeOut(root, key).node }
}

// The tree with `slots` added as tree.append adds the global slots a tree
// lacks: new children at the end of its root split (a tree that is one leaf
// becomes h[leaf, ...]), or a scroll branch's last columns, before a
// trailing * (other windows stay the last column).
function appendSlots(root, slots) {
  if (!slots || slots.length === 0) return copy(root)
  var out
  if (isLeaf(root)) {
    var leaf = copy(root)
    leaf.weight = 1
    out = { kind: "h", weight: root.weight || 1, children: [leaf] }
  } else {
    out = copy(root)
  }
  var at = out.children.length
  if (out.kind === "scroll" && out.children[at - 1].kind === "overflow") at--
  slots.forEach(function(slot) {
    out.children.splice(at, 0, { kind: "slot", slot: slot, weight: 1 })
    at++
  })
  return out
}

// The drafts (screen key -> { node, base }) after the slot list made slot
// `slot`, which the engine puts into every tree: an edited draft gets it
// (appendSlots) when its screen's tree in force (`panes`, as panes() reads
// the state) has it now; the others take the engine's trees on the re-read.
function followNewSlot(drafts, panes, slot) {
  var out = {}
  for (var k in drafts) out[k] = drafts[k]
  ;(panes || []).forEach(function(p) {
    var d = out[p.key]
    if (!d || !d.node || format(d.node) === d.base || leaves(d.node).indexOf(slot) >= 0 || p.tree === null) return
    var inForce = parse(p.tree)
    if (inForce.node && leaves(inForce.node).indexOf(slot) >= 0) out[p.key] = { node: appendSlots(d.node, [slot]), base: d.base }
  })
  return out
}

// The screen key whose draft places slot `slot` (drafts: "1" -> { node }),
// or null: a slot sits on one screen of a workspace.
function placedIn(drafts, slot) {
  if (slot === OVERFLOW) return null
  for (var screen in drafts || {}) {
    var d = drafts[screen]
    if (d && d.node && leaves(d.node).indexOf(slot) >= 0) return screen
  }
  return null
}

// The tree with slot `from` called `to` (the slot list's rename, carried
// into an edited draft as the engine's rename_slot rewrites the trees).
function renameSlot(root, from, to) {
  var out = copy(root)
  ;(function walk(n) {
    if (n.kind === "slot" && n.slot === from) n.slot = to
    if (n.children) n.children.forEach(walk)
  })(out)
  return out
}

// --- the view's model -------------------------------------------------------

function layoutEntry(state, layout) {
  return state && state.layouts && layout ? state.layouts[layout] || null : null
}

// The trees of one workspace of a layout (or its default trees, workspace
// "default"), one pane per screen 1..N: { screen, key (its drafts key, "1"),
// tree (the text it shows, or null when there is none on that screen),
// ratio, resized, connector (the active desk's monitor at that position,
// "" when none) }. A workspace with no trees of its own shows the default
// ones, as the state reports.
function panes(state, layout, workspace) {
  var entry = layoutEntry(state, layout)
  if (!entry) return []
  var branches = workspace === "default" ? entry.default || {} : (entry.workspaces || {})[String(workspace)] || {}
  var screens = state && Array.isArray(state.screens) ? state.screens : []
  var out = []
  for (var i = 1; i <= (entry.screens || 0); i++) {
    var branch = branches[String(i)]
    out.push({ screen: i, key: String(i), tree: branch ? branch.tree : null, ratio: branch ? branch.ratio || "" : "",
      resized: !!(branch && branch.resized), connector: screens[i - 1] || "" })
  }
  return out
}

// A pane's title: the screen number and the display name of the active
// desk's monitor there ("Screen 1 · Built-in"), its connector from an
// engine that names none.
function screenLabel(state, screen) {
  var connector = state && Array.isArray(state.screens) ? state.screens[screen - 1] : null
  if (!connector) return "Screen " + screen
  var list = state && Array.isArray(state.monitors) ? state.monitors : []
  var display = connector
  for (var i = 0; i < list.length; i++) if (list[i].name === connector && list[i].display) display = list[i].display
  return "Screen " + screen + " · " + display
}

// Whether a workspace has trees of its own in a layout (an override of the
// shared ones); "default", the shared trees themselves, has none.
function hasOwn(state, layout, workspace) {
  var entry = layoutEntry(state, layout)
  if (!entry || workspace === "default") return false
  var own = Array.isArray(entry.own) ? entry.own : []
  return own.indexOf(workspace) >= 0 || own.indexOf(String(workspace)) >= 0
}

// What the header says of a workspace that uses the shared trees (none of
// its own), and whom its edits are for once asked (`scope`: "all" edits
// the shared trees, "only" gives it its own on apply).
function defaultNote(state, layout, workspace, scope) {
  if (!layoutEntry(state, layout) || workspace === "default" || hasOwn(state, layout, workspace)) return ""
  if (scope === "all") return "(uses the shared tree: editing it for all workspaces)"
  if (scope === "only") return "(uses the shared tree: w gives workspace " + workspace + " its own)"
  return "(uses the shared tree)"
}

// Whether an edit on `workspace` asks first whom it is for: a workspace on
// the shared trees, not asked yet (`scope` "").
function needsScope(state, layout, workspace, scope) {
  return workspace !== "default" && !scope && !!layoutEntry(state, layout) && !hasOwn(state, layout, workspace)
}

// The question its first edit asks, for Prompts.choice(label, options,
// { inline: true }).
function scopeQuestion(workspace) {
  return {
    label: "Apply to (a)ll workspaces or (o)nly workspace " + workspace + "?",
    options: [{ key: "a", label: "all workspaces", value: "all" }, { key: "o", label: "only workspace " + workspace, value: "only" }],
  }
}

// The workspace an edit goes to: the shared trees ("default") for all
// workspaces, else the one shown.
function editTarget(workspace, scope) {
  return scope === "all" ? "default" : workspace
}

// Where the view opens: the focused workspace's number and screen, else the
// first used workspace on screen 1.
function initialTarget(state, workspaceId) {
  var ws = state && state.workspaces ? state.workspaces[String(workspaceId)] : null
  if (ws && ws.workspace) return { workspace: ws.workspace, screen: ws.screen || 1 }
  var used = state && Array.isArray(state.used_workspaces) ? state.used_workspaces : []
  return { workspace: used.length ? used[0] : 1, screen: 1 }
}

// Why the trees of a layout may not be edited, "" when they may.
function editBlock(state, layout) {
  if (!state) return "no state from hyprslots yet"
  if (state.refused) return "hyprslots is off: " + state.refused
  if (!state.config || !state.config.editable) {
    return "your config loads no editor data, so there is nothing the editor may change"
  }
  if (!layout) return "no desk is active: these monitors have none yet"
  var entry = layoutEntry(state, layout)
  if (!entry) return "no layout '" + layout + "'"
  if (entry.read_only) return "layout '" + layout + "' is set by code in your config; edit it there"
  return ""
}

// slot -> title of the window in it, for a workspace's screen.
function titles(state, workspace, screen) {
  var out = {}
  var windows = state && Array.isArray(state.windows) ? state.windows : []
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i]
    if (w.workspace !== workspace || !w.slot) continue
    var ws = state.workspaces ? state.workspaces[String(w.workspace_id)] : null
    if (screen && ws && ws.screen !== screen) continue
    if (out[w.slot] === undefined) out[w.slot] = w.title || ""
  }
  return out
}

function containerLabel(node) {
  return node.kind + " " + integers(node.children.map(function(c) { return c.weight })).join(":")
}

// The picture of a tree laid over `area`, as rectangles in drawing order:
//   { kind: "slot" | "overflow" | "h" | "v", key?, x, y, w, h, depth, label,
//     title?, selected? }
// Boxes are proportional to the weights in whole pixels (tree.lua's
// arithmetic: the remainder goes to the last child). A nested container is a
// box titled with its kind and ratio, its children inset by `pad` (and
// `title` more at the top). For tiles: a scroll tree is a filmstrip.
// opts: { pad, title, selected, titles }.
function rects(root, area, opts) {
  return laidOut(root, area, opts).rects
}

// The boundaries between neighbouring children of the tiled splits of the
// picture `rects` draws (same area and opts), each a divider the mouse
// drags (dragDivider):
//   { id ("<last leaf before>|<first leaf after>"), axis (the split's kind:
//     "h" parts left from right), x, y, length (the boundary as a line from
//     x, y, down for "h", across for "v"), at (where it is along the axis),
//     start, end (the two neighbours' extent along the axis), before, after
//     (the leaves of the two neighbours), split (the leaves of the whole
//     split), depth (1: the root's) }
// None on a scroll tree or a single window.
function dividers(root, area, opts) {
  return laidOut(root, area, opts).dividers
}

// The divider under the pointer at x, y: within `slop` pixels of its line,
// along its length; the nearest, a deeper one on a tie. null for none.
function dividerAt(list, x, y, slop) {
  var best = null
  var bestOff = Infinity
  for (var i = 0; i < list.length; i++) {
    var d = list[i]
    var along = d.axis === "h" ? y - d.y : x - d.x
    if (along < 0 || along > d.length) continue
    var off = Math.abs((d.axis === "h" ? x : y) - d.at)
    if (off > slop) continue
    if (off < bestOff || (off === bestOff && d.depth > best.depth)) {
      best = d
      bestOff = off
    }
  }
  return best
}

// Where `pos` (along the divider's axis) puts it: the share of the two
// neighbours' extent before it, 0 to 1.
function dividerFraction(divider, pos) {
  var span = divider.end - divider.start
  if (span <= 0) return 0.5
  return Math.max(0, Math.min(1, (pos - divider.start) / span))
}

// --- dragging a divider -------------------------------------------------------

// A drag snaps the whole split to an allowed arrangement: every child a
// whole weight 1 to MAX_WEIGHT, divided by their gcd (2 children: 19
// arrangements, 3: 115, 4: 607). Anchored to where the split's dividers
// were when the drag started, never where the drag has had them since:
//   1. of the arrangements keeping every other divider exactly where it
//      started, the one putting the dragged divider nearest the pointer,
//      if within SNAP_TOLERANCE of the split;
//   2. else the one minimising 3 × the dragged divider's distance from the
//      pointer plus every other divider's from where it started.
// Back where it started, an allowed split is what it was. A typed ratio may
// be any whole one; dragging it moves to the nearest allowed arrangement.
// No child drops below 1/MIN_SHARE of the split (tree.lua's nudge minimum,
// 5%): with up to four children every arrangement keeps that (the least
// share is 1/16); with five or six, arrangements that would not are left
// out. A split of more than MAX_SNAPPED children (whose arrangements grow
// past 5^7) snaps only the dragged divider's two neighbours, the same way,
// as a pair of 1 to 5 (neither below 5% of the split); the others keep
// their size.
var MAX_WEIGHT = 5
var SNAP_TOLERANCE = 0.03
var MIN_SHARE = 20
var MAX_SNAPPED = 6
var arranged = {}

// The allowed arrangements of `n` children (above), each a list of weights;
// computed once per n.
function arrangements(n) {
  if (arranged[n]) return arranged[n]
  var out = []
  var t = []
  var fill = function(i, sum) {
    if (i === n) {
      var common = t.reduce(function(g, w) { return gcd(g, w) }, 0)
      if (common === 1 && t.every(function(w) { return MIN_SHARE * w >= sum })) out.push(t.slice())
      return
    }
    for (var w = 1; w <= MAX_WEIGHT; w++) {
      t[i] = w
      fill(i + 1, sum + w)
    }
  }
  fill(0, 0)
  arranged[n] = out
  return out
}

// The dividers of weights `t`: where each falls, as a share of the split.
function cumulative(t) {
  var total = t.reduce(function(s, w) { return s + w }, 0)
  var at = 0
  return t.slice(0, -1).map(function(w) { return (at += w) / total })
}

// The arrangement of `list` for divider `k` moved to `target` (a share of
// the split) from dividers at `start` (cumulative), the rest anchored
// there (above).
function snapSplit(list, start, k, target) {
  var kept = null
  var keptOff = Infinity
  var best = null
  var bestScore = Infinity
  for (var i = 0; i < list.length; i++) {
    var p = cumulative(list[i])
    var off = Math.abs(p[k] - target)
    var moved = 0
    var stays = true
    for (var j = 0; j < p.length; j++) {
      if (j === k) continue
      var d = Math.abs(p[j] - start[j])
      if (d >= 1e-9) stays = false
      moved += d
    }
    if (stays && off < keptOff) {
      kept = list[i]
      keptOff = off
    }
    if (3 * off + moved < bestScore) {
      best = list[i]
      bestScore = 3 * off + moved
    }
  }
  return kept && keptOff <= SNAP_TOLERANCE ? kept : best
}

var DIVIDER_GONE = "That divider is not in the tree any more."

// A divider of the picture (dividers) let go at `fraction` of its two
// neighbours (dividerFraction), on the draft the drag started on: the
// split's children in the picture snap to an allowed arrangement
// (snapSplit), anchored to where the draft has them, and the split's
// weights are divided by their gcd. The divider names its neighbours by
// their leaves, so it finds them in the draft whatever the picture left
// out: other windows' place hidden from it keeps its size, out of the
// arrangement; a divider next to that place where the engine puts it (o)
// writes it into the tree, as moving it does. { node, changed, label (the
// split's ratio, "2 : 1 : 1") } or { error }; the draft given is never
// changed. A null `fraction` (held, not moved yet) changes nothing.
function dragDivider(draft, divider, fraction) {
  var keys = divider.before.concat(divider.after)
  var own = leaves(draft)
  var base = keys.every(function(k) { return own.indexOf(k) >= 0 }) ? draft : withOther(draft)
  var paths = keys.map(function(k) { return pathTo(base, k) })
  if (paths.some(function(p) { return !p })) return { error: DIVIDER_GONE }
  // the split: the deepest node every neighbour's leaf is under
  var depth = 0
  while (paths.every(function(p) { return p.length > depth + 1 && p[depth + 1].node === paths[0][depth + 1].node })) depth++
  var split = paths[0][depth].node
  if (isLeaf(split) || split.kind !== divider.axis) return { error: DIVIDER_GONE }
  var side = split.children.map(function() { return 0 })
  paths.forEach(function(p, i) { side[p[depth + 1].index] |= i < divider.before.length ? 1 : 2 })
  if (side.indexOf(3) >= 0 || side.indexOf(1) < 0 || side.indexOf(2) < 0) return { error: DIVIDER_GONE }
  // the children the picture draws (a child with none of its leaves in the
  // picture's split is other windows' hidden place)
  var drawn = split.children.map(function(c, i) {
    return side[i] !== 0 || leaves(c).some(function(k) { return divider.split.indexOf(k) >= 0 })
  })

  var old = split.children.map(function(c) { return c.weight })
  var reduced = function(list) {
    var common = list.reduce(function(g, w) { return gcd(g, w) }, 0)
    return list.map(function(w) { return w / common })
  }
  var label = function(list) { return reduced(list).join(" : ") }
  var unchanged = { node: draft, changed: false, label: label(old) }
  if (fraction === null || fraction === undefined) return unchanged

  var units = []
  old.forEach(function(w, i) { if (drawn[i]) units.push(i) })
  var shown = units.map(function(i) { return old[i] })
  var k = -1
  units.forEach(function(i, u) { if (side[i] === 1) k = u })
  if (k < 0 || k + 1 >= units.length || side[units[k + 1]] !== 2) return { error: DIVIDER_GONE }
  var snapped
  if (units.length <= MAX_SNAPPED) {
    var total = shown.reduce(function(s, w) { return s + w }, 0)
    var upTo = shown.slice(0, k).reduce(function(s, w) { return s + w }, 0)
    var target = (upTo + fraction * (shown[k] + shown[k + 1])) / total
    snapped = snapSplit(arrangements(units.length), cumulative(shown), k, target)
  } else {
    // the two neighbours as a pair of 1 to 5, neither below 5% of the split
    var pair = shown[k] + shown[k + 1]
    var all = old.reduce(function(s, w) { return s + w }, 0)
    var pairs = arrangements(2).filter(function(t) {
      return MIN_SHARE * t[0] * pair >= (t[0] + t[1]) * all && MIN_SHARE * t[1] * pair >= (t[0] + t[1]) * all
    })
    var ab = snapSplit(pairs, [shown[k] / pair], 0, fraction)
    // over a common denominator: the pair comes to a : b of its total, the
    // rest keeps its share
    snapped = shown.map(function(w, u) {
      if (u === k) return ab[0] * pair
      if (u === k + 1) return ab[1] * pair
      return w * (ab[0] + ab[1])
    })
  }
  // the drawn children come to the arrangement, keeping their share of the
  // split; a hidden place keeps its own
  var drawnTotal = shown.reduce(function(s, w) { return s + w }, 0)
  var snappedTotal = snapped.reduce(function(s, w) { return s + w }, 0)
  var u = 0
  var weights = reduced(old.map(function(w, i) { return drawn[i] ? snapped[u++] * drawnTotal : w * snappedTotal }))
  var before = reduced(old)
  if (weights.every(function(w, i) { return w === before[i] })) return unchanged

  var out = copy(base)
  var target2 = out
  for (var d = 1; d <= depth; d++) target2 = target2.children[paths[0][d].index]
  target2.children.forEach(function(c, i) { c.weight = weights[i] })
  return { node: out, changed: true, label: weights.join(" : ") }
}

function laidOut(root, area, opts) {
  opts = opts || {}
  var pad = opts.pad || 0
  var titleHeight = opts.title || 0
  var out = []
  var bounds = []

  function leaf(node, box, depth, cell) {
    var key = keyOf(node)
    var label = node.kind === "overflow" ? "other windows" : node.slot
    if (cell !== undefined && cell !== 1) label += " ×" + cell
    var r = { kind: node.kind, key: key, x: box.x, y: box.y, w: box.w, h: box.h, depth: depth, label: label,
      selected: key === opts.selected }
    if (opts.titles && opts.titles[key]) r.title = opts.titles[key]
    out.push(r)
  }

  function inside(node, box, depth) {
    var total = node.children.reduce(function(s, c) { return s + c.weight }, 0)
    var cells = integers(node.children.map(function(c) { return c.weight }))
    var across = node.kind === "h"
    var extent = across ? box.w : box.h
    var origin = across ? box.x : box.y
    var offset2 = 0
    var spans = node.children.map(function(child, i) {
      var size = i === node.children.length - 1 ? extent - offset2 : Math.floor(extent * child.weight / total)
      var span = { start: origin + offset2, end: origin + offset2 + size }
      offset2 += size
      return span
    })
    // a split's own dividers before those inside its children
    if (node.kind === "h" || node.kind === "v") {
      for (var i = 0; i + 1 < node.children.length; i++) {
        var before = leaves(node.children[i])
        var after = leaves(node.children[i + 1])
        var at = spans[i + 1].start
        bounds.push({ id: before[before.length - 1] + "|" + after[0], axis: node.kind,
          x: across ? at : box.x, y: across ? box.y : at, length: across ? box.h : box.w, at: at,
          start: spans[i].start, end: spans[i + 1].end, before: before, after: after, split: leaves(node), depth: depth })
      }
    }
    node.children.forEach(function(child, i) {
      var size = spans[i].end - spans[i].start
      var childBox = across
        ? { x: spans[i].start, y: box.y, w: size, h: box.h }
        : { x: box.x, y: spans[i].start, w: box.w, h: size }
      place(child, childBox, depth, cells[i])
    })
  }

  function place(node, box, depth, cell) {
    if (isLeaf(node)) {
      leaf(node, box, depth, cell)
      return
    }
    out.push({ kind: node.kind, x: box.x, y: box.y, w: box.w, h: box.h, depth: depth,
      label: containerLabel(node) + (cell !== undefined && cell !== 1 ? "  ×" + cell : "") })
    inside(node, { x: box.x + pad, y: box.y + pad + titleHeight, w: Math.max(0, box.w - 2 * pad),
      h: Math.max(0, box.h - 2 * pad - titleHeight) }, depth + 1)
  }

  if (isLeaf(root)) leaf(root, area, 0)
  else inside(root, area, 1)
  return { rects: out, dividers: bounds }
}

// The picture of a scroll tree: a filmstrip. Its columns stand in slot
// order, each its `width` of the SCREEN (half, full, ...), and the screen is
// a viewport over the strip, scrolled the least that shows the selected
// column (none selected: the strip starts at the screen's left edge), as
// Hyprland's scrolling layout brings the focused column into view. The
// viewport is the largest box of the screen's `aspect` that is at most
// 1/`span` of the area's width and fits its height, centred in the area:
// with span 3, about a screen's width of the strip shows on each side of
// it, where the columns beyond the screen are. Returns { label
// (modeLabel), viewport: { x, y, w, h }, columns: [{ kind, key, label,
// title?, x, y, w, h, selected, visible (how much of it is on the screen, 0
// to 1) }] }.
// opts: { aspect (screen width / height), span (screen widths across the
// area, default 1), selected, titles }.
function filmstrip(root, area, opts) {
  opts = opts || {}
  var aspect = opts.aspect > 0 ? opts.aspect : 16 / 9
  var span = opts.span >= 1 ? opts.span : 1
  var vw = Math.floor(Math.min(area.w / span, area.h * aspect))
  var vh = Math.floor(vw / aspect)
  var viewport = { x: area.x + Math.floor((area.w - vw) / 2), y: area.y + Math.floor((area.h - vh) / 2), w: vw, h: vh }
  var cw = Math.round(vw * (root.width || 1))
  var keys = root.children.map(keyOf)
  var at = keys.indexOf(opts.selected)
  var offset = at >= 0 ? Math.max(0, (at + 1) * cw - vw) : 0
  var columns = root.children.map(function(child, i) {
    var key = keyOf(child)
    var x = viewport.x + i * cw - offset
    var shown = Math.max(0, Math.min(x + cw, viewport.x + vw) - Math.max(x, viewport.x))
    var c = { kind: child.kind, key: key, label: child.kind === "overflow" ? "other windows" : child.slot,
      x: x, y: viewport.y, w: cw, h: vh, selected: key === opts.selected, visible: cw > 0 ? shown / cw : 0 }
    if (opts.titles && opts.titles[key]) c.title = opts.titles[key]
    return c
  })
  return { label: modeLabel(root), viewport: viewport, columns: columns }
}

// The Assignment view's mini-map of a tree (its text, as state has it) on
// one screen, in a box `size` { w, h } pixels, the slot `slot` lit,
// without the place for other windows (picture, no o). { kind: "tiles" |
// "scroll" | "none", screen: { x, y, w, h } (where the screen is in the
// box), tiles: [{ kind, key, x, y, w, h, selected, visible? }] }:
//   tiles   the Layout picture's own geometry at thumbnail size (rects, no
//           padding or titles): the leaves, filling the box, the screen
//   scroll  the whole strip across the box (a strip shorter than a screen
//           from its left), each column its `width` of a screen and the
//           box's height (a scroll tree's columns are the screen's height,
//           so the height says nothing and the strip gets it all); the
//           screen where Hyprland scrolls to show the slot's column (the
//           least, as filmstrip), `visible` how much of each column it shows
//   none    no tree, or one that does not parse
function miniMap(text, slot, size) {
  var none = { kind: "none", screen: null, tiles: [] }
  if (!text) return none
  var parsed = parse(String(text))
  if (!parsed.node) return none
  var node = picture(parsed.node, false)
  var area = { x: 0, y: 0, w: size.w, h: size.h }
  if (node.kind === "scroll") return miniStrip(node, slot, area)
  var leavesOnly = rects(node, area, { selected: slot }).filter(function(r) { return r.kind === "slot" || r.kind === "overflow" })
  return { kind: "tiles", screen: area, tiles: leavesOnly.map(function(r) {
    return { kind: r.kind, key: r.key, x: r.x, y: r.y, w: r.w, h: r.h, selected: r.selected }
  }) }
}

function miniStrip(node, slot, area) {
  var fraction = node.width || 1
  var count = node.children.length
  // screens the strip spans, at least the one it is shown on
  var screens = Math.max(1, count * fraction)
  var perScreen = area.w / screens
  var column = perScreen * fraction
  var sw = Math.round(perScreen)
  var keys = node.children.map(keyOf)
  var at = keys.indexOf(slot)
  var offset = at >= 0 ? Math.round(Math.max(0, (at + 1) * column - perScreen)) : 0
  var screen = { x: area.x + offset, y: area.y, w: sw, h: area.h }
  var tiles = node.children.map(function(child, i) {
    var x = Math.round(i * column)
    var w = Math.round((i + 1) * column) - x
    var shown = Math.max(0, Math.min(x + w, offset + sw) - Math.max(x, offset))
    return { kind: child.kind, key: keys[i], x: area.x + x, y: area.y, w: w, h: area.h, selected: keys[i] === slot,
      visible: w > 0 ? shown / w : 0 }
  })
  return { kind: "scroll", screen: screen, tiles: tiles }
}

// A mini-map's size: the screen's shape (`aspect`, width / height; 16:9 for
// an unknown one), as large as fits `maxW` x `maxH`.
function miniMapSize(aspect, maxW, maxH) {
  var a = aspect > 0 ? aspect : 16 / 9
  var w = Math.min(maxW, Math.round(maxH * a))
  return { w: w, h: Math.min(maxH, Math.round(w / a)) }
}

// The ratio prompt for a tree (aerolayout's [r]): { text } or { error } when
// there is nothing a ratio could divide.
function ratioPrompt(root) {
  if (isLeaf(root)) return { error: "Nothing to divide — this layout is one window." }
  if (root.kind === "scroll") {
    var mode = scrollMode(root)
    var width = mode === "other" ? Math.round(root.width * 100) + "%" : mode
    return { error: "Ratios are for tiles: each column of a scroll tree is a set width of the screen (" + width
      + " here). t cycles to tiles." }
  }
  var current = ratio(root)
  var hints = ["current " + current, "empty clears all"]
  return { text: "Ratios for the whole tree (" + hints.join("; ") + ") [Enter] set  [Esc] cancel: " }
}

// --- the help rows (Help.row groups): each one line at the panel's width ----

function workspaceHelp(jumpKeys) {
  return [[{ key: "[ ] " + jumpKeys + " -", label: "workspace" }], [{ key: "Tab", label: "view" }]]
}

// The picture's keys. opts: { node (the selected pane's draft: t names
// what it makes of it, / and r show on tiles only), hasOwn (the workspace
// has trees of its own: u), jumpKeys (Workspaces.jumpKeys), readOnly (the
// layout takes no edit), edited (a pane has unapplied edits: w), workspace
// ("default": R records a workspace, not the shared trees), screens (the
// layout's screen count: p, swap with the next, on more than one) }. A key the
// picture would refuse now is marked `enabled: false` (the toolbar dims it).
function pictureHelp(opts) {
  var tiles = scrollMode(opts.node) === "tiles"
  var ro = !!opts.readOnly
  var edits = !ro && !!opts.node
  var off = function(item, on) {
    if (!on) item.enabled = false
    return item
  }
  var tree = [{ key: "←↑↓→", label: "select" }, off({ key: "hjkl/HJKL", label: "move" }, edits)]
  if (tiles) tree.push(off({ key: "/", label: "flip" }, edits))
  tree.push(off({ key: "t", label: cycleLabel(opts.node), before: true }, edits))
  if (tiles) tree.push(off({ key: "r", label: "ratios" }, edits))
  if ((opts.screens || 0) > 1) tree.push(off({ key: "p", label: "swap" }, edits))
  tree.push({ key: "o", label: "others" })
  var layout = [off({ key: "w", label: "apply" }, !ro && opts.edited !== false), off({ key: "d", label: "revert" }, !ro),
    off({ key: "R", label: "record" }, !ro && opts.workspace !== "default")]
  if (opts.hasOwn) layout.push(off({ key: "u", label: "use shared" }, !ro))
  return [tree, layout, [{ key: "s", label: "slots" }]].concat(workspaceHelp(opts.jumpKeys))
}

// The slot list's keys. opts: { jumpKeys, readOnly (the slots are code's),
// hasSlot (there is a slot to act on) }; what it would refuse is marked
// `enabled: false`.
function slotListHelp(opts) {
  var ro = !!opts.readOnly
  var one = opts.hasSlot !== false
  var off = function(item, on) {
    if (!on) item.enabled = false
    return item
  }
  return [
    [{ key: "↑/↓", label: "select" }, off({ key: "a", label: "add" }, !ro), off({ key: "r", label: "rename" }, !ro && one),
      off({ key: "e", label: "describe" }, !ro && one), off({ key: "K", label: "key" }, !ro && one),
      off({ key: "d", label: "delete" }, !ro && one), off({ key: "Return", label: "show in the picture" }, one)],
    [{ key: "s/Esc", label: "back" }],
  ].concat(workspaceHelp(opts.jumpKeys))
}

// --- d: revert ------------------------------------------------------------------

function treeName(workspace, screen) {
  return (workspace === "default" ? "the shared tree" : "workspace " + workspace + "'s tree") + " on screen " + screen
}

// The y/n d asks: the tree of `workspace` ("default": the shared tree) on
// `screen` back to how it was last saved (api reset), its draft and its
// applied but unsaved edits gone.
function revertQuestion(workspace, screen) {
  return "Revert " + treeName(workspace, screen) + " to how it was last saved? Its unsaved edits go."
}

function revertedText(workspace, screen, tree) {
  return "Reverted " + treeName(workspace, screen) + ": " + (tree || "no tree") + "."
}
