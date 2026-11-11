import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bandwidth Usage: Bar widget and host for the panel
BarWidget {
  id: root
  moduleName: "theju-bot.bandwidth"

  readonly property var panel: panelLoader.item
  readonly property string markGlyph: "󰖟"

  readonly property double todayTotal: panel ? panel.todayTotal : 0
  readonly property string status: panel ? panel.status : "ok"
  readonly property string pillText: {
    if (root.status === "error") return root.markGlyph + " !"
    return root.markGlyph + " " + Model.formatBytes(root.todayTotal)
  }

  // Panel routing contract
  readonly property bool opened: panel ? panel.opened === true : false
  readonly property bool popoutSwitchClosing: panel ? panel.popoutSwitchClosing === true : false

  function open() { if (panel) panel.open() }
  function close() { if (panel) panel.close() }
  function togglePanel() { if (panel) panel.toggle() }
  function closeForPopoutSwitch() { if (panel) panel.closeForPopoutSwitch() }
  function refresh() { if (panel) panel.refresh() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
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

  IpcHandler {
    target: "bandwhich-usage"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { root.refresh() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    horizontalMargin: 6
    hasVisualContent: text !== ""
    tooltipText: panel && panel.status === "error"
      ? (panel.errorMessage || (panel.errorType === "not_installed" ? "bandwhich is not installed (sudo pacman -S bandwhich)" : "bandwhich permission required"))
      : "Internet Usage Today: " + Model.formatBytes(root.todayTotal)
        + (panel ? " (↓ " + Model.formatBytes(panel.todayDown) + "  ↑ " + Model.formatBytes(panel.todayUp) + ")" : "")
        + (panel && panel.currentTotalBps > 0 ? " · " + Model.formatSpeed(panel.currentTotalBps) : "")

    onPressed: function(b) {
      root.togglePanel()
    }
  }
}
