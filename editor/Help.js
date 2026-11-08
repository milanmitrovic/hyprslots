.pragma library

// The help row of every view (docs/design.md §9): each action with its
// trigger key highlighted inside its label, as Qt StyledText ("<b><font
// color=...>a</font></b>dd"). Pure, so node can test it
// (editor/tests/help.test.mjs).
//
// An item is { key, label }: a single-character key is highlighted where it
// first occurs in the label, ignoring case (a shifted key shows itself in
// place: "Record" for R), else it goes before the label ("x delete", "/ flip");
// a longer key (Tab, Ctrl+S, "[ ]", ←→) always goes before it. { text } is
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
  if (key.length === 1) {
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
