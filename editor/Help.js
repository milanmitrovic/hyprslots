.pragma library

// The help row of every view (docs/design.md §9): each action with its
// trigger key highlighted inside its label, as Qt StyledText ("<b><font
// color=...>a</font></b>dd"). Pure, so node can test it
// (editor/tests/help.test.mjs).
//
// An item is { key, label }: a single-character key is highlighted where it
// first occurs in the label, ignoring case (a shifted key shows itself in
// place: "Record" for R), else it goes before the label ("x delete", "/ flip");
// a longer key (Tab, Ctrl+S, "[ ]", ←→) always goes before it, as does any
// key of an item with `before: true` ("o show/hide other windows"). { text } is
// plain text. A row is a list of groups, each a list of items or { title,
// items }; items are joined by two spaces, groups by a dot.

var ITEM_GAP = "  "
var GROUP_GAP = "   ·   "

function escape(text) {
  return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

function mark(text, accent) {
  return '<b><font color="' + accent + '">' + escape(text) + "</font></b>"
}

function item(entry, accent) {
  if (entry.key === undefined || entry.key === null || entry.key === "") return escape(entry.text || entry.label || "")
  var key = String(entry.key)
  var label = entry.label ? String(entry.label) : ""
  if (label === "") return mark(key, accent)
  if (key.length === 1 && !entry.before) {
    var at = label.toLowerCase().indexOf(key.toLowerCase())
    if (at >= 0) {
      var found = label.charAt(at)
      // a shifted key (R) over its lower-case letter shows itself
      var shown = key !== key.toLowerCase() && found === found.toLowerCase() ? key : found
      return escape(label.slice(0, at)) + mark(shown, accent) + escape(label.slice(at + 1))
    }
  }
  return mark(key, accent) + " " + escape(label)
}

function group(entry, accent) {
  var items = Array.isArray(entry) ? entry : entry.items || []
  var text = items.map(function(i) { return item(i, accent) }).join(ITEM_GAP)
  return !Array.isArray(entry) && entry.title ? escape(entry.title) + ": " + text : text
}

function row(groups, accent) {
  return groups.filter(function(g) { return Array.isArray(g) ? g.length > 0 : (g.items || []).length > 0 })
    .map(function(g) { return group(g, accent) }).join(GROUP_GAP)
}

// The row as it reads, without the markup.
function plain(styled) {
  return String(styled).replace(/<[^>]*>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
}

// --- the toolbar: the same rows, every action a button ------------------------
//
// The panel draws a row as a toolbar (Panel.qml): each action a button
// showing its label with the key highlighted, as above; a click feeds the
// panel the key itself (Panel.press), so a click and a key press run one
// handler. An item whose key is several keys ("↑/↓", "hjkl/HJKL", "[ ]")
// is a key button per key, then its label. Digits are the workspace
// switcher's to click (it heads the views that have them): a range ("1–9")
// and the digits beside it are shown, not clicked.

var ARROWS = { "↑": "Up", "↓": "Down", "←": "Left", "→": "Right" }
var NAMES = { Tab: "Tab", Esc: "Escape", Return: "Return", "Ctrl+S": "Ctrl+s" }

// The key presses behind a help key: [{ glyph (what the button shows),
// press (the key name Panel.press takes, null for none) }].
function presses(key) {
  var out = []
  var text = String(key)
  var parts = []
  text.split(" ").forEach(function(word) {
    if (word === "") return
    if (word === "/" || NAMES[word]) parts.push(word)
    else word.split("/").forEach(function(p) { if (p !== "") parts.push(p) })
  })
  var ranged = parts.some(function(p) { return p.indexOf("–") >= 0 })
  parts.forEach(function(part) {
    if (NAMES[part]) out.push({ glyph: part, press: NAMES[part] })
    else if (part.indexOf("–") >= 0) out.push({ glyph: part, press: null })
    else if (/^[0-9]$/.test(part) && ranged) out.push({ glyph: part, press: null })
    else if (part.length > 1 && part.split("").every(function(c) { return ARROWS[c] })) {
      part.split("").forEach(function(c) { out.push({ glyph: c, press: ARROWS[c] }) })
    } else if (part.length > 1 && /^[A-Za-z]+$/.test(part)) {
      part.split("").forEach(function(c) { out.push({ glyph: c, press: c }) })
    } else out.push({ glyph: part, press: ARROWS[part] || part })
  })
  return out
}

// A row (as row() takes it) as the toolbar's cells, in order: { kind:
// "title", text } (a group's title), { kind: "text", text } (plain text),
// { kind: "button", styled (item()'s text), press, available } for an
// action of one key, { kind: "keys", keys: presses(), label, available }
// for one of several; each with its `group` and `first` (it starts its
// group, which the toolbar sets apart). `available` is false for an item
// marked `enabled: false`: the view would refuse the key now.
function buttons(groups, accent) {
  var cells = []
  var group = 0
  groups.forEach(function(g) {
    var items = Array.isArray(g) ? g : g.items || []
    if (items.length === 0) return
    var first = true
    var push = function(cell) {
      cell.group = group
      cell.first = first
      first = false
      cells.push(cell)
    }
    if (!Array.isArray(g) && g.title) push({ kind: "title", text: String(g.title) })
    items.forEach(function(entry) {
      if (entry.key === undefined || entry.key === null || entry.key === "") {
        push({ kind: "text", text: String(entry.text || entry.label || "") })
        return
      }
      var keys = presses(entry.key)
      var available = entry.enabled !== false
      if (keys.length === 1 && keys[0].press !== null) {
        push({ kind: "button", styled: item(entry, accent), press: keys[0].press, available: available })
      } else {
        push({ kind: "keys", keys: keys, label: entry.label ? String(entry.label) : "", available: available })
      }
    })
    group++
  })
  return cells
}
