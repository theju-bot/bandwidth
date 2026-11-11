import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "theju-bot.bandwidth"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string pluginDir: {
    var s = String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "");
    try { return decodeURIComponent(s); } catch (e) { return s; }
  }

  // Live state
  property double todayDown: 0
  property double todayUp: 0
  property double todayTotal: 0
  property double currentDownBps: 0
  property double currentUpBps: 0
  property double currentTotalBps: 0

  property string status: "ok"
  property string errorMessage: ""
  property string errorType: ""
  property var currentApps: []
  property var topDownloads: []
  property var topUploads: []
  property var daysHistory: []

  // Active tab: 0 = Usage, 1 = Current, 2 = History
  property int currentTab: 0

  readonly property string fontFamily: Style.font.family
  readonly property color fg: root.bar ? root.bar.barForeground : Color.foreground
  readonly property color dimFg: Qt.darker(fg, 1.45)
  readonly property color downAccent: "#38bdf8"
  readonly property color upAccent: "#c084fc"

  function refresh() {
    if (!statusProc.running) statusProc.running = true;
  }

  onOpenedChanged: {
    if (opened) root.refresh();
  }

  // Background daemon
  Process {
    id: daemonProc
    running: true
    command: ["python3", root.pluginDir + "/bin/collector.py", "daemon"]
  }

  // Poller (refresh every 1.5 seconds for live speeds)
  Process {
    id: statusProc
    running: false
    command: ["python3", root.pluginDir + "/bin/collector.py", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var out = String(this.text).trim();
        if (!out) return;
        try {
          var d = JSON.parse(out);
          root.todayDown = Number(d.today_down) || 0;
          root.todayUp = Number(d.today_up) || 0;
          root.todayTotal = Number(d.total) || (root.todayDown + root.todayUp);
          root.currentDownBps = Number(d.current_down_bps) || 0;
          root.currentUpBps = Number(d.current_up_bps) || 0;
          root.currentTotalBps = Number(d.current_total_bps) || (root.currentDownBps + root.currentUpBps);
          root.status = d.status || "ok";
          root.errorMessage = d.error || "";
          root.errorType = d.error_type || (root.errorMessage.indexOf("not installed") !== -1 ? "not_installed" : "permission");
          root.currentApps = d.current_apps || [];
          root.topDownloads = d.top_downloads || [];
          root.topUploads = d.top_uploads || [];
          root.daysHistory = d.days || [];
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 1500
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(390))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar {
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

          // ---------- Header Row (Clean, no redundant total badge) ----------
          Row {
            id: titleArea
            width: parent.width
            spacing: Style.space(8)

            Text {
              text: "󰖟"
              font.family: "Symbols Nerd Font"
              font.pixelSize: Style.space(22)
              color: root.fg
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)

              Text {
                textFormat: Text.PlainText
                text: "Internet Usage"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
              }

              Text {
                textFormat: Text.PlainText
                text: "TODAY'S BANDWIDTH (BANDWHICH)"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // ---------- Cumulative Traffic (Download first, Upload second, then Total) ----------
          Row {
            spacing: Style.space(10)
            anchors.left: parent.left

            // Download
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "↓"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Model.formatBytes(root.todayDown)
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            // Upload
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "↑"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Model.formatBytes(root.todayUp)
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            // Total
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "Total:"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Model.formatBytes(root.todayTotal)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // ---------- Current Speed (Download speed first, Upload speed second) ----------
          Row {
            spacing: Style.space(10)
            anchors.left: parent.left

            Text {
              textFormat: Text.PlainText
              text: "Current:"
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }

            // Download speed
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "↓"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Model.formatSpeed(root.currentDownBps)
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }

            // Upload speed
            Row {
              spacing: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              Text {
                textFormat: Text.PlainText
                text: "↑"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
              Text {
                textFormat: Text.PlainText
                text: Model.formatSpeed(root.currentUpBps)
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // Error banner
          BorderSurface {
            visible: root.status === "error"
            width: parent.width
            implicitHeight: errCol.implicitHeight + Style.space(16)
            color: Qt.rgba(0.9, 0.2, 0.2, 0.12)
            borderSpec: Border.flat(Qt.rgba(0.9, 0.2, 0.2, 0.4), Math.max(1, Style.space(1)))
            radius: Style.cornerRadius

            Column {
              id: errCol
              anchors.fill: parent
              anchors.margins: Style.space(8)
              spacing: Style.space(6)

              Row {
                spacing: Style.space(6)
                Text {
                  textFormat: Text.PlainText
                  text: "!"
                  color: "#f87171"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  text: root.errorType === "not_installed"
                    ? "bandwhich is not installed"
                    : "Packet capture permission needed"
                  color: "#f87171"
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                }
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.Wrap
                text: root.errorType === "not_installed"
                  ? "Install bandwhich using your package manager to enable tracking:"
                  : "bandwhich needs network packet inspection capabilities. Run in terminal:"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Rectangle {
                width: parent.width
                implicitHeight: cmdText.implicitHeight + Style.space(12)
                color: Qt.rgba(0, 0, 0, 0.4)
                radius: Style.cornerRadius

                Text {
                  id: cmdText
                  textFormat: Text.PlainText
                  anchors.fill: parent
                  anchors.margins: Style.space(6)
                  wrapMode: Text.WrapAnywhere
                  font.family: "monospace"
                  font.pixelSize: Style.font.caption
                  color: "#68d391"
                  text: root.errorType === "not_installed"
                    ? "sudo pacman -S bandwhich"
                    : "sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' $(which bandwhich)"
                }
              }
            }
          }

          // ==========================================
          // TEXT TABS: Usage | Current | History
          // (Clean text with underline active indicator)
          // ==========================================
          Row {
            width: parent.width
            spacing: Style.space(24)

            // Tab 0: Usage
            Item {
              width: usageTabTxt.implicitWidth
              height: Style.space(28)

              Text {
                id: usageTabTxt
                textFormat: Text.PlainText
                text: "Usage"
                color: root.currentTab === 0 ? root.fg : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.currentTab === 0
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Rectangle {
                visible: root.currentTab === 0
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                radius: 1
                color: root.downAccent
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 0
              }
            }

            // Tab 1: Current
            Item {
              width: currTabTxt.implicitWidth
              height: Style.space(28)

              Text {
                id: currTabTxt
                textFormat: Text.PlainText
                text: "Current"
                color: root.currentTab === 1 ? root.fg : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.currentTab === 1
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Rectangle {
                visible: root.currentTab === 1
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                radius: 1
                color: root.upAccent
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 1
              }
            }

            // Tab 2: History
            Item {
              width: histTabTxt.implicitWidth
              height: Style.space(28)

              Text {
                id: histTabTxt
                textFormat: Text.PlainText
                text: "History"
                color: root.currentTab === 2 ? root.fg : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.currentTab === 2
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
              }

              Rectangle {
                visible: root.currentTab === 2
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 2
                radius: 1
                color: root.fg
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 2
              }
            }
          }

          PanelSeparator { width: parent.width }

          // ==========================================
          // TAB 0: USAGE CONTENT
          // (Download first, Upload second)
          // ==========================================
          Column {
            visible: root.currentTab === 0
            width: parent.width
            spacing: Style.space(10)

            // Top Downloads Section (Download First!)
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Top Download Apps"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: root.topDownloads

                delegate: BorderSurface {
                  required property var modelData
                  width: column.width
                  implicitHeight: Style.space(34)
                  color: Qt.rgba(1, 1, 1, 0.03)
                  radius: Style.cornerRadius
                  borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                  Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    height: dNameText.implicitHeight

                    Text {
                      id: dNameText
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.right: dValText.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      id: dValText
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.formatBytes(modelData.down)
                      color: root.downAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }
              }
            }

            // Top Uploads Section (Upload Second!)
            Column {
              width: parent.width
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Top Upload Apps"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Repeater {
                model: root.topUploads

                delegate: BorderSurface {
                  required property var modelData
                  width: column.width
                  implicitHeight: Style.space(34)
                  color: Qt.rgba(1, 1, 1, 0.03)
                  radius: Style.cornerRadius
                  borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                  Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(10)
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    height: nameText.implicitHeight

                    Text {
                      id: nameText
                      textFormat: Text.PlainText
                      anchors.left: parent.left
                      anchors.right: valText.left
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      text: modelData.name
                      color: root.fg
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      id: valText
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: Model.formatBytes(modelData.up)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }
                }
              }
            }
          }

          // ==========================================
          // TAB 1: CURRENT LIVE APP SPEEDS (MB/s or KB/s)
          // ==========================================
          Column {
            visible: root.currentTab === 1
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Current App Speeds"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].width - currBadge.width - Style.space(12))
                height: 1
              }

              BorderSurface {
                id: currBadge
                visible: !!root.currentApps && root.currentApps.length > 0
                implicitWidth: currBadgeText.implicitWidth + Style.space(14)
                implicitHeight: currBadgeText.implicitHeight + Style.space(4)
                color: Qt.rgba(0.75, 0.52, 0.99, 0.15)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: currBadgeText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.currentApps.length + " active"
                  color: root.upAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              visible: !root.currentApps || root.currentApps.length === 0
              textFormat: Text.PlainText
              width: parent.width
              text: "No active network transfers at the moment."
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.currentApps

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: Style.space(34)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                Item {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: curName.implicitHeight

                  Text {
                    id: curName
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: curMidDetails.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  // Mid detail: Download speed first, upload speed second
                  Row {
                    id: curMidDetails
                    anchors.right: curVal.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      text: "↓ " + Model.formatSpeed(modelData.down_bps)
                      color: root.downAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "↑ " + Model.formatSpeed(modelData.up_bps)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    id: curVal
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatSpeed(modelData.total_bps)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }
            }
          }

          // ==========================================
          // TAB 2: HISTORY CONTENT
          // ==========================================
          Column {
            visible: root.currentTab === 2
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Daily History"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].width - histBadge.width - Style.space(12))
                height: 1
              }

              BorderSurface {
                id: histBadge
                visible: !!root.daysHistory && root.daysHistory.length > 0
                implicitWidth: histBadgeText.implicitWidth + Style.space(14)
                implicitHeight: histBadgeText.implicitHeight + Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.08)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: histBadgeText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.daysHistory.length + " days"
                  color: root.fg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              visible: !root.daysHistory || root.daysHistory.length === 0
              textFormat: Text.PlainText
              width: parent.width
              text: "No historical usage data recorded yet."
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.daysHistory

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: Style.space(34)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                Item {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(12)
                  anchors.verticalCenter: parent.verticalCenter
                  height: dayDateText.implicitHeight

                  Text {
                    id: dayDateText
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: dayMidDetails.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatDate(modelData.date, modelData.is_today)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: modelData.is_today
                    elide: Text.ElideRight
                  }

                  // Mid detail: Download first, then upload
                  Row {
                    id: dayMidDetails
                    anchors.right: dayValText.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      text: "↓ " + Model.formatBytes(modelData.down)
                      color: root.downAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "↑ " + Model.formatBytes(modelData.up)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  Text {
                    id: dayValText
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatBytes(modelData.total)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
