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

// /: every split turned the other way (flip_tree).
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

// A pane's title: the screen number and the active desk's monitor there.
function screenLabel(state, screen) {
  var connector = state && Array.isArray(state.screens) ? state.screens[screen - 1] : null
  if (!connector) return "Screen " + screen
  var list = state && Array.isArray(state.monitors) ? state.monitors : []
  var description = ""
  for (var i = 0; i < list.length; i++) if (list[i].name === connector) description = list[i].description || ""
  return "Screen " + screen + " · " + connector + (description ? " (" + description + ")" : "")
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
  opts = opts || {}
  var pad = opts.pad || 0
  var titleHeight = opts.title || 0
  var out = []

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
    var extent = node.kind === "h" ? box.w : box.h
    var offset2 = 0
    node.children.forEach(function(child, i) {
      var size = i === node.children.length - 1 ? extent - offset2 : Math.floor(extent * child.weight / total)
      var childBox = node.kind === "h"
        ? { x: box.x + offset2, y: box.y, w: size, h: box.h }
        : { x: box.x, y: box.y + offset2, w: box.w, h: size }
      offset2 += size
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
  return out
}

// The picture of a scroll tree: a filmstrip. Its columns stand in slot
// order, each its `width` of the SCREEN (half, full, ...), and the screen is
// a viewport over the strip, scrolled the least that shows the selected
// column (none selected: the strip starts at the screen's left edge), as
// Hyprland's scrolling layout brings the focused column into view. The
// viewport is the largest box of the screen's `aspect` in `area` that
// leaves `peek` of the area's width free on each side, where the columns
// beyond the screen show. Returns { label (modeLabel), viewport: { x, y, w,
// h }, columns: [{ kind, key, label, title?, x, y, w, h, selected, visible
// (how much of it is on the screen, 0 to 1) }] }.
// opts: { aspect (screen width / height), peek, selected, titles }.
function filmstrip(root, area, opts) {
  opts = opts || {}
  var aspect = opts.aspect > 0 ? opts.aspect : 16 / 9
  var peek = opts.peek || 0
  var vw = Math.floor(Math.min(area.w * (1 - 2 * peek), area.h * aspect))
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
// what it makes of it, r shows on tiles only), hasOwn (the workspace has
// trees of its own: u), jumpKeys (Workspaces.jumpKeys) }.
function pictureHelp(opts) {
  var tiles = scrollMode(opts.node) === "tiles"
  var tree = [{ key: "←↑↓→", label: "select" }, { key: "hjkl/HJKL", label: "move" }, { key: "/", label: "flip" },
    { key: "t", label: cycleLabel(opts.node), before: true }]
  if (tiles) tree.push({ key: "r", label: "ratios" })
  tree.push({ key: "o", label: "other windows" })
  var layout = [{ key: "w", label: "apply" }, { key: "d", label: "revert" }, { key: "R", label: "record" }]
  if (opts.hasOwn) layout.push({ key: "u", label: "use shared" })
  return [tree, layout, [{ key: "s", label: "slots" }]].concat(workspaceHelp(opts.jumpKeys))
}

// The slot list's keys. opts: { jumpKeys }.
function slotListHelp(opts) {
  return [
    [{ key: "↑/↓", label: "select" }, { key: "a", label: "add" }, { key: "r", label: "rename" },
      { key: "e", label: "describe" }, { key: "d", label: "delete" }, { key: "Return", label: "show in the picture" }],
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
