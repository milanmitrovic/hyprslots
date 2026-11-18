pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs.Commons
import "../Layout.js" as Layout

// A slot's place on its screen, at thumbnail size (the Assignment table's
// slot rows): the workspace's tree there, `tree` as state has it, drawn
// with the Layout picture's own geometry (Layout.miniMap: tiles in
// proportion; a scroll tree's whole strip, the screen outlined where it
// scrolls to show the slot's column),
// `slot` an accent fill and the others dim outlines. The screen's shape
// (the monitor `connector`'s) fitted into Tokens.miniMapWidth x
// miniMapHeight. `targeted`: the slot a drag would land on, outlined in the
// accent.
Item {
  id: root

  property string tree: ""
  property string slot: ""
  property string connector: ""
  property bool targeted: false

  function aspectOf(name) {
    var list = Hyprland.monitors ? Hyprland.monitors.values : []
    for (var i = 0; i < list.length; i++) {
      var m = list[i]
      if (m && m.name === name && m.width > 0 && m.height > 0) return m.width / m.height
    }
    return 16 / 9
  }

  readonly property var fit: Layout.miniMapSize(aspectOf(connector), Tokens.miniMapWidth, Tokens.miniMapHeight)
  // laid out a pixel inside the screen's line
  readonly property var map: Layout.miniMap(tree, slot, { w: Math.max(0, fit.w - 2), h: Math.max(0, fit.h - 2) })

  implicitWidth: Tokens.miniMapWidth
  implicitHeight: Tokens.miniMapHeight
  visible: map.kind !== "none"

  // The box, the screen in it (a tiled tree's: all of it; a scroll tree's:
  // the part of the strip it shows), the tiles or columns over that and the
  // screen's line over them. Layout.miniMap lays out a box a pixel
  // smaller each side, so the line sits just outside the tiles.
  Item {
    id: box
    anchors.centerIn: parent
    width: root.fit.w
    height: root.fit.h
    clip: true
    readonly property var screen: root.map.screen || ({ x: 0, y: 0, w: 0, h: 0 })
    readonly property int corner: Math.min(Tokens.radius, Style.space(3))

    Rectangle {
      x: box.screen.x
      y: box.screen.y
      width: box.screen.w + 2
      height: box.screen.h + 2
      radius: box.corner
      color: root.targeted ? Tokens.dropFill : Tokens.miniMapFrame
    }

    Repeater {
      model: root.map.tiles
      delegate: Rectangle {
        required property var modelData
        readonly property bool lit: !!modelData.selected
        // two pixels apart, one inside the screen's line
        x: 1 + modelData.x + 1
        y: 1 + modelData.y + 1
        width: Math.max(1, modelData.w - 2)
        height: Math.max(1, modelData.h - 2)
        radius: Math.min(Tokens.radius, Style.space(2))
        // a scroll tree's columns beyond the screen, fainter
        opacity: modelData.visible === undefined || modelData.visible > 0.999 ? 1 : Tokens.faint
        color: lit ? Tokens.miniMapSlot : "transparent"
        border.width: lit ? 0 : 1
        border.color: Tokens.miniMapLine
      }
    }

    Rectangle {
      x: box.screen.x
      y: box.screen.y
      width: box.screen.w + 2
      height: box.screen.h + 2
      radius: box.corner
      color: "transparent"
      border.width: root.targeted ? Tokens.dropLine : 1
      border.color: root.targeted ? Tokens.dropOutline : Tokens.miniMapLine
    }
  }
}
