.pragma library

// The Arrangements view's model (aerolayout's MonitorsView): every
// arrangement with its screens, which one these monitors run, and what a new
// one for them would look like; read off one api `state` reply
// (docs/design.md §9). Pure, so node can test it
// (editor/tests/arrangements.test.mjs).
//
// hyprslots picks the arrangement itself: the one whose screens are exactly
// the connected monitors (§8). So where aerolayout's [a] mapped a monitor
// signature to an arrangement, here an arrangement is made to fit these
// monitors by pointing its screen roles at them.

function monitors(state) {
  return state && Array.isArray(state.monitors) ? state.monitors : []
}

// The connector a selector picks among the monitors, as the engine resolves
// it (arrangement.lua): description, then serial, then connector; empty
// fields never match. Null when none.
function resolve(selector, list) {
  var fields = ["description", "serial", "name"]
  for (var f = 0; f < fields.length; f++) {
    for (var i = 0; i < list.length; i++) {
      var value = list[i][fields[f]]
      if (value && value === selector) return list[i].name
    }
  }
  return null
}

function rows(state) {
  if (!state || !state.arrangements) return []
  var connected = monitors(state)
  var pinned = {}
  var p = Array.isArray(state.pinned) ? state.pinned : []
  for (var i = 0; i < p.length; i++) pinned[p[i]] = true
  return Object.keys(state.arrangements).sort().map(function(name) {
    var a = state.arrangements[name]
    var roles = Array.isArray(a.roles) ? a.roles : Object.keys(a.screens || {}).sort()
    var seen = {}
    var fits = roles.length === connected.length && connected.length > 0
    var screens = roles.map(function(role) {
      var selector = (a.screens || {})[role]
      var monitor = resolve(selector, connected)
      if (!monitor || seen[monitor]) fits = false
      if (monitor) seen[monitor] = true
      return { role: role, selector: selector, monitor: monitor, pinned: !!pinned[role] }
    })
    var workspaces = Object.keys(a.workspaces || {}).map(Number).sort(function(x, y) { return x - y })
    return { name: name, screens: screens, active: !!a.active || state.arrangement === name, fits: fits,
      readOnly: !!a.read_only, workspaces: workspaces }
  })
}

function screensLabel(count) {
  return count === 1 ? "1 screen" : count + " screens"
}

function rowText(row) {
  var text = row.name + "   " + screensLabel(row.screens.length)
  if (row.active) text += "   ● in use here"
  if (row.readOnly) text += "   (set in config.lua)"
  return text
}

function monitorText(m) {
  var what = m.description || m.serial
  return m.name + (what ? " (" + what + ")" : "")
}

function header(state) {
  var list = monitors(state)
  var lines = [list.length ? "These monitors: " + list.map(monitorText).join(" + ") : "No monitors connected."]
  lines.push(state && state.arrangement ? "Running: " + state.arrangement
    : "Running: nothing — no arrangement names exactly these screens")
  return lines
}

// What a new arrangement selects a monitor by: its description (it follows
// the monitor from port to port), else its serial, else its connector (the
// laptop panel reports neither).
function selectorFor(monitor) {
  return monitor.description || monitor.serial || monitor.name
}

// Every value that selects one of the monitors, to step through when typing
// a selector.
function selectorSuggestions(list) {
  var out = []
  for (var i = 0; i < list.length; i++) {
    var values = [list[i].description, list[i].serial, list[i].name]
    for (var v = 0; v < values.length; v++) if (values[v] && out.indexOf(values[v]) < 0) out.push(values[v])
  }
  return out
}

// The role name to suggest for a monitor of a new arrangement: what the
// running arrangement calls it, else "laptop" for a built-in panel, else
// "screenN"; never one of `taken`.
function suggestedRole(state, monitor, index, taken) {
  var base = null
  var screens = (state && state.screens) || {}
  for (var role in screens) if (screens[role] === monitor.name) base = role
  if (!base) base = /^eDP/.test(monitor.name || "") ? "laptop" : "screen" + (index + 1)
  var name = base
  for (var n = 2; taken.indexOf(name) >= 0; n++) name = base + n
  return name
}

// Copying trees: each target role takes the source role of its name; the
// others are to be asked.
function roleMapping(sourceRoles, targetRoles) {
  var map = {}
  var ask = []
  for (var i = 0; i < targetRoles.length; i++) {
    if (sourceRoles.indexOf(targetRoles[i]) >= 0) map[targetRoles[i]] = targetRoles[i]
    else ask.push(targetRoles[i])
  }
  return { map: map, ask: ask }
}

// Where `c` (copy trees) can copy from: the default trees, then every other
// arrangement. Values are the copy_trees arguments.
function copySources(state, exclude) {
  var out = [{ label: "default", value: { default: true } }]
  var names = Object.keys((state && state.arrangements) || {}).sort()
  for (var i = 0; i < names.length; i++) if (names[i] !== exclude) out.push({ label: names[i], value: { from: names[i] } })
  return out
}

function deleteQuestion(row) {
  var q = "Delete arrangement '" + row.name + "'? "
  q += row.workspaces.length ? "It takes its trees for workspaces " + row.workspaces.join(", ") : "It holds no trees"
  if (row.active) q += "; these monitors will run nothing until another matches them"
  return q + "."
}
