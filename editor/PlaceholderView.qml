pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons
import "Summary.js" as Summary

// A tab whose editor arrives in a later slice (Layout: D2; Slots and
// Arrangements: D3). Until then it shows, read-only, what it will edit.
Item {
  id: root

  property string view: ""
  property var engine: null
  property color foreground: Commons.Color.menu.text
  property string fontFamily: Style.font.menuFamily

  readonly property var lines: Summary.lines(engine ? engine.state : null, view)

  Column {
    anchors.fill: parent
    spacing: Style.spacing.md

    Text {
      width: parent.width
      textFormat: Text.PlainText
      wrapMode: Text.WordWrap
      text: "The " + root.view + " editor is not built yet; this is what it will edit."
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      font.italic: true
    }

    ListView {
      width: parent.width
      height: parent.height - y
      clip: true
      model: root.lines
      delegate: Text {
        required property string modelData
        width: ListView.view.width
        textFormat: Text.PlainText
        text: modelData
        color: root.foreground
        font.family: "monospace"
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }
}
