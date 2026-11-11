import QtQuick
import qs.Commons
import qs.Commons as Commons

// A row of a list (the Assignment and Desk tables, the Layout tab's slot
// list). Selected: the accent's selected fill and an accent stripe down its
// left, the strongest thing on the page; `marked`: the current row while
// the keys are elsewhere, an outline. Its content goes past the stripe;
// a click selects it (clicked()).
Rectangle {
  id: root

  property bool selected: false
  property bool marked: false
  default property alias content: inner.data
  signal clicked()

  height: Tokens.rowHeight
  radius: Tokens.radius
  color: selected ? Tokens.selectionFill : "transparent"
  border.width: marked && !selected ? Math.max(1, Style.spacing.hairline) : 0
  border.color: Tokens.outline

  MouseArea {
    anchors.fill: parent
    onClicked: root.clicked()
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
