pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons

// A table's column titles, muted and small, over the TableRow cells they
// name: `columns` is [{ text, width }], the widths the rows' cells use (a
// leading { text: "", width: Tokens.stripeWidth } stands over the
// selection's stripe).
Row {
  id: root

  property var columns: []

  Repeater {
    model: root.columns
    delegate: Text {
      required property var modelData
      width: modelData.width
      visible: modelData.width > 0
      leftPadding: modelData.text !== "" ? Tokens.cellPadding : 0
      bottomPadding: Style.spacing.xs
      textFormat: Text.PlainText
      text: modelData.text
      color: Tokens.info
      font.family: Tokens.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
