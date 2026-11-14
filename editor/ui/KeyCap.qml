import QtQuick
import qs.Commons
import qs.Commons as Commons

// A key, drawn as a key cap: the letter or name bold in the accent colour
// (`ink`: the selected text colour on a selected row) on a faint rounded
// outline ("m", "Esc"). The slot list shows each slot's key with it; an
// ActionButton (a toolbar button, a prompt's chip) leads with one.
Rectangle {
  id: root

  property string text: ""
  property color ink: Commons.Color.accent
  property int pixelSize: Style.font.bodySmall

  implicitWidth: Math.max(implicitHeight, glyph.implicitWidth + Style.spacing.sm * 2)
  implicitHeight: glyph.implicitHeight + Style.spacing.xxs * 2
  width: implicitWidth
  height: implicitHeight
  radius: Math.min(Tokens.radius, height / 3)
  color: Commons.Util.alpha(root.ink, 0.1)
  border.width: Math.max(1, Style.spacing.hairline)
  border.color: Commons.Util.alpha(root.ink, 0.45)

  Text {
    id: glyph
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: root.text
    color: root.ink
    font.family: Tokens.fontFamily
    font.pixelSize: root.pixelSize
    font.bold: true
  }
}
