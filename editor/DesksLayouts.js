.pragma library

// The Desk view's model (docs/design.md §9), read off one api
// `state` reply. A desk is a monitor setup: the monitors it is made of and the
// layout it uses; the desk whose monitors are exactly
// the connected ones is active. A layout is a logical arrangement for N
// screens: several desks with N monitors may share one, and every edit goes
// to the active desk's. Pure, so node can test it
// (editor/tests/desks-layouts.test.mjs).
//
// A row is a desk { kind: "desk", key, name, active, auto, readOnly, layout,
// screens (its monitor count), monitors: [{ selector, connected,
// connector, description }] } or a layout { kind: "layout", key, name,
// active, readOnly, screens, usedBy[] }; desks first, each by name.

function sortedNames(object) {
  return Object.keys(object || {}).sort()
}

function monitorList(state) {
  return state && Array.isArray(state.monitors) ? state.monitors : []
}

// The connected monitor a selector names (description, then serial, then
// connector, as the engine resolves it), or null.
function findMonitor(selector, list) {
  var fields = ["description", "serial", "name"]
  for (var f = 0; f < fields.length; f++) {
    for (var i = 0; i < list.length; i++) {
      var value = list[i][fields[f]]
      if (value && value === selector) return list[i]
    }
  }
  return null
}

function deskRow(state, name) {
  var d = state.desks[name]
  var selectors = Array.isArray(d.monitors) ? d.monitors : []
  var connected = Array.isArray(d.connected) ? d.connected : []
  var list = monitorList(state)
  return {
    kind: "desk",
    key: "desk:" + name,
    name: name,
    active: !!d.active || state.desk === name,
    auto: !!d.auto,
    readOnly: !!d.read_only,
    layout: d.layout || "",
    screens: selectors.length,
    monitors: selectors.map(function(selector, i) {
      var on = connected[i] === true
      var m = on ? findMonitor(selector, list) : null
      return { selector: selector, connected: on, connector: m ? m.name : "", description: m ? m.description || "" : "" }
    }),
  }
}

function layoutRow(state, name) {
  var l = state.layouts[name]
  return {
    kind: "layout",
    key: "layout:" + name,
    name: name,
    active: !!l.active || state.layout === name,
    readOnly: !!l.read_only,
    screens: l.screens || 0,
    usedBy: Array.isArray(l.used_by) ? l.used_by.slice() : [],
  }
}

function rows(state) {
  if (!state) return []
  var out = []
  sortedNames(state.desks).forEach(function(name) { out.push(deskRow(state, name)) })
  sortedNames(state.layouts).forEach(function(name) { out.push(layoutRow(state, name)) })
  return out
}

function screensLabel(count) {
  return count === 1 ? "1 screen" : count + " screens"
}

function monitorsLabel(count) {
  return count === 1 ? "1 monitor" : count + " monitors"
}

// One monitor of a desk: "● eDP-1 (BOE 0x0BCA)" when connected (the
// connector, or the description when the selector is the connector), "○
// <selector>" when not.
function monitorText(m) {
  if (!m.connected) return "○ " + m.selector
  var what = m.connector && m.connector !== m.selector ? m.connector : m.description
  return "● " + m.selector + (what && what !== m.selector ? " (" + what + ")" : "")
}

function nameCell(row) {
  return row.name + (row.auto ? " (new, unsaved)" : "") + (row.readOnly ? " (set in your config)" : "")
}

// What a desk row shows, column by column; the mark, a quiet ● on the
// active one.
function deskCells(row) {
  return {
    mark: row.active ? "●" : "",
    name: nameCell(row),
    monitors: row.monitors.map(monitorText).join(" + "),
    layout: "→ " + row.layout,
  }
}

// The column titles over a section's rows ("desk" or "layout"), keyed as
// deskCells / layoutCells are.
function columnTitles(kind) {
  if (kind === "desk") return { name: "Desk", monitors: "Monitors", layout: "Uses layout" }
  return { name: "Layout", screens: "Screens", usedBy: "Used by" }
}

function layoutCells(row) {
  return {
    mark: row.active ? "●" : "",
    name: nameCell(row),
    screens: screensLabel(row.screens),
    usedBy: row.usedBy.length ? row.usedBy.join(", ") : "unused",
  }
}

// A section's quiet header ("desk" or "layout"): its title, and what it
// lists.
function sectionHeader(kind) {
  if (kind === "desk") return { title: "Desks", hint: "monitor setups · ● connected  ○ not" }
  return { title: "Layouts", hint: "a desk can use a layout with the same number of screens" }
}

// The keys that act on the selected row, for the help row: [{ key, label }].
function actions(row) {
  if (!row) return [{ key: "n", label: "new layout" }]
  var desk = row.kind === "desk"
  return [
    { key: "a", label: desk ? "apply a layout" : "apply to the active desk" },
    { key: "f", label: desk ? "fork its layout" : "fork" },
    { key: "n", label: "new layout" },
    { key: "r", label: "rename" },
    { key: "x", label: "delete" },
  ]
}

