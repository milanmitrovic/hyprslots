pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Commons as Commons

// A desk's monitors as a small map (the Desk tab's leading column): `map`
// is DesksLayouts.deskMap's { w, h, screens[] }, fitted into
// Tokens.deskMapWidth x deskMapHeight and centred in it; each screen a
// rectangle labelled with its number, solid when the monitor is connected,
// outlined when not, the active desk's in the accent (the others in the
// mini-maps' dim line colour). `tip`: what hovering it says (the screens'
// display names); the view that holds it shows that while `hovered`, as a
// tooltip under the map's row, over the list (DesksLayoutsView), so it
// hides nothing on the row and no row or list clip cuts it. `name` keys its
// objectNames for the e2e smoke: "deskmap:<name>", each screen
// "deskmap:<name>:<n>".
Item {
  id: root

  property var map: ({ w: 0, h: 0, screens: [] })
  property bool active: false
  property string tip: ""
  property string name: ""
  readonly property bool hovered: hover.hovered

  objectName: name !== "" ? "deskmap:" + name : ""
  implicitWidth: Tokens.deskMapWidth
  implicitHeight: Tokens.deskMapHeight

  readonly property color ink: active ? Tokens.deskMapActive : Tokens.deskMapLine

  HoverHandler {
    id: hover
  }

  Item {
    id: box
    anchors.centerIn: parent
    width: root.map.w
    height: root.map.h

    Repeater {
      model: root.map.screens
      delegate: Rectangle {
        id: screen
        required property var modelData
        objectName: root.name !== "" ? "deskmap:" + root.name + ":" + modelData.screen : ""
        // a pixel apart from the screen beside it
        x: modelData.x + 1
        y: modelData.y + 1
        width: Math.max(2, modelData.w - 2)
        height: Math.max(2, modelData.h - 2)
        radius: Math.min(Tokens.radius, Style.space(2))
        color: modelData.connected ? root.ink : "transparent"
        border.width: modelData.connected ? 0 : 1
        border.color: root.ink

        Text {
          anchors.centerIn: parent
          visible: screen.width >= 7 && screen.height >= 8
          textFormat: Text.PlainText
          text: String(screen.modelData.screen)
          color: screen.modelData.connected ? Tokens.surface : root.ink
          font.family: Tokens.fontFamily
          font.pixelSize: Math.max(7, Math.min(Style.font.bodySmall, screen.height - 2))
          font.bold: true
        }
      }
    }
  }
}
