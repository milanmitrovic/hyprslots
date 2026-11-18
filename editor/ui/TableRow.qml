import QtQuick
import qs.Commons
import qs.Commons as Commons

// A row of a list (the Assignment and Desk tables, the Layout tab's slot
// list). Selected: the accent's selected fill and an accent stripe down its
// left, the strongest thing on the page; `marked`: the current row while
// the keys are elsewhere, an outline. Its content goes past the stripe;
// a click selects it (clicked()), a double-click runs the view's primary
// action on it (doubleClicked(), after the click); `interactive: false`
// leaves the pointer to a MouseArea of the list's own (the Assignment
// table's, which drags rows). `dropTarget`: where a dragged row would land,
// an accent outline.
Rectangle {
  id: root

  property bool selected: false
  property bool marked: false
  property bool dropTarget: false
  property bool interactive: true
  default property alias content: inner.data
  signal clicked()
  signal doubleClicked()

  height: Tokens.rowHeight
  radius: Tokens.radius
  color: selected ? Tokens.selectionFill : dropTarget ? Tokens.dropFill : "transparent"
  border.width: dropTarget ? Tokens.dropLine : marked && !selected ? Math.max(1, Style.spacing.hairline) : 0
  border.color: dropTarget ? Tokens.dropOutline : Tokens.outline

  MouseArea {
    anchors.fill: parent
    enabled: root.interactive
    onClicked: root.clicked()
    onDoubleClicked: root.doubleClicked()
  }

  // the selection's stripe, down the left edge
  Rectangle {
    visible: root.selected
    width: Tokens.stripeWidth
    height: parent.height
    topLeftRadius: root.radius
    bottomLeftRadius: root.radius
    color: Commons.Color.accent
  }

  Item {
    id: inner
    x: Tokens.stripeWidth
    width: parent.width - x
    height: parent.height
  }
}
