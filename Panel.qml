// SPDX-FileCopyrightText: 2026 hrzlgnm
// SPDX-License-Identifier: MIT

import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// HeadsetControl bar widget: a bar icon showing headset state plus a popup
// panel to control everything HeadsetControl exposes for the connected
// device (sidetone, EQ presets, auto-off timer, mic LED, chatmix, ...).
//
// Ported from the Noctalia "headsetcontrol" plugin. The bar-widget entry
// point is the panel root (audio/power style), so `bar`, `moduleName` and
// `settings` arrive injected from the bar host.
Panel {
  id: root
  moduleName: "hrzlgnm.headsetcontrol"
  ipcTarget: "hrzlgnm.headsetcontrol"
  // manageIpc: false so this panel owns the single IpcHandler the target
  // permits — needed for the headset control methods below.
  manageIpc: false

  // The bar host sizes each widget slot from the widget root's implicit size
  // (see Bar.qml), so expose the button's here or the slot collapses to zero.
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ---- settings (inline shell.json layout entry, see BarWidget.setting) ----
  readonly property int pollingInterval: Math.max(0, parseInt(setting("pollingInterval", 30)) || 0)
  readonly property bool showPercentage: setting("barShowPercentage", true) === true
  property int lastSidetone: parseInt(setting("lastSidetone", 64)) || 64
  property int lastEqPreset: parseInt(setting("lastEqPreset", 0)) || 0

  // ---- live device state (from `headsetcontrol -o json`) ----
  property bool isDetected: false
  property bool isConnected: false
  property string deviceName: ""
  property int batteryLevel: -1
  property string batteryStatus: "BATTERY_UNAVAILABLE"
  property int chatmixLevel: -1
  property int eqPresetCount: 4
  property var capabilities: ({})

  readonly property bool isCharging: batteryStatus === "BATTERY_CHARGING"
  readonly property bool batteryReady: isConnected && batteryLevel >= 0

  // Found, but its battery is not reporting. Either the headset is off or the
  // dongle wants a replug, and nothing in the output tells the two apart.
  readonly property bool isSilent: isDetected && !isConnected

  // Capability flags gate every section of the panel.
  readonly property bool cSidetone: Model.hasCapability(capabilities, "CAP_SIDETONE")
  readonly property bool cLights: Model.hasCapability(capabilities, "CAP_LIGHTS")
  readonly property bool cInactiveTime: Model.hasCapability(capabilities, "CAP_INACTIVE_TIME")
  readonly property bool cEqPreset: Model.hasCapability(capabilities, "CAP_EQUALIZER_PRESET")
  readonly property bool cMicLed: Model.hasCapability(capabilities, "CAP_MICROPHONE_MUTE_LED_BRIGHTNESS")
  readonly property bool cVolumeLimiter: Model.hasCapability(capabilities, "CAP_VOLUME_LIMITER")
  readonly property bool cChatmix: Model.hasCapability(capabilities, "CAP_CHATMIX_STATUS")
  readonly property bool cNotificationSound: Model.hasCapability(capabilities, "CAP_NOTIFICATION_SOUND")
  readonly property bool cBtPowerOn: Model.hasCapability(capabilities, "CAP_BT_WHEN_POWERED_ON")
  readonly property bool cBtCallVolume: Model.hasCapability(capabilities, "CAP_BT_CALL_VOLUME")
  readonly property bool cVoicePrompts: Model.hasCapability(capabilities, "CAP_VOICE_PROMPTS")

  // ---- bar button ----
  readonly property string headsetGlyph: "󰋋"

  function barText() {
    if (!isConnected || !showPercentage || !batteryReady) return root.headsetGlyph
    return root.headsetGlyph + " " + batteryLevel + "%"
  }

  function barTooltip() {
    if (isSilent)
      return (deviceName !== "" ? deviceName : "Headset")
        + " · not reporting\nTurn the headset on, or replug the dongle"
    if (!isConnected) return "No headset detected"
    var parts = [deviceName]
    if (batteryReady) parts.push(batteryLevel + "%" + (isCharging ? " \u00b7 charging" : ""))
    return parts.join(" \u00b7 ")
  }

  // The percentage makes the button paint a text block wider than an icon, so
  // the open-panel mark takes the painted width instead of the icon-sized
  // fraction of the slot the fallback assumes.
  readonly property real openPanelIndicatorWidth: showPercentage && batteryReady && !button.vertical ? button.glyphPaintedWidth : 0

  // ---- process plumbing ----
  // One process does everything: with `-o json` the JSON state is printed for
  // plain queries *and* after set commands, so parsing the output is the same
  // either way. The `running` guard serializes overlapping calls.
  Process {
    id: commandProc
    command: ["headsetcontrol", "-o", "json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.handleOutput(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: { if (text) console.warn("HeadsetControl:", text.trim()) }
    }
  }

  function runCommand(args) {
    if (commandProc.running) return false
    commandProc.command = ["headsetcontrol", "-o", "json"].concat(args)
    commandProc.running = true
    return true
  }

  function checkConnected() {
    runCommand([])
  }

  function handleOutput(text) {
    var state = Model.parseState(text)
    if (!state) {
      console.warn("HeadsetControl: unparseable output")
      applyState(Model.disconnectedState())
      return
    }
    if (state.error) {
      console.warn("HeadsetControl:", state.error)
      return
    }
    applyState(state)
  }

  function applyState(state) {
    root.isDetected = state.detected === true
    root.isConnected = state.connected
    root.deviceName = state.deviceName || ""
    root.batteryLevel = state.batteryLevel
    root.batteryStatus = state.batteryStatus
    root.chatmixLevel = state.chatmixLevel
    root.eqPresetCount = state.eqPresetCount || 4
    root.capabilities = state.capabilities
  }

  // ---- settings persistence ----
  // Copy the current inline entry, overlay new values, and write it back to
  // shell.json via the same path the clock widget uses.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    for (var vk in values) entry[vk] = values[vk]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // ---- device actions ----
  function setSidetone(level) {
    root.lastSidetone = level
    persistSettings({ lastSidetone: level })
    runCommand(["-s", String(level)])
  }

  function setInactiveTime(minutes) {
    runCommand(["-i", String(minutes)])
  }

  function setEqPreset(preset) {
    root.lastEqPreset = preset
    persistSettings({ lastEqPreset: preset })
    runCommand(["-p", String(preset)])
  }

  function setMicLed(level) {
    runCommand(["--microphone-mute-led-brightness", String(level)])
  }

  function setBtCallVolume(volume) {
    runCommand(["--bt-call-volume", String(volume)])
  }

  // ---- multi-monitor relay ----
  // An IPC target only ever routes to one handler, but the bar surface exists
  // per monitor; relay the call to every live instance of this widget.
  function relay(method, args) {
    var items = root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      var w = items[i]
      if (w && typeof w[method] === "function") w[method].apply(w, args)
    }
  }

  // ---- lifecycle ----
  Timer {
    id: pollTimer
    interval: root.pollingInterval * 1000
    running: root.pollingInterval > 0
    repeat: true
    onTriggered: root.checkConnected()
  }

  onOpenedChanged: if (root.opened) root.checkConnected()

  Component.onCompleted: Qt.callLater(root.checkConnected)

  // ---- bar button ----
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barText()
    dimmed: !root.isConnected
    slotSize: Style.bar.iconSlot * (root.showPercentage && root.batteryReady && !vertical ? 2 : 1)
    tooltipText: root.barTooltip()
    onPressed: function(b) {
      if (b === Qt.RightButton) root.checkConnected()
      else root.toggle()
    }
  }

  // ---- popup panel ----
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero: glyph · title/status/device · battery ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            text: root.headsetGlyph
            color: root.isConnected ? root.barForeground : Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.iconLarge
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(12)
            anchors.verticalCenter: heroIcon.verticalCenter
            width: parent.width - heroIcon.width - Style.space(12)
            spacing: Style.space(2)

            Text {
              text: "HeadsetControl"
              color: root.barForeground
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: root.isConnected
                ? "Connected"
                : (root.isSilent ? "Not reporting" : "No headset detected")
              color: root.isConnected ? Color.accent : Qt.darker(root.barForeground, 1.4)
              font.pixelSize: Style.font.bodySmall
            }

            // The name is known as soon as the device is detected, so show it
            // even while the battery is silent - it is the clearest signal that
            // headsetcontrol did find the hardware.
            Text {
              visible: root.isDetected && root.deviceName !== ""
              text: root.deviceName
              color: Qt.darker(root.barForeground, 1.4)
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        // Says what is actually known and what to try, rather than leaving a
        // detected device looking like an absent one.
        Text {
          visible: root.isSilent
          width: parent.width
          text: "Battery is not reporting. Turn the headset on; if it is already on, unplug the dongle and plug it back in."
          color: Qt.darker(root.barForeground, 1.4)
          wrapMode: Text.WordWrap
          font.pixelSize: Style.font.caption
        }

        Row {
          visible: root.batteryReady
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: Model.batteryIcon(root.batteryLevel, root.batteryStatus)
            color: root.barForeground
            font.pixelSize: Style.font.body
          }

          Text {
            text: Model.batteryLabel(root.batteryLevel, root.batteryStatus)
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---------- Sidetone ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cSidetone
        }
        PanelSectionHeader {
          text: "Sidetone"
          visible: root.isConnected && root.cSidetone
        }
        Row {
          visible: root.isConnected && root.cSidetone
          width: parent.width
          spacing: Style.space(10)

          PanelSlider {
            width: parent.width - sidetoneLabel.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 128
            step: 1
            integer: true
            value: root.lastSidetone
            onMoved: function(v) { root.lastSidetone = Math.round(v) }
            onReleased: function(v) { root.setSidetone(Math.round(v)) }
            onRightClicked: root.setSidetone(0)
          }

          Text {
            id: sidetoneLabel
            text: root.lastSidetone
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }
        }

        // ---------- Lights ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cLights
        }
        PanelSectionHeader {
          text: "Lights"
          visible: root.isConnected && root.cLights
        }
        Row {
          visible: root.isConnected && root.cLights
          width: parent.width
          spacing: Style.space(8)
          Button { width: (parent.width - parent.spacing) / 2; text: "On"; onClicked: root.runCommand(["-l", "1"]) }
          Button { width: (parent.width - parent.spacing) / 2; text: "Off"; onClicked: root.runCommand(["-l", "0"]) }
        }

        // ---------- Auto-off timer ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cInactiveTime
        }
        PanelSectionHeader {
          text: "Auto-off timer (min)"
          visible: root.isConnected && root.cInactiveTime
        }
        Row {
          visible: root.isConnected && root.cInactiveTime
          width: parent.width
          spacing: Style.space(10)

          PanelSlider {
            width: parent.width - inactiveLabel.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 90
            step: 15
            integer: true
            value: root.inactiveTimeValue
            onReleased: function(v) { root.setInactiveTime(Math.round(v)) }
          }

          Text {
            id: inactiveLabel
            text: root.inactiveTimeValue === 0 ? "off" : String(root.inactiveTimeValue)
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }
        }

        // ---------- Equalizer preset ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cEqPreset
        }
        PanelSectionHeader {
          text: "Equalizer preset"
          visible: root.isConnected && root.cEqPreset
        }
        // Driven by the count HeadsetControl reports rather than a fixed four:
        // an Audeze Maxwell 2 has ten, so six of them used to be unreachable.
        Grid {
          id: eqGrid
          visible: root.isConnected && root.cEqPreset
          width: parent.width
          columns: Model.eqPresetColumns(root.deviceName)
          spacing: Style.space(8)
          Repeater {
            model: Model.eqPresetLabels(root.deviceName, root.eqPresetCount)
            Button {
              required property int index
              required property var modelData
              width: (eqGrid.width - eqGrid.spacing * (eqGrid.columns - 1)) / eqGrid.columns
              text: modelData
              selected: root.lastEqPreset === index
              onClicked: root.setEqPreset(index)
            }
          }
        }

        // ---------- Voice prompts ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cVoicePrompts
        }
        PanelSectionHeader {
          text: "Voice prompts"
          visible: root.isConnected && root.cVoicePrompts
        }
        Row {
          visible: root.isConnected && root.cVoicePrompts
          width: parent.width
          spacing: Style.space(8)
          Button { width: (parent.width - parent.spacing) / 2; text: "Enable"; onClicked: root.runCommand(["-v", "1"]) }
          Button { width: (parent.width - parent.spacing) / 2; text: "Disable"; onClicked: root.runCommand(["-v", "0"]) }
        }

        // ---------- Microphone LED brightness ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cMicLed
        }
        PanelSectionHeader {
          text: "Mic LED brightness"
          visible: root.isConnected && root.cMicLed
        }
        Row {
          visible: root.isConnected && root.cMicLed
          width: parent.width
          spacing: Style.space(10)

          PanelSlider {
            width: parent.width - micLedLabel.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 3
            step: 1
            integer: true
            value: root.micLedValue
            onReleased: function(v) { root.setMicLed(Math.round(v)) }
          }

          Text {
            id: micLedLabel
            text: root.micLedValue
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }
        }

        // ---------- Volume limiter ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cVolumeLimiter
        }
        PanelSectionHeader {
          text: "Volume limiter"
          visible: root.isConnected && root.cVolumeLimiter
        }
        Row {
          visible: root.isConnected && root.cVolumeLimiter
          width: parent.width
          spacing: Style.space(8)
          Button { width: (parent.width - parent.spacing) / 2; text: "On"; onClicked: root.runCommand(["--volume-limiter", "1"]) }
          Button { width: (parent.width - parent.spacing) / 2; text: "Off"; onClicked: root.runCommand(["--volume-limiter", "0"]) }
        }

        // ---------- Chatmix ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cChatmix
        }
        PanelSectionHeader {
          text: "Chatmix"
          visible: root.isConnected && root.cChatmix
        }
        Text {
          visible: root.isConnected && root.cChatmix
          text: Model.chatmixLabel(root.chatmixLevel)
          color: Qt.darker(root.barForeground, 1.4)
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- Notification sound ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && root.cNotificationSound
        }
        PanelSectionHeader {
          text: "Notification sound"
          visible: root.isConnected && root.cNotificationSound
        }
        Row {
          visible: root.isConnected && root.cNotificationSound
          width: parent.width
          spacing: Style.space(8)
          Button { width: (parent.width - parent.spacing) / 2; text: "0"; onClicked: root.runCommand(["-n", "0"]) }
          Button { width: (parent.width - parent.spacing) / 2; text: "1"; onClicked: root.runCommand(["-n", "1"]) }
        }

        // ---------- Bluetooth ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected && (root.cBtPowerOn || root.cBtCallVolume)
        }
        PanelSectionHeader {
          text: "Bluetooth"
          visible: root.isConnected && (root.cBtPowerOn || root.cBtCallVolume)
        }
        Row {
          visible: root.isConnected && root.cBtPowerOn
          width: parent.width
          spacing: Style.space(8)
          Button { width: (parent.width - parent.spacing) / 2; text: "Power on: On"; onClicked: root.runCommand(["--bt-when-powered-on", "1"]) }
          Button { width: (parent.width - parent.spacing) / 2; text: "Power on: Off"; onClicked: root.runCommand(["--bt-when-powered-on", "0"]) }
        }
        Row {
          visible: root.isConnected && root.cBtCallVolume
          width: parent.width
          spacing: Style.space(10)

          Text {
            text: "Call volume"
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
            verticalAlignment: Text.AlignVCenter
          }

          PanelSlider {
            width: parent.width - btVolLabel.implicitWidth - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            minimum: 0
            maximum: 100
            step: 1
            integer: true
            value: root.btCallVolumeValue
            onReleased: function(v) { root.setBtCallVolume(Math.round(v)) }
          }

          Text {
            id: btVolLabel
            text: root.btCallVolumeValue
            color: Qt.darker(root.barForeground, 1.4)
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignRight
          }
        }

        // ---------- Footer ----------
        PanelSeparator {
          width: parent.width
          visible: root.isConnected
        }

        Button {
          visible: root.isConnected
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Refresh"
          onClicked: root.checkConnected()
        }
      }
    }
  }

  property int inactiveTimeValue: 30
  property int micLedValue: 1
  property int btCallVolumeValue: 50

  // ---- IPC ----
  IpcHandler {
    target: "hrzlgnm.headsetcontrol"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.relay("checkConnected", []) }

    function checkConnected(): string {
      return JSON.stringify({
        connected: root.isConnected,
        deviceName: root.deviceName,
        batteryLevel: root.batteryLevel,
        batteryStatus: root.batteryStatus
      })
    }

    function setSidetone(level: string): string {
      var lvl = parseInt(level)
      if (isNaN(lvl) || lvl < 0 || lvl > 128) return JSON.stringify({ error: "Level must be 0-128" })
      root.relay("setSidetone", [lvl])
      return JSON.stringify({ success: true, level: lvl })
    }

    function setLights(on: string): string {
      var val = (on === "1" || on === "true") ? "1" : "0"
      root.relay("runCommand", [["-l", val]])
      return JSON.stringify({ success: true, lights: val === "1" })
    }

    function setInactiveTime(minutes: string): string {
      var min = parseInt(minutes)
      if (isNaN(min) || min < 0) return JSON.stringify({ error: "Minutes must be >= 0" })
      root.relay("runCommand", [["-i", String(min)]])
      return JSON.stringify({ success: true, minutes: min })
    }

    function setVoicePrompt(on: string): string {
      var val = (on === "1" || on === "true") ? "1" : "0"
      root.relay("runCommand", [["-v", val]])
      return JSON.stringify({ success: true, voicePrompt: val === "1" })
    }

    function setEqualizerPreset(preset: string): string {
      var p = parseInt(preset)
      if (isNaN(p) || p < 0 || p > 3) return JSON.stringify({ error: "Preset must be 0-3" })
      root.relay("setEqPreset", [p])
      return JSON.stringify({ success: true, preset: p })
    }

    function setEqualizer(curve: string): string {
      root.relay("runCommand", [["-e", curve]])
      return JSON.stringify({ success: true })
    }

    function setMicMuteLedBrightness(level: string): string {
      var lvl = parseInt(level)
      if (isNaN(lvl)) return JSON.stringify({ error: "Invalid brightness level" })
      root.relay("runCommand", [["--microphone-mute-led-brightness", String(lvl)]])
      return JSON.stringify({ success: true, level: lvl })
    }

    function setVolumeLimiter(on: string): string {
      var val = (on === "1" || on === "true") ? "1" : "0"
      root.relay("runCommand", [["--volume-limiter", val]])
      return JSON.stringify({ success: true, limiter: val === "1" })
    }

    function setBtPowerOn(on: string): string {
      var val = (on === "1" || on === "true") ? "1" : "0"
      root.relay("runCommand", [["--bt-when-powered-on", val]])
      return JSON.stringify({ success: true, btPowerOn: val === "1" })
    }

    function setBtCallVolume(volume: string): string {
      var vol = parseInt(volume)
      if (isNaN(vol)) return JSON.stringify({ error: "Invalid volume" })
      root.relay("runCommand", [["--bt-call-volume", String(vol)]])
      return JSON.stringify({ success: true, volume: vol })
    }

    function sendNotification(type: string): string {
      var t = type || "0"
      root.relay("runCommand", [["-n", t]])
      return JSON.stringify({ success: true, type: t })
    }
  }
}