// The layouts a desk may use: those with as many screens as it has
// monitors, by name.
function layoutsFor(state, desk) {
  var d = state && state.desks ? state.desks[desk] : null
  if (!d) return []
  var count = Array.isArray(d.monitors) ? d.monitors.length : 0
  return sortedNames(state.layouts).filter(function(name) { return state.layouts[name].screens === count })
}

function activeDesk(state) {
  return state && state.desk && state.desks ? state.desks[state.desk] || null : null
}

// Why `layout` cannot go on the active desk, "" when it can.
function applyBlock(state, layout) {
  var d = activeDesk(state)
  if (!d) return "No desk is active: these monitors have none yet."
  var l = state.layouts ? state.layouts[layout] : null
  if (!l) return "There is no layout '" + layout + "'."
  var count = Array.isArray(d.monitors) ? d.monitors.length : 0
  if (l.screens !== count) {
    return "Layout '" + layout + "' has " + screensLabel(l.screens) + "; desk '" + state.desk + "' has "
      + monitorsLabel(count) + " — pick a layout with " + screensLabel(count) + "."
  }
  return ""
}

// The name a fork of `name` is suggested under: <name>-2, or the next free
// number (a fork of docked-2 counts on from docked).
function forkName(state, name) {
  var taken = state && state.layouts ? state.layouts : {}
  var base = String(name).replace(/-\d+$/, "")
  for (var n = 2; ; n++) {
    var candidate = base + "-" + n
    if (!Object.prototype.hasOwnProperty.call(taken, candidate)) return candidate
  }
}

// The layout f copies: the selected layout, or the selected desk's.
function forkSource(row) {
  if (!row) return null
  return row.kind === "desk" ? row.layout : row.name
}

function forkMessage(reply) {
  var text = "Forked '" + reply.layout + "' as '" + reply.to + "'; "
  text += reply.desk ? "desk '" + reply.desk + "' uses it now."
    : "the active desk has another screen count, so it keeps its layout."
  return text + " Ctrl+S saves."
}

// A new layout's screen count, suggested: the active desk's monitors.
function suggestedScreens(state) {
  var d = activeDesk(state)
  if (d && Array.isArray(d.monitors) && d.monitors.length) return d.monitors.length
  if (state && Array.isArray(state.screens) && state.screens.length) return state.screens.length
  return 1
}

function parseScreens(text) {
  var s = String(text).trim()
  if (!/^[0-9]+$/.test(s) || Number(s) < 1) return { error: "The screen count is a whole number from 1." }
  return { screens: Number(s) }
}

function deleteDeskQuestion(row) {
  var q = "Delete desk '" + row.name + "'? "
  if (row.active) {
    q += "It is the active desk: these monitors get a new desk (the layout used last with " + screensLabel(row.screens)
      + ") in a second. "
  }
  return q + "Its layout '" + row.layout + "' stays."
}

// What x on a layout asks: { question, remap[] }. A layout desks use goes
// only when they move to another with as many screens (remap, picked); with
// none to move to, the y/n question leads to the engine's refusal.
function deleteLayoutPlan(state, row) {
  if (row.usedBy.length === 0) return { question: "Delete layout '" + row.name + "'? No desk uses it.", remap: [] }
  var others = sortedNames(state && state.layouts).filter(function(name) {
    return name !== row.name && state.layouts[name].screens === row.screens
  })
  var who = (row.usedBy.length === 1 ? "desk " : "desks ") + row.usedBy.join(", ")
  if (others.length === 0) {
    return { question: "Delete layout '" + row.name + "'? " + who.charAt(0).toUpperCase() + who.slice(1) + " uses it.",
      remap: [] }
  }
  return { question: "Layout '" + row.name + "' is used by " + who + ": move " + (row.usedBy.length === 1 ? "it" : "them")
    + " to", remap: others }
}

// The desks other than `desk` that use `layout`: an edit to it changes it
// for them too.
function sharedWith(state, layout, desk) {
  var l = state && state.layouts ? state.layouts[layout] : null
  var users = l && Array.isArray(l.used_by) ? l.used_by : []
  return users.filter(function(name) { return name !== desk })
}

// The Layout tab's warning while other desks (`names`) use the layout it
// edits; "" when none do. Forking is the Desk tab's.
function sharedNote(names) {
  if (!names || names.length === 0) return ""
  return "Shared with desk" + (names.length > 1 ? "s " : " ") + names.join(", ")
    + ": edits here change it there too — fork it in the Desk tab."
}

// The panel's header line, on every tab.
function header(state) {
  if (!state || !state.desk) return "Desk: none"
  var d = state.desks ? state.desks[state.desk] : null
  var text = "Desk: " + state.desk + (d && d.auto ? " (new, unsaved)" : "")
  if (state.layout) {
    var others = sharedWith(state, state.layout, state.desk)
    text += " · Layout: " + state.layout + (others.length ? " (also used by: " + others.join(", ") + ")" : "")
  }
  return text
}

function readOnlyError(row) {
  if (!row || !row.readOnly) return ""
  return (row.kind === "desk" ? "Desk '" : "Layout '") + row.name + "' is set in your config."
}
