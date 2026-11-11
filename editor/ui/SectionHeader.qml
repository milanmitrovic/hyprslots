import QtQuick
import qs.Commons

// A section's header: its title in the accent colour, small capitals,
// letter-spaced ("DESKS", "LAYOUTS", the workspace switcher's
// "WORKSPACE"), and an optional hint after it as InfoText.
Row {
  id: root

  property string title: ""
  property string hint: ""

  spacing: Style.spacing.lg

  Text {
    id: titleText
    anchors.verticalCenter: parent.verticalCenter
    textFormat: Text.PlainText
    text: root.title
    color: Tokens.header
    font.family: Tokens.fontFamily
    font.pixelSize: Style.font.bodySmall
    font.weight: Font.DemiBold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: Math.max(1, Style.spacing.xxs / 2)
  }

  InfoText {
    visible: root.hint !== ""
    anchors.verticalCenter: parent.verticalCenter
    text: root.hint
  }
}
