import QtQuick
import qs.Commons
import qs.Ui

// Bar entry for the lights widget. Mirrors omarchy.weather's BarWidget: the
// pill is a BarIconButton and all state lives in Panel.qml.
BarWidget {
  id: root
  moduleName: "vscarpenter.ha-lights"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Shape contract for shell.summon/hide/toggle routing (see omarchy.weather).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

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
    // nf-md-lightbulb when anything is on, nf-md-lightbulb_outline otherwise.
    text: panelLoader.item && panelLoader.item.onCount > 0 ? "󰌵" : "󰌶"
    tooltipText: panelLoader.item ? panelLoader.item.tooltip : ""

    onPressed: function(b) {
      if (!panelLoader.item) return
      if (b === Qt.RightButton) panelLoader.item.allOff()
      else if (b === Qt.MiddleButton) panelLoader.item.refresh()
      else root.togglePanel()
    }
  }
}
