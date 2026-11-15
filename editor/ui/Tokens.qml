pragma Singleton
import QtQuick
import qs.Commons
import qs.Commons as Commons

// The editor's design tokens, all from the Omarchy theme (colours, the
// theme's corner radius and spacing): what the components in this folder
// share, so each kind of element looks the same on every tab.
//
//   section headers   the accent colour (SectionHeader, WorkspaceSwitcher)
//   information       muted, small (InfoText)
//   problems          the urgent colour (ProblemText, InfoText.urgent)
//   the selection     an accent fill and an accent stripe down its left
//                     (TableRow), the strongest thing on a page
//   dividers          the Layout picture's split boundaries: a hit band
//                     wide enough to grab, an accent line on hover, the
//                     full accent while dragged; the ratio by the pointer
//                     on the theme's tooltip surface
//   drag and drop     the Assignment table's rows: the dragged row dimmed,
//                     a ghost of it by the pointer (DragGhost, on the menu
//                     surface), the row or section it would land on in an
//                     accent outline, what letting go does on the tooltip
//                     surface beside the ghost (as the ratio label)
//   mini-maps         a slot's place on its screen (MiniMap): the slot an
//                     accent fill, the others dim outlines; a desk's
//                     monitors (DeskMap): connected solid, absent
//                     outlined, the active desk's in the accent
//   actions           buttons (ActionButton: the help row's toolbar, a prompt's
//                     chips and answers), keys as key caps (KeyCap); hover
//                     and press from the theme's control tokens
QtObject {
  readonly property string fontFamily: Style.font.menuFamily

  readonly property color text: Commons.Color.menu.text
  readonly property color header: Commons.Color.accent
  readonly property color info: Commons.Color.muted
  readonly property color urgent: Commons.Color.urgent
  readonly property color selectedText: Commons.Color.menu.selectedText
  // a row that is neither active nor selected, where activity matters
  readonly property color restText: Commons.Util.alpha(text, 0.78)
  // what is there but not in force: a missing window, a slot with no spec
  readonly property real dim: 0.55
  readonly property real faint: 0.4

  readonly property int radius: Style.cornerRadius
  readonly property int rowHeight: Math.max(Style.space(26), Style.font.body + Style.spacing.md * 2)
  readonly property int cellPadding: Style.spacing.md
  readonly property int stripeWidth: Math.max(2, Style.spacing.xxs + 1)
  readonly property color selectionFill: Style.selectedAccentFill
  readonly property color outline: Commons.Util.alpha(text, 0.3)
  // a button at rest (ActionButton): there, but quieter than its hover fill
  readonly property color restFill: Commons.Util.alpha(text, 0.05)
  // the Layout picture's dividers: the band the pointer grabs (at least
  // 8 px), the line drawn on hover and while dragged
  readonly property int dividerHit: Math.max(8, Style.space(10))
  readonly property int dividerLine: Math.max(2, Style.spacing.xxs + 1)
  readonly property color dividerHover: Commons.Util.alpha(Commons.Color.accent, 0.6)
  readonly property color dividerActive: Commons.Color.accent
  // a small label by the pointer (the dragged split's ratio)
  readonly property color tipFill: Commons.Color.tooltip.background
  readonly property color tipText: Commons.Color.tooltip.text
  readonly property color tipBorder: Commons.Util.alpha(Commons.Color.accent, 0.7)
  // drag and drop (the Assignment table): what lands it, outlined and
  // faintly filled in the accent; the ghost by the pointer on the menu
  // surface (the label beside it: tipFill, tipText, tipBorder)
  readonly property color surface: Commons.Color.menu.background
  readonly property color dropOutline: Commons.Color.accent
  readonly property color dropFill: Commons.Util.alpha(Commons.Color.accent, 0.1)
  readonly property int dropLine: Math.max(2, Style.spacing.xxs)
  // a slot's mini-map: the box it fits (the screen's shape inside it), and
  // the rows tall enough for it
  readonly property int miniMapWidth: Style.space(56)
  readonly property int miniMapHeight: Style.space(32)
  readonly property int miniMapRowHeight: Math.max(rowHeight, miniMapHeight + Style.spacing.sm * 2)
  readonly property color miniMapFrame: Commons.Util.alpha(text, 0.04)
  readonly property color miniMapLine: Commons.Util.alpha(text, 0.35)
  readonly property color miniMapSlot: Commons.Color.accent
  // a desk's map (DeskMap, the Desk tab): its monitors in a box a little
  // wider than a slot's mini-map, the desk rows tall enough for it; a
  // connected screen solid, one that is not outlined, the active desk's in
  // the accent
  readonly property int deskMapWidth: Style.space(72)
  readonly property int deskMapHeight: Style.space(36)
  readonly property int deskMapRowHeight: Math.max(rowHeight, deskMapHeight + Style.spacing.sm * 2)
  readonly property color deskMapLine: Commons.Util.alpha(text, 0.45)
  readonly property color deskMapActive: Commons.Color.accent
  // where a page's text starts: past a row's stripe and its cell padding,
  // so headers, notes and cells line up on every tab
  readonly property int textInset: stripeWidth + cellPadding
}
