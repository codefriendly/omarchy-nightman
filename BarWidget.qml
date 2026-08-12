import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "codefriendly.nightman"

  readonly property var nightMan: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
  readonly property string mode: nightMan ? nightMan.mode : ""
  readonly property bool overridden: nightMan ? nightMan.overrideActive : false
  readonly property string glyph: mode === "light" ? "☀" : (mode === "dark" ? "☾" : "◌")
  readonly property string tooltip: {
    if (!nightMan) return "NightMan is starting"
    var label = mode === "light" ? "Light" : "Dark"
    var detail = overridden ? "manual override until the next transition" : "automatic " + nightMan.scheduleSource + " schedule"
    return "NightMan: " + label + " (" + detail + ")"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.overridden
    tooltipText: root.tooltip

    onPressed: function(mouseButton) {
      if (!root.nightMan) return
      if (mouseButton === Qt.RightButton) root.nightMan.clearOverride(true)
      else root.nightMan.toggleManual()
    }
  }

  Rectangle {
    visible: root.overridden
    width: 5
    height: 5
    radius: 3
    color: root.bar ? root.bar.urgent : Color.urgent
    anchors.right: parent.right
    anchors.rightMargin: 3
    anchors.top: parent.top
    anchors.topMargin: 3
  }
}
