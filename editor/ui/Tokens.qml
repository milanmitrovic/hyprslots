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
  // where a page's text starts: past a row's stripe and its cell padding,
  // so headers, notes and cells line up on every tab
  readonly property int textInset: stripeWidth + cellPadding
}
