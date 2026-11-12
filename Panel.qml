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
  property var overviewApps: []
  property var currentApps: []
  property var daysHistory: []

  // Active tab: 0 = Overview, 1 = Live Activity, 2 = Usage History
  property int currentTab: 0

  property bool themeAware: false
  property var themePalette: ({})

  readonly property string fontFamily: Style.font.family
  readonly property color fg: root.themeAware ? (Color.popups.text || Color.foreground) : (root.bar ? root.bar.barForeground : Color.foreground)
  readonly property color dimFg: root.themeAware ? (Color.muted || Qt.darker(fg, 1.45)) : Qt.darker(fg, 1.45)
  readonly property color downAccent: root.themeAware ? (root.themePalette.cyan || root.themePalette.blue || Color.accent || "#38bdf8") : "#38bdf8"
  readonly property color upAccent: root.themeAware ? (root.themePalette.magenta || root.themePalette.accent || Color.urgent || "#c084fc") : "#c084fc"
  readonly property color cardBg: root.themeAware ? Util.alpha(Color.popups.text || Color.foreground, 0.04) : Qt.rgba(1, 1, 1, 0.03)
  readonly property color cardBorder: root.themeAware ? Util.alpha(Color.popups.border || Color.foreground, 0.12) : Qt.rgba(1, 1, 1, 0.06)

  function parseThemeColors(raw) {
    var lines = String(raw || "").split("\n");
    var pal = {};
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/);
      if (match) {
        pal[match[1]] = match[2];
      }
    }
    root.themePalette = pal;
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.parseThemeColors(text())
    onFileChanged: reload()
  }

  FileView {
    id: configFileView
    path: Quickshell.env("HOME") + "/.local/state/omarchy/theju-bot.bandwidth/config.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        var c = JSON.parse(text());
        if (c && typeof c.theme_aware === "boolean") {
          root.themeAware = c.theme_aware;
        }
      } catch (e) {}
    }
    onFileChanged: reload()
  }

  Process {
    id: setThemeAwareProc
    running: false
    property string targetVal: "0"
    command: ["python3", root.pluginDir + "/bin/collector.py", "set-theme-aware", targetVal]
  }

  function toggleThemeAware() {
    root.themeAware = !root.themeAware;
    setThemeAwareProc.targetVal = root.themeAware ? "1" : "0";
    setThemeAwareProc.running = true;
  }

  Component.onCompleted: {
    if (themeColorsFile.text()) root.parseThemeColors(themeColorsFile.text());
  }

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
          root.overviewApps = d.overview_apps || [];
          root.currentApps = d.current_apps || [];
          root.daysHistory = d.days || [];
          if (typeof d.theme_aware === "boolean" && !setThemeAwareProc.running) {
            root.themeAware = d.theme_aware;
          }
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
          policy: ScrollBar.AsNeeded
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(8)

          // ---------- Header Row ----------
          Item {
            id: titleArea
            width: parent.width
            implicitHeight: Math.max(leftHeader.implicitHeight, rightHeader.implicitHeight)

            Row {
              id: leftHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(8)

              Text {
                text: "󱘖"
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

            Row {
              id: rightHeader
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Theme"
                color: root.themeAware ? root.fg : root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: root.themeAware
                anchors.verticalCenter: parent.verticalCenter

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleThemeAware()
                }
              }

              ToggleSwitch {
                id: themeSwitch
                anchors.verticalCenter: parent.verticalCenter
                checked: root.themeAware
                onToggled: root.toggleThemeAware()
              }
            }
          }

          // ---------- Bandwidth Metric Cards (Upload on left, Download on right, Live speeds beneath) ----------
          Row {
            width: parent.width
            spacing: Style.space(8)

            // Upload Metric Card
            BorderSurface {
              id: upMetricCard
              width: Math.floor((parent.width - Style.space(8)) / 2)
              implicitHeight: Style.space(60)
              color: root.cardBg
              radius: Style.cornerRadius
              borderSpec: Border.flat(root.cardBorder, Math.max(1, Style.space(1)))

              Column {
                anchors.centerIn: parent
                spacing: Style.space(2)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: "↑ Upload"
                  color: root.upAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: Model.formatBytes(root.todayUp)
                  color: root.upAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(18)
                  font.bold: true
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(3)

                  Text {
                    textFormat: Text.PlainText
                    text: "Live:"
                    color: root.dimFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatSpeed(root.currentUpBps)
                    color: root.upAccent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }

            // Download Metric Card
            BorderSurface {
              id: downMetricCard
              width: parent.width - Style.space(8) - upMetricCard.width
              implicitHeight: Style.space(60)
              color: root.cardBg
              radius: Style.cornerRadius
              borderSpec: Border.flat(root.cardBorder, Math.max(1, Style.space(1)))

              Column {
                anchors.centerIn: parent
                spacing: Style.space(2)

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: "↓ Download"
                  color: root.downAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Text {
                  anchors.horizontalCenter: parent.horizontalCenter
                  textFormat: Text.PlainText
                  text: Model.formatBytes(root.todayDown)
                  color: root.downAccent
                  font.family: root.fontFamily
                  font.pixelSize: Style.space(18)
                  font.bold: true
                }

                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(3)

                  Text {
                    textFormat: Text.PlainText
                    text: "Live:"
                    color: root.dimFg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    textFormat: Text.PlainText
                    text: Model.formatSpeed(root.currentDownBps)
                    color: root.downAccent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }
              }
            }
          }

          // Total Transferred (Subtle secondary metric)
          Item {
            width: parent.width
            implicitHeight: totalRow.implicitHeight

            Row {
              id: totalRow
              anchors.centerIn: parent
              spacing: Style.space(6)

              Text {
                textFormat: Text.PlainText
                text: "Total data today:"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                textFormat: Text.PlainText
                text: Model.formatBytes(root.todayTotal)
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
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
          // TEXT TABS: Overview | Live Activity | Usage History
          // (3 equal sections: 33.33% each, centered labels and indicators)
          // ==========================================
          Row {
            id: tabsRow
            width: parent.width
            spacing: 0

            // Tab 0: Overview
            Item {
              id: tab0
              width: Math.floor(parent.width / 3)
              height: Style.space(28)

              Text {
                id: tab0Txt
                textFormat: Text.PlainText
                text: "Overview"
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
                anchors.horizontalCenter: parent.horizontalCenter
                width: tab0Txt.implicitWidth
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

            // Tab 1: Live Activity
            Item {
              id: tab1
              width: Math.floor(parent.width / 3)
              height: Style.space(28)

              Text {
                id: tab1Txt
                textFormat: Text.PlainText
                text: "Live Activity"
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
                anchors.horizontalCenter: parent.horizontalCenter
                width: tab1Txt.implicitWidth
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

            // Tab 2: Usage History
            Item {
              id: tab2
              width: parent.width - tab0.width - tab1.width
              height: Style.space(28)

              Text {
                id: tab2Txt
                textFormat: Text.PlainText
                text: "Usage History"
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
                anchors.horizontalCenter: parent.horizontalCenter
                width: tab2Txt.implicitWidth
                height: 2
                radius: 1
                color: root.themeAware ? (Color.accent || root.fg) : root.fg
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
          // TAB 0: OVERVIEW CONTENT
          // (Unified Apps List: Upload on left, Download on far right)
          // ==========================================
          Column {
            visible: root.currentTab === 0
            width: parent.width
            spacing: Style.space(8)

            // Column Headers
            Item {
              width: parent.width
              implicitHeight: Style.space(18)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "Application"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.right: ovDownHeader.left
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↑ Upload"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: ovDownHeader
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↓ Download"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            Text {
              visible: !root.overviewApps || root.overviewApps.length === 0
              textFormat: Text.PlainText
              width: parent.width
              text: "No network activity recorded yet today."
              color: root.dimFg
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Repeater {
              model: root.overviewApps

              delegate: BorderSurface {
                required property var modelData
                width: column.width
                implicitHeight: Style.space(34)
                color: root.cardBg
                radius: Style.cornerRadius
                borderSpec: Border.flat(root.cardBorder, Math.max(1, Style.space(1)))

                Item {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.leftMargin: Style.space(10)
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  height: ovName.implicitHeight

                  Text {
                    id: ovName
                    textFormat: Text.PlainText
                    anchors.left: parent.left
                    anchors.right: ovUpCol.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  // Upload column (left/middle)
                  Item {
                    id: ovUpCol
                    anchors.right: ovDownCol.left
                    anchors.rightMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↑ " + Model.formatBytes(modelData.up)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  // Download column (far right)
                  Item {
                    id: ovDownCol
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↓ " + Model.formatBytes(modelData.down)
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
          // TAB 1: LIVE ACTIVITY CONTENT
          // (Real-time speed: Upload on left, Download on far right, NO Total)
          // ==========================================
          Column {
            visible: root.currentTab === 1
            width: parent.width
            spacing: Style.space(8)

            // Column Headers
            Item {
              width: parent.width
              implicitHeight: Style.space(18)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "Application"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.right: liveDownHeader.left
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↑ Upload"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: liveDownHeader
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↓ Download"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
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
                color: root.cardBg
                radius: Style.cornerRadius
                borderSpec: Border.flat(root.cardBorder, Math.max(1, Style.space(1)))

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
                    anchors.right: liveUpCol.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  // Upload Speed column (left/middle)
                  Item {
                    id: liveUpCol
                    anchors.right: liveDownCol.left
                    anchors.rightMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↑ " + Model.formatSpeed(modelData.up_bps)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  // Download Speed column (far right)
                  Item {
                    id: liveDownCol
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↓ " + Model.formatSpeed(modelData.down_bps)
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
          // TAB 2: USAGE HISTORY CONTENT
          // (Upload on left, Download on far right)
          // ==========================================
          Column {
            visible: root.currentTab === 2
            width: parent.width
            spacing: Style.space(8)

            // Column Headers
            Item {
              width: parent.width
              implicitHeight: Style.space(18)

              Text {
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: "Date"
                color: root.dimFg
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                anchors.right: histDownHeader.left
                anchors.rightMargin: Style.space(16)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↑ Upload"
                color: root.upAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              Text {
                id: histDownHeader
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: Style.space(85)
                horizontalAlignment: Text.AlignRight
                text: "↓ Download"
                color: root.downAccent
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
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
                color: root.cardBg
                radius: Style.cornerRadius
                borderSpec: Border.flat(root.cardBorder, Math.max(1, Style.space(1)))

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
                    anchors.right: histUpCol.left
                    anchors.rightMargin: Style.space(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatDate(modelData.date, modelData.is_today)
                    color: root.fg
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: modelData.is_today
                    elide: Text.ElideRight
                  }

                  // Upload column (left/middle)
                  Item {
                    id: histUpCol
                    anchors.right: histDownCol.left
                    anchors.rightMargin: Style.space(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↑ " + Model.formatBytes(modelData.up)
                      color: root.upAccent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                  }

                  // Download column (far right)
                  Item {
                    id: histDownCol
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: Style.space(85)
                    height: parent.height

                    Text {
                      textFormat: Text.PlainText
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: "↓ " + Model.formatBytes(modelData.down)
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
        }
      }
    }
  }
}
