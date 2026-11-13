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
  readonly property string markGlyph: "󱘖"

  readonly property double todayTotal: panel ? panel.todayTotal : 0
  readonly property double currentDownBps: panel ? panel.currentDownBps : 0
  readonly property double currentUpBps: panel ? panel.currentUpBps : 0
  readonly property string status: panel ? panel.status : "ok"

  // 0: Total data for the day
  // 1: Current data download speed
  // 2: Current data upload speed
  property int displayMode: 0

  readonly property string pillText: {
    if (root.status === "error") return root.markGlyph + " !"
    if (root.displayMode === 1) {
      return root.markGlyph + " ↓ " + Model.formatSpeed(root.currentDownBps)
    } else if (root.displayMode === 2) {
      return root.markGlyph + " ↑ " + Model.formatSpeed(root.currentUpBps)
    } else {
      return root.markGlyph + " " + Model.formatBytes(root.todayTotal, 2)
    }
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
      : (root.displayMode === 0 ? "Total Today: " + Model.formatBytes(root.todayTotal, 2)
          : (root.displayMode === 1 ? "Download Speed: " + Model.formatSpeed(root.currentDownBps)
             : "Upload Speed: " + Model.formatSpeed(root.currentUpBps)))
        + " (Right-click to cycle)\n"
        + "Today: ↓ " + Model.formatBytes(panel ? panel.todayDown : 0, 2) + "  ↑ " + Model.formatBytes(panel ? panel.todayUp : 0, 2) + "\n"
        + "Live: ↓ " + Model.formatSpeed(root.currentDownBps) + "  ↑ " + Model.formatSpeed(root.currentUpBps)

    onPressed: function(b) {
      if (b === Qt.RightButton) {
        root.displayMode = (root.displayMode + 1) % 3
      } else {
        root.togglePanel()
      }
    }
  }
}
