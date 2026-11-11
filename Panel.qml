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

  // Poller
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
    interval: 2000
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
    contentWidth: panel.fittedContentWidth(Style.space(410))
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
          id: vbar
          parent: panel
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.topMargin: Style.space(8)
          anchors.bottomMargin: Style.space(8)
          anchors.rightMargin: Style.space(4)
          policy: flick.contentHeight > flick.height ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          active: flick.moving || flick.fllicking || vbar.hovered
          interactive: true

          contentItem: Rectangle {
            implicitWidth: Style.space(4)
            radius: Style.cornerRadius
            color: vbar.pressed ? Color.accent : (vbar.hovered ? root.fg : Qt.rgba(1, 1, 1, 0.25))
          }
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)
          topPadding: Style.space(12)
          bottomPadding: Style.space(12)
          leftPadding: Style.space(12)
          rightPadding: Style.space(12)

          // ---------- Header ----------
          Row {
            width: parent.width
            height: Style.space(38)

            Row {
              id: titleArea
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
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

            // Right header badge: Total
            BorderSurface {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: totalBadgeText.implicitWidth + Style.space(16)
              implicitHeight: Style.space(26)
              radius: Style.cornerRadius
              color: Qt.rgba(1, 1, 1, 0.05)
              borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.12), Math.max(1, Style.space(1)))

              Text {
                id: totalBadgeText
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Model.formatBytes(root.todayTotal)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }
          }

          // ---------- Traffic Readout (Upload first on left, then Download, then Total) ----------
          Row {
            spacing: Style.space(12)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)

            // Upload
            Row {
              spacing: Style.space(5)
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

            // Separator dot
            Text {
              textFormat: Text.PlainText
              text: "·"
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              anchors.verticalCenter: parent.verticalCenter
            }

            // Download
            Row {
              spacing: Style.space(5)
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

            // Separator dot
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
              spacing: Style.space(5)
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
          // SEGMENTED TABS: Usage | Current | History
          // ==========================================
          Row {
            width: parent.width
            spacing: Style.space(8)

            // Tab 0: Usage
            BorderSurface {
              width: (parent.width - Style.space(16)) / 3
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius
              color: root.currentTab === 0 ? Qt.rgba(0.22, 0.74, 0.97, 0.18) : Qt.rgba(1, 1, 1, 0.04)
              borderSpec: Border.flat(root.currentTab === 0 ? root.downAccent : Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Usage"
                color: root.currentTab === 0 ? root.downAccent : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.currentTab === 0
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 0
              }
            }

            // Tab 1: Current
            BorderSurface {
              width: (parent.width - Style.space(16)) / 3
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius
              color: root.currentTab === 1 ? Qt.rgba(0.75, 0.52, 0.99, 0.18) : Qt.rgba(1, 1, 1, 0.04)
              borderSpec: Border.flat(root.currentTab === 1 ? root.upAccent : Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "Current"
                color: root.currentTab === 1 ? root.upAccent : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.currentTab === 1
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 1
              }
            }

            // Tab 2: History
            BorderSurface {
              width: (parent.width - Style.space(16)) / 3
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius
              color: root.currentTab === 2 ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.04)
              borderSpec: Border.flat(root.currentTab === 2 ? root.fg : Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: "History"
                color: root.currentTab === 2 ? root.fg : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.currentTab === 2
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
          // (Left side: Upload, Right side: Download)
          // ==========================================
          Column {
            visible: root.currentTab === 0
            width: parent.width
            spacing: Style.space(10)

            // Two summary cards: Upload on left, Download on right
            Row {
              width: parent.width
              spacing: Style.space(10)

              // Upload Card (Left)
              BorderSurface {
                width: (parent.width - Style.space(10)) / 2
                implicitHeight: Style.space(64)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      text: "↑ Upload"
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Model.formatBytes(root.todayUp)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(root.todayUp / (root.todayTotal || 1) * 100) + "% of total"
                    color: root.dimFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }

              // Download Card (Right)
              BorderSurface {
                width: (parent.width - Style.space(10)) / 2
                implicitHeight: Style.space(64)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(2)

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(4)
                    Text {
                      textFormat: Text.PlainText
                      text: "↓ Download"
                      color: root.downAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Model.formatBytes(root.todayDown)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.title
                    font.bold: true
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Math.round(root.todayDown / (root.todayTotal || 1) * 100) + "% of total"
                    color: root.dimFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // Ratio Proportion Bar
            Item {
              width: parent.width
              height: Style.space(6)

              Rectangle {
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Qt.rgba(1, 1, 1, 0.06)
                clip: true

                Row {
                  anchors.fill: parent

                  Rectangle {
                    width: parent.width * Math.min(1.0, root.todayUp / (root.todayTotal || 1))
                    height: parent.height
                    color: root.upAccent
                  }

                  Rectangle {
                    width: Math.max(0, parent.width - (parent.width * Math.min(1.0, root.todayUp / (root.todayTotal || 1))))
                    height: parent.height
                    color: root.downAccent
                  }
                }
              }
            }

            // Top Uploads Section
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
                model: (root.topUploads || []).slice(0, 4)

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
                    anchors.rightMargin: Style.space(10)
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

            // Top Downloads Section
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
                model: (root.topDownloads || []).slice(0, 4)

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
                    anchors.rightMargin: Style.space(10)
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
          }

          // ==========================================
          // TAB 1: CURRENT APPS USAGE
          // ==========================================
          Column {
            visible: root.currentTab === 1
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Current App Usage"
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
                  text: root.currentApps.length + " apps"
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
              text: "No network activity recorded yet today."
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
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  height: curName.implicitHeight

                  Text {
                    id: curName
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: curVal.left
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
                    id: curVal
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatBytes(modelData.total)
                    color: root.downAccent
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
                  anchors.rightMargin: Style.space(10)
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

                  // Mid detail: Upload first, then download
                  Row {
                    id: dayMidDetails
                    anchors.right: dayValText.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(6)

                    Text {
                      textFormat: Text.PlainText
                      text: "↑ " + Model.formatBytes(modelData.up)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    Text {
                      textFormat: Text.PlainText
                      text: "↓ " + Model.formatBytes(modelData.down)
                      color: root.downAccent
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
