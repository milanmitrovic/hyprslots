.pragma library

// The editor's guidance for someone who has never seen hyprslots
// (docs/design.md §9, "First run and empty states"): the tab the panel opens
// on, what stands in a tab while there is nothing in it yet, and the line
// that says what to do next. Every empty state points to the next step: the
// Layout tab explains slots and makes the first one, the Assignment tab sends
// you there while there are none, and a workspace with nothing assigned says
// how to assign a window. Pure, so node can test it
// (editor/tests/guide.test.mjs).

var TABS = ["Assignment", "Layout", "Desk"]
var ASSIGNMENT = 0
var LAYOUT = 1

function slotCount(state) {
  return state && Array.isArray(state.slots) ? state.slots.length : 0
}

// Whether the engine runs a config the editor can edit slots in.
function running(state) {
  return !!state && !state.config_error && !state.refused
}

function slotsEditable(state) {
  var cfg = state && state.config
  if (!cfg) return true
  if (cfg.editable === false) return false
  return !(Array.isArray(cfg.read_only) && cfg.read_only.indexOf("slots") >= 0)
}

// Whether an open payload asks for a tab: the bar's Record (the Layout tab),
// or { tab: "Desk" } by name.
function asksForTab(payload) {
  return !!payload && (payload.record === true || TABS.indexOf(payload.tab) >= 0)
}

// The tab the panel opens on, an index into TABS: the one the payload asks
// for, else Layout while there are no slots (that is where they are made),
// else Assignment. null while that depends on a state not read yet.
function openingTab(state, payload) {
  if (payload && payload.record === true) return LAYOUT
  if (payload && TABS.indexOf(payload.tab) >= 0) return TABS.indexOf(payload.tab)
  if (!state) return null
  return running(state) && slotCount(state) === 0 ? LAYOUT : ASSIGNMENT
}

// What the Layout tab shows in place of its picture while there are no
// slots: { title, lines[], action: { key, label } } (the action's key makes
// the first slot: a name, then an optional description), or null.
function layoutWelcome(state) {
  if (!running(state) || slotCount(state) > 0 || !slotsEditable(state)) return null
  return {
    title: "Start with your slots",
    lines: [
      "Slots are named places on your screens, like left, main and right. Each app you assign goes into its slot.",
      "You choose the names, and how many. Arrange them here, then put windows into them in the Assignment tab.",
    ],
    action: { key: "a", label: "Create your first slot" },
  }
}

// The line under the Layout tab's header once there are slots but no
// workspace says yet what fills any of them: what to do next. "" otherwise.
function layoutHint(state) {
  if (!running(state) || slotCount(state) === 0) return ""
  var specs = state.specs || {}
  for (var n in specs) {
    if (specs[n] && Object.keys(specs[n]).length > 0) return ""
  }
  return "Add more slots (s, then a), or go to Assignment (Tab) to put windows into them."
}

// The first slot's name prompt and the message once it is made.
function firstSlotLabel() {
  return "Name your first slot (main, left, notes…) [Enter] next  [Esc] cancel: "
}

function firstSlotAdded(slot) {
  return "Made slot '" + slot + "': it shows in the picture. Ctrl+S saves."
}

// What the Assignment tab shows while there are no slots: { text, action:
// { key, label } } (the key goes to the Layout tab), or null.
function assignmentEmpty(state) {
  if (!running(state) || slotCount(state) > 0) return null
  return {
    text: "Define slots in the Layout tab first: they are the places your windows go into.",
    action: { key: "Tab", label: "Go to Layout" },
  }
}

// The line over a workspace's table while nothing on it is assigned (no
// window in a slot, none waited for): how to assign one, or, with no window
// there, to open one first. "" otherwise. `rows` are Assignment.rows.
function assignmentHint(state, rows, workspace) {
  if (!running(state) || slotCount(state) === 0) return ""
  var windows = 0
  for (var i = 0; i < rows.length; i++) {
    var status = rows[i].status
    if (status === "slot" || status === "manual" || status === "missing" || status === "overflow") return ""
    if (rows[i].kind === "window") windows++
  }
  if (windows === 0) return "Open an app on workspace " + workspace + ", then select it here and press a (or click assign)."
  return "Select a window and press a (or click assign) to put it into a slot."
}

// The Desk tab's opening line.
function deskIntro() {
  return "A desk is a monitor setup; its layout is how your slots are arranged on its screens."
    + " The other tabs edit the active desk's (●)."
}

// The Layout tab's help row while it explains slots (Help.js groups): a
// makes the first slot, s goes to the (empty) slot list.
function welcomeHelp() {
  return [
    [{ key: "a", label: "create your first slot" }],
    [{ key: "s", label: "slots" }],
    [{ key: "Tab", label: "view" }, { key: "q", label: "close" }],
  ]
}
