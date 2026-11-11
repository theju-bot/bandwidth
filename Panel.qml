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
  property var topDownloads: []
  property var topUploads: []
  property var daysHistory: []

  // Active tab: 0 = Downloads, 1 = Uploads, 2 = History
  property int currentTab: 0

  // Minimalistic toggle
  property bool minimalistic: false

  function setMinimalistic(val) {
    root.minimalistic = val;
    setMinimalProc.command = ["python3", root.pluginDir + "/bin/collector.py", "set-minimal", val ? "true" : "false"];
    setMinimalProc.running = true;
  }

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

  // Save minimal state process
  Process {
    id: setMinimalProc
    running: false
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
          root.topDownloads = d.top_downloads || [];
          root.topUploads = d.top_uploads || [];
          root.daysHistory = d.days || [];
          if (d.minimalistic !== undefined) {
            root.minimalistic = Boolean(d.minimalistic);
          }
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

  readonly property double maxDownloadUsage: {
    var max = 1;
    var list = root.topDownloads || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].down > max) max = list[i].down;
    }
    return max;
  }

  readonly property double maxUploadUsage: {
    var max = 1;
    var list = root.topUploads || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].up > max) max = list[i].up;
    }
    return max;
  }

  readonly property double maxDailyUsage: {
    var max = 1;
    var list = root.daysHistory || [];
    for (var i = 0; i < list.length; i++) {
      if (list[i].total > max) max = list[i].total;
    }
    return max;
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(410))
    // Scrollable bounded height
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
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: column
          width: flick.width - Style.space(4)
          spacing: Style.space(12)

          // ---------- Header ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(headerLeftRow.implicitHeight, trailingControlItem.implicitHeight)

            Row {
              id: headerLeftRow
              anchors.left: parent.left
              anchors.right: trailingControlItem.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(12)

              Text {
                visible: !root.minimalistic
                text: "󰖟"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.space(32)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

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
                  font.bold: true
                  font.letterSpacing: 1.2
                }
              }
            }

            // Trailing Minimal switch
            Item {
              id: trailingControlItem
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              implicitWidth: switchRow.implicitWidth
              implicitHeight: switchRow.implicitHeight

              Row {
                id: switchRow
                spacing: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  textFormat: Text.PlainText
                  text: "Minimal"
                  color: root.minimalistic ? root.downAccent : root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.minimalistic
                  anchors.verticalCenter: parent.verticalCenter
                }

                ToggleSwitch {
                  id: miniSwitch
                  trackHeight: 16
                  interactive: false
                  checked: root.minimalistic
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setMinimalistic(!root.minimalistic)
              }
            }
          }

          // ---------- Traffic Readout: Download, Upload, Total ----------
          Row {
            spacing: Style.space(12)
            anchors.left: parent.left
            anchors.leftMargin: Style.space(4)

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
                Text { text: "⚠️"; font.pixelSize: Style.font.body }
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
          // SEGMENTED TABS: Downloads | Uploads | History
          // ==========================================
          Row {
            width: parent.width
            spacing: Style.space(8)

            // Tab 0: Downloads
            BorderSurface {
              width: (parent.width - Style.space(16)) / 3
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius
              color: root.currentTab === 0 ? Qt.rgba(0.22, 0.74, 0.97, 0.20) : Qt.rgba(1, 1, 1, 0.04)
              borderSpec: Border.flat(root.currentTab === 0 ? root.downAccent : Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)
                Text {
                  visible: !root.minimalistic
                  text: "📥"
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: "Downloads"
                  color: root.currentTab === 0 ? root.downAccent : root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.currentTab === 0
                  anchors.verticalCenter: parent.verticalCenter
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.currentTab = 0
              }
            }

            // Tab 1: Uploads
            BorderSurface {
              width: (parent.width - Style.space(16)) / 3
              implicitHeight: Style.space(34)
              radius: Style.cornerRadius
              color: root.currentTab === 1 ? Qt.rgba(0.75, 0.52, 0.99, 0.20) : Qt.rgba(1, 1, 1, 0.04)
              borderSpec: Border.flat(root.currentTab === 1 ? root.upAccent : Qt.rgba(1, 1, 1, 0.08), Math.max(1, Style.space(1)))

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)
                Text {
                  visible: !root.minimalistic
                  text: "📤"
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: "Uploads"
                  color: root.currentTab === 1 ? root.upAccent : root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.currentTab === 1
                  anchors.verticalCenter: parent.verticalCenter
                }
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

              Row {
                anchors.centerIn: parent
                spacing: Style.space(6)
                Text {
                  visible: !root.minimalistic
                  text: "📅"
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  textFormat: Text.PlainText
                  text: "History"
                  color: root.currentTab === 2 ? root.fg : root.dimFg
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: root.currentTab === 2
                  anchors.verticalCenter: parent.verticalCenter
                }
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
          // TAB 0: DOWNLOADS CONTENT
          // ==========================================
          Column {
            visible: root.currentTab === 0
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Top Download Apps"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].width - downBadge.width - Style.space(12))
                height: 1
              }

              BorderSurface {
                id: downBadge
                visible: !!root.topDownloads && root.topDownloads.length > 0
                implicitWidth: downBadgeText.implicitWidth + Style.space(14)
                implicitHeight: downBadgeText.implicitHeight + Style.space(4)
                color: Qt.rgba(0.22, 0.74, 0.97, 0.15)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: downBadgeText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.topDownloads.length + " apps"
                  color: root.downAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              visible: !root.topDownloads || root.topDownloads.length === 0
              textFormat: Text.PlainText
              width: parent.width
              text: "No download activity recorded yet today."
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.topDownloads

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: root.minimalistic ? Style.space(34) : Style.space(52)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                Item {
                  id: downRowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: root.minimalistic ? parent.verticalCenter : undefined
                  anchors.top: root.minimalistic ? undefined : parent.top
                  anchors.topMargin: root.minimalistic ? 0 : Style.space(8)
                  height: Math.max(downNameCol.implicitHeight, downValText.implicitHeight)

                  Row {
                    id: downLeftSide
                    anchors.left: parent.left
                    anchors.right: downValText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      visible: !root.minimalistic
                      text: Model.appEmoji(modelData.name)
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      id: downNameCol
                      width: parent.width - (parent.children[0].visible ? parent.children[0].width + parent.spacing : 0)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: !root.minimalistic
                        textFormat: Text.PlainText
                        text: "↑ " + Model.formatBytes(modelData.up)
                        color: root.dimFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    id: downValText
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

                Rectangle {
                  visible: !root.minimalistic
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(8)
                  height: Style.space(3)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Rectangle {
                    width: Math.max(Style.space(4), parent.width * Math.min(1.0, (modelData.down || 0) / Math.max(1, root.maxDownloadUsage)))
                    height: parent.height
                    radius: Style.cornerRadius
                    color: root.downAccent
                  }
                }
              }
            }
          }

          // ==========================================
          // TAB 1: UPLOADS CONTENT
          // ==========================================
          Column {
            visible: root.currentTab === 1
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Top Upload Apps"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].width - upBadge.width - Style.space(12))
                height: 1
              }

              BorderSurface {
                id: upBadge
                visible: !!root.topUploads && root.topUploads.length > 0
                implicitWidth: upBadgeText.implicitWidth + Style.space(14)
                implicitHeight: upBadgeText.implicitHeight + Style.space(4)
                color: Qt.rgba(0.75, 0.52, 0.99, 0.15)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: upBadgeText
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: root.topUploads.length + " apps"
                  color: root.upAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }
            }

            Text {
              visible: !root.topUploads || root.topUploads.length === 0
              textFormat: Text.PlainText
              width: parent.width
              text: "No upload activity recorded yet today."
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.topUploads

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: root.minimalistic ? Style.space(34) : Style.space(52)
                color: Qt.rgba(1, 1, 1, 0.03)
                radius: Style.cornerRadius
                borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.06), Math.max(1, Style.space(1)))

                Item {
                  id: upRowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: root.minimalistic ? parent.verticalCenter : undefined
                  anchors.top: root.minimalistic ? undefined : parent.top
                  anchors.topMargin: root.minimalistic ? 0 : Style.space(8)
                  height: Math.max(upNameCol.implicitHeight, upValText.implicitHeight)

                  Row {
                    id: upLeftSide
                    anchors.left: parent.left
                    anchors.right: upValText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      visible: !root.minimalistic
                      text: Model.appEmoji(modelData.name)
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      id: upNameCol
                      width: parent.width - (parent.children[0].visible ? parent.children[0].width + parent.spacing : 0)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        text: modelData.name
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: true
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: !root.minimalistic
                        textFormat: Text.PlainText
                        text: "↓ " + Model.formatBytes(modelData.down)
                        color: root.dimFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Text {
                    id: upValText
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

                Rectangle {
                  visible: !root.minimalistic
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(8)
                  height: Style.space(3)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Rectangle {
                    width: Math.max(Style.space(4), parent.width * Math.min(1.0, (modelData.up || 0) / Math.max(1, root.maxUploadUsage)))
                    height: parent.height
                    radius: Style.cornerRadius
                    color: root.upAccent
                  }
                }
              }
            }
          }

          // ==========================================
          // TAB 2: DAILY HISTORY CONTENT
          // ==========================================
          Column {
            visible: root.currentTab === 2
            width: parent.width
            spacing: Style.space(8)

            Row {
              width: parent.width

              Text {
                textFormat: Text.PlainText
                text: "Daily Bandwidth History"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                anchors.verticalCenter: parent.verticalCenter
              }

              Item {
                width: Math.max(0, parent.width - parent.children[0].width - daysBadge.width - Style.space(12))
                height: 1
              }

              BorderSurface {
                id: daysBadge
                visible: !!root.daysHistory && root.daysHistory.length > 0
                implicitWidth: daysBadgeText.implicitWidth + Style.space(14)
                implicitHeight: daysBadgeText.implicitHeight + Style.space(4)
                color: Qt.rgba(1, 1, 1, 0.08)
                radius: Style.cornerRadius
                anchors.verticalCenter: parent.verticalCenter

                Text {
                  id: daysBadgeText
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

            Repeater {
              model: root.daysHistory

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: root.minimalistic ? Style.space(34) : Style.space(52)
                color: modelData.is_today ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(1, 1, 1, 0.02)
                radius: Style.cornerRadius
                borderSpec: Border.flat(modelData.is_today ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05), Math.max(1, Style.space(1)))

                Item {
                  id: dayRowContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: root.minimalistic ? parent.verticalCenter : undefined
                  anchors.top: root.minimalistic ? undefined : parent.top
                  anchors.topMargin: root.minimalistic ? 0 : Style.space(8)
                  height: Math.max(dayCol.implicitHeight, dayValText.implicitHeight)

                  Row {
                    id: dayLeftSide
                    anchors.left: parent.left
                    anchors.right: dayValText.left
                    anchors.rightMargin: Style.space(8)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)

                    Text {
                      visible: !root.minimalistic
                      text: modelData.is_today ? "🌟" : "🗓️"
                      font.pixelSize: Style.font.body
                      anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                      id: dayCol
                      width: parent.width - (parent.children[0].visible ? parent.children[0].width + parent.spacing : 0)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(1)

                      Text {
                        textFormat: Text.PlainText
                        text: Model.formatDate(modelData.date, modelData.is_today)
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        font.bold: modelData.is_today
                        elide: Text.ElideRight
                        width: parent.width
                      }

                      Text {
                        visible: !root.minimalistic
                        textFormat: Text.PlainText
                        text: "↓ " + Model.formatBytes(modelData.down) + "  ·  ↑ " + Model.formatBytes(modelData.up)
                        color: root.dimFg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
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

                Rectangle {
                  visible: !root.minimalistic
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.bottomMargin: Style.space(8)
                  height: Style.space(3)
                  radius: Style.cornerRadius
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Rectangle {
                    width: Math.max(Style.space(4), parent.width * Math.min(1.0, (modelData.total || 0) / Math.max(1, root.maxDailyUsage)))
                    height: parent.height
                    radius: Style.cornerRadius
                    color: modelData.is_today ? Color.accent : Qt.darker(Color.accent, 1.3)
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
