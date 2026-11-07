.pragma library

// The Layout view's model (docs/design.md §9): one desk's trees, edited as a
// draft before they are applied. Ported from aerolayout's tree_visualizer.py
// (move, force move, flip, toggle, overflow, the nested ratio editor) onto
// hyprslots' tree text (tree.lua) and ratio grammar (ratio.lua), which are
// mirrored here so the draft can be edited, shown and checked without a
// round trip; the engine validates again on apply. Pure, so node can test it
// (editor/tests/layout.test.mjs).
//
// A node is
//   { kind: "slot", slot, weight }          a slot
//   { kind: "overflow", weight }            the overflow leaf, written *
//   { kind: "h" | "v", weight, children }   a split
//   { kind: "a", weight, children, was? }   an accordion (slots only); `was`
//                                           remembers the split it was made from
// A leaf is named by its key: the slot's name, or "*" for the overflow leaf.
// Every edit returns { node } (a new tree) or { error }; the tree given is
// never changed.

var OVERFLOW = "*"

// --- tree text (tree.lua) ---------------------------------------------------

var NAME = /^[A-Za-z0-9_\-.]+/
var CONTAINER = { h: true, v: true, a: true }

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
  function children(child, weightless) {
    pos++
    var out = []
    var more
    do {
      var n = child()
      if (weightless && peek() === ":") fail("accordion members take no weight (the accordion shares one box)")
      n.weight = weight()
      out.push(n)
      more = peek() === ","
      if (more) pos++
    } while (more)
    expect("]")
    return out
  }
  function member() {
    if (peek() === "*") fail("an accordion holds slots only, found '*' inside it")
    var start = pos
    var n = name()
    if (CONTAINER[n] && peek() === "[") {
      pos = start
      skip()
      fail("an accordion holds slots only, found '" + n + "[' inside it")
    }
    return { kind: "slot", slot: n }
  }
  function node() {
    if (peek() === "*") {
      if (overflow) fail("more than one overflow leaf '*'")
      overflow = true
      pos++
      return { kind: "overflow" }
    }
    var n = name()
    if (CONTAINER[n] && peek() === "[") {
      if (n === "a") return { kind: "a", children: children(member, true) }
      return { kind: n, children: children(node, false) }
    }
    return { kind: "slot", slot: n }
  }

  var root
  try {
    root = node()
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

// A deep copy (the `was` memory of an accordion included).
function copy(node) {
  var out = {}
  for (var key in node) out[key] = node[key]
  if (node.children) out.children = node.children.map(copy)
  if (node.was) out.was = { kind: node.was.kind, weights: node.was.weights.slice() }
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
  var own = child.kind === "slot" ? child.slot : child.kind === "overflow" ? "the overflow" : "cell " + index
  return parent === ROOT_SUBJECT ? own : parent + " > " + own
}

function validate(node, list, path) {
  if (isLeaf(node)) ratioFail(path + " is a window, not a split")
  var count = node.children.length
  if (list.length !== count) {
    ratioFail("expected " + count + " value" + (count === 1 ? "" : "s") + " for " + path + ", got " + list.length)
  }
  for (var i = 0; i < list.length; i++) {
    if (node.kind === "a") {
      if (list[i].weight !== STAR && list[i].weight !== 1) {
        ratioFail("ratios don't apply to " + path + " — it's an accordion, and its panes each get the "
          + "whole container. Write * for a collapsed pane and 1 for the expanded one")
      }
    } else if (list[i].weight === STAR) {
      ratioFail("* is an accordion pane with no share of its own, and " + path
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
  var weights = node.kind === "a" ? null : integers(list.map(function(t) { return t.weight }))
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
  var cells = node.kind === "a"
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

// The axis a container lays its children along; an accordion's members sit
// side by side, like the tabs of its Hyprland group.
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
// share); a child split of the same kind is merged in, its children's
// shares scaled so nothing moves on screen. Empty containers go. Changes
// `node` in place and returns its replacement, or null when nothing is left.
function tidy(node) {
  if (isLeaf(node)) return node
  var kept = []
  for (var i = 0; i < node.children.length; i++) {
    var child = tidy(node.children[i])
    if (child) kept.push(child)
  }
  var mergeable = function(c) { return !isLeaf(c) && c.kind === node.kind && c.kind !== "a" }
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
  if (children.length === 1) {
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

var ACCORDION_SLOTS = "an accordion holds slots only (no splits inside a group); press t to make it tiles first"

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
  if (axisOf(parent) === AXIS[direction]) {
    var other = index + STEP[direction]
    if (other < 0 || other >= parent.children.length) return { node: out, changed: false }
    if (parent.kind === "a") return { error: ACCORDION_SLOTS }
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

// t: the leaf's container stacked as an accordion, or an accordion back to
// the split it was (toggle_layout_mode). An accordion holds slots only, as
// tree.lua says when it is not so. { node } or { error }.
function toggleAccordion(root, key) {
  var out = copy(root)
  var path = pathTo(out, key)
  if (!path) return { error: "no leaf '" + key + "' in this tree" }
  if (path.length < 2) return { error: "this tree is one window; there is no container to stack" }
  var target = path[path.length - 2].node
  if (target.kind === "a") {
    var was = target.was
    target.kind = was ? was.kind : "h"
    var keep = was && was.weights.length === target.children.length
    target.children.forEach(function(child, i) { child.weight = keep ? was.weights[i] : 1 })
    delete target.was
    return { node: out }
  }
  for (var i = 0; i < target.children.length; i++) {
    var child = target.children[i]
    if (child.kind === "overflow") return { error: "an accordion holds slots only, found '*' inside it" }
    if (!isLeaf(child)) return { error: "an accordion holds slots only, found '" + child.kind + "[' inside it" }
  }
  target.was = { kind: target.kind, weights: target.children.map(function(c) { return c.weight }) }
  target.kind = "a"
  target.children.forEach(function(c) { c.weight = 1 })
  return { node: out }
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

// o: park the overflow leaf (out of the tree; the engine then gives windows
// with no slot a column at the right), or put it back: exactly as it was
// when the tree has not changed since, else beside the leaf it was next to,
// else where the engine would put it. `memory` is what parking returned.
// { node, parked, memory } or { error }.
function toggleOverflow(root, memory) {
  if (leaves(root).indexOf(OVERFLOW) >= 0) {
    if (isLeaf(root)) return { error: "the overflow leaf is the whole tree; there would be nothing left to edit" }
    var taken = takeOut(root, OVERFLOW)
    return { node: taken.node, parked: true,
      memory: { saved: format(root), shape: format(taken.node), anchor: taken.anchor } }
  }
  if (memory && memory.shape === format(root)) {
    return { node: parse(memory.saved).node, parked: false, memory: null }
  }
  if (memory && memory.anchor) {
    var out = copy(root)
    var path = pathTo(out, memory.anchor.key)
    if (path && path.length >= 2) {
      var parent = path[path.length - 2].node
      var index = path[path.length - 1].index
      if (parent.kind !== "a") {
        parent.children.splice(memory.anchor.side === "after" ? index + 1 : index, 0, { kind: "overflow", weight: 1 })
        return { node: out, parked: false, memory: null }
      }
    }
  }
  return { node: withOverflow(root), parked: false, memory: null }
}

// A leaf moved off the left or right edge of its screen's tree onto the
// next screen's (`target`, null when that screen has no tree for the desk),
// arriving at the near edge (aerolayout's cross-pane move).
// { source, target } or { error }.
function crossMove(source, target, key, direction) {
  if (isLeaf(source)) {
    return { error: (key === OVERFLOW ? "the overflow leaf" : key) + " is the only window on this screen; "
      + "moving it would leave the screen empty" }
  }
  if (key === OVERFLOW && target && leaves(target).indexOf(OVERFLOW) >= 0) {
    return { error: "that screen has an overflow leaf already" }
  }
  var path = pathTo(source, key)
  var leaf = path[path.length - 1].node
  var moved = leaf.kind === "overflow" ? { kind: "overflow", weight: 1 } : { kind: "slot", slot: leaf.slot, weight: 1 }
  var rest = takeOut(source, key).node
  if (!target) return { source: rest, target: moved }
  var into = copy(target)
  var atStart = STEP[direction] > 0
  if (into.kind === "h") {
    into.children.splice(atStart ? 0 : into.children.length, 0, moved)
  } else {
    into.weight = 1
    into = { kind: "h", weight: 1, children: atStart ? [moved, into] : [into, moved] }
  }
  return { source: rest, target: rooted(into) }
}
