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
//   { kind: "scroll", weight, children, was? }  a scroll branch: the whole
//                                           tree, slots only, full-width
//                                           scrolling columns in order; `was`
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
        return { kind: "scroll", children: children(member("scroll[...]", true), "columns of scroll[...] take no weight (each is full width)") }
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
  return node.kind + "[" + parts.join(", ") + "]"
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

var SCROLL_SLOTS = "a scroll branch holds slots only (full-width columns in order); press t for tiles first"

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

// t: the whole tree as a scroll branch, its leaves in reading order as
// full-width scrolling columns (the overflow leaf as the column windows with
// no slot take), or a scroll branch back to the tree it was made from when
// its columns are as they were, else its columns side by side.
// { node } or { error }.
function toggleScroll(root) {
  if (root.kind === "scroll") {
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
    kind: "scroll", weight: 1,
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

// a: slot `slot` added right after the leaf `key` in its container (a
// tree that is one leaf becomes h[leaf, slot]; no tree at all, `root` null,
// becomes the slot alone). { node } or { error }.
function addSlot(root, key, slot) {
  var leaf = { kind: "slot", slot: slot, weight: 1 }
  if (!root) return { node: leaf }
  if (leaves(root).indexOf(slot) >= 0) return { error: "this tree places " + slot + " already" }
  var out = copy(root)
  var path = pathTo(out, key)
  if (!path || path.length < 2) {
    out.weight = 1
    return { node: { kind: "h", weight: 1, children: [out, leaf] } }
  }
  var parent = path[path.length - 2].node
  parent.children.splice(path[path.length - 1].index + 1, 0, leaf)
  return { node: out }
}

// x: the slot `key` taken out of the tree, tidied ({ node: null } when it
// was all of it). Never the place for other windows. { node } or { error }.
function removeSlot(root, key) {
  if (key === OVERFLOW) return { error: "other windows always have a place in the tree: o only hides it from the picture" }
  if (isLeaf(root)) return { node: null }
  return { node: takeOut(root, key).node }
}

// The global slots (state.slots) no pane's draft of the workspace places
// yet: what `a` offers. `drafts` is screen key ("1") -> { node }.
function slotChoices(state, drafts) {
  var placed = {}
  for (var screen in drafts || {}) {
    var d = drafts[screen]
    if (d && d.node) leaves(d.node).forEach(function(k) { placed[k] = true })
  }
  var list = state && Array.isArray(state.slots) ? state.slots : []
  return list.map(function(s) { return s.name }).filter(function(name) { return !placed[name] })
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
    return "config.lua loads no slots.lua, so there is nothing the editor may change"
  }
  if (!layout) return "no desk is active: these monitors have none yet"
  var entry = layoutEntry(state, layout)
  if (!entry) return "no layout '" + layout + "'"
  if (entry.read_only) return "layout '" + layout + "' is set by code in config.lua; edit it there"
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
//     title?, selected?, column? }
// Boxes are proportional to the weights in whole pixels (tree.lua's
// arithmetic: the remainder goes to the last child). A nested container is a
// box titled with its kind and ratio, its children inset by `pad` (and
// `title` more at the top). A scroll branch is a filmstrip: its columns side
// by side in equal frames, numbered in order (`column`, from 1), each
// standing for a full-width column of the screen.
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
    if (node.kind === "scroll") {
      var offset = 0
      node.children.forEach(function(child, i) {
        var w = i === node.children.length - 1 ? box.w - offset : Math.floor(box.w / node.children.length)
        leaf(child, { x: box.x + offset, y: box.y, w: w, h: box.h }, depth)
        var frame = out[out.length - 1]
        frame.column = i + 1
        frame.label = (i + 1) + ". " + frame.label
        offset += w
      })
      return
    }
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

// The ratio prompt for a tree (aerolayout's [r]): { text } or { error } when
// there is nothing a ratio could divide.
function ratioPrompt(root) {
  if (isLeaf(root)) return { error: "Nothing to divide — this layout is one window." }
  var current = ratio(root)
  if (root.kind === "scroll") {
    return { error: "Ratios don't apply to a scroll branch — each of its columns is full width (" + current
      + "). Press t for tiles first." }
  }
  var hints = ["current " + current, "empty clears all"]
  return { text: "Ratios for the whole tree (" + hints.join("; ") + ") [Enter] set  [Esc] cancel: " }
}
