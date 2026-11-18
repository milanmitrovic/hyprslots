import QtQuick
import qs.Commons

// What a drag carries, by the pointer: a ghost of the dragged row (its
// app, bold, and its title, muted) on the menu surface, and, beside it on
// the tooltip surface as the Layout picture's ratio label, what letting go
// there does (`label`, "Assign to main", "Unassign"; none where it does
// nothing).
Item {
  id: root

  property string title: ""
  property string subtitle: ""
  property string label: ""

  implicitWidth: Math.max(card.width, tip.visible ? tip.width : 0)
  implicitHeight: card.height + (tip.visible ? tip.height + Style.spacing.xs : 0)
  width: implicitWidth
  height: implicitHeight

  Rectangle {
    id: card
    // what the texts need (TextMetrics: an elided Text's implicitWidth
    // follows the width it is given), at most Style.space(320)
    readonly property real natural: Math.ceil(appMetrics.advanceWidth)
      + (root.subtitle !== "" ? Style.spacing.md + Math.ceil(titleMetrics.advanceWidth) : 0)
    width: Math.min(Style.space(320), natural + Style.spacing.md * 2)
    height: Tokens.rowHeight
    radius: Tokens.radius
    color: Tokens.surface
    opacity: 0.94
    border.width: 1
    border.color: Tokens.outline

    Text {
      id: appText
      x: Style.spacing.md
      width: Math.min(Math.ceil(appMetrics.advanceWidth), card.width - Style.spacing.md * 2)
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.title
      color: Tokens.text
      font.family: Tokens.fontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
    Text {
      id: titleText
      x: appText.x + appText.width + Style.spacing.md
      width: Math.max(0, card.width - x - Style.spacing.md)
      anchors.verticalCenter: parent.verticalCenter
      visible: root.subtitle !== ""
      textFormat: Text.PlainText
      elide: Text.ElideRight
      text: root.subtitle
      color: Tokens.info
      font.family: Tokens.fontFamily
      font.pixelSize: Style.font.body
    }
  }

  TextMetrics {
    id: appMetrics
    font: appText.font
    text: root.title
  }
  TextMetrics {
    id: titleMetrics
    font: titleText.font
    text: root.subtitle
  }

  Rectangle {
    id: tip
    visible: root.label !== ""
    y: card.height + Style.spacing.xs
    width: tipText.implicitWidth + Style.spacing.md * 2
    height: tipText.implicitHeight + Style.spacing.xs * 2
    radius: Tokens.radius
    color: Tokens.tipFill
    border.width: 1
    border.color: Tokens.tipBorder
    Text {
      id: tipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: root.label
      color: Tokens.tipText
      font.family: Tokens.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }
}
