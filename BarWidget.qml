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
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("nightMan" in target) target.nightMan = root.nightMan
  }

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onNightManChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    active: root.overridden
    tooltipText: root.nightMan ? root.nightMan.statusText() : "NightMan"

    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.togglePanel()
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
