// SPDX-FileCopyrightText: 2026 hrzlgnm
// SPDX-License-Identifier: MIT

// Helpers for the HeadsetControl bar widget. Kept in JS so the pure
// parsing/formatting logic stays testable and out of QML bindings.

const chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
const defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰁂", "󰁂", "󰁹"]

// Shown when the device is one whose preset bank has published names.
// HeadsetControl's JSON reports only a count, but its own driver documents what
// each slot holds, so numbering them hides information the user already has:
// "Footsteps" says considerably more than "5".
//
// Keyed on the `device` string HeadsetControl reports. Both Audeze drivers
// carry the same list (audeze_maxwell.hpp and audeze_maxwell2.hpp: "1 = Audeze,
// 2 = Treble Boost, 3 = Bass Boost, 4 = Immersive, 5 = Competition,
// 6 = Footsteps, 7 = EQ1, 8 = EQ2, 9 = EQ3, 10 = EQ4"), shifted here to the
// 0-based indices the -p flag takes.
const eqPresetNames = {
  "Audeze Maxwell": ["Audeze", "Treble Boost", "Bass Boost", "Immersive",
                     "Competition", "Footsteps", "EQ1", "EQ2", "EQ3", "EQ4"],
  "Audeze Maxwell 2": ["Audeze", "Treble Boost", "Bass Boost", "Immersive",
                       "Competition", "Footsteps", "EQ1", "EQ2", "EQ3", "EQ4"]
}

// Fallback when the count is missing, matching what the panel showed before it
// used the reported value.
const defaultEqPresetCount = 4

function disconnectedState() {
  return { detected: false, connected: false, deviceName: "", batteryLevel: -1, batteryStatus: "BATTERY_UNAVAILABLE", chatmixLevel: -1, capabilities: {}, eqPresetCount: 0 }
}

function clampIndex(index) {
  return Math.max(0, Math.min(9, index))
}

// Parse `headsetcontrol -o json` output into a plain state object.
// Returns null on unparseable output, otherwise a state object:
//   detected        bool (headsetcontrol found the device at all)
//   connected       bool (battery is reporting, so the headset is live)
//   deviceName      string
//   batteryLevel    int (-1 when unavailable)
//   batteryStatus   string (BATTERY_*)
//   chatmixLevel    int (-1 when unavailable)
//   capabilities    map of CAP_* -> true
function parseState(data) {
  var json
  try {
    json = JSON.parse(data)
  } catch (e) {
    return null
  }
  if (!json || !Array.isArray(json.devices) || json.devices.length === 0) {
    return disconnectedState()
  }
  var dev = json.devices[0] || {}
  if (dev.status !== "success") return disconnectedState()

  var caps = {}
  if (Array.isArray(dev.capabilities)) {
    for (var i = 0; i < dev.capabilities.length; i++) {
      if (typeof dev.capabilities[i] === "string") caps[dev.capabilities[i]] = true
    }
  }

  var battery = dev.battery || {}
  var level = typeof battery.level === "number" && battery.level >= 0 ? battery.level : -1
  var status = typeof battery.status === "string" ? battery.status : "BATTERY_UNAVAILABLE"
  var chatmix = typeof dev.chatmix === "number" ? dev.chatmix : -1
  var presets = typeof dev.equalizer_presets_count === "number"
    && dev.equalizer_presets_count > 0
      ? dev.equalizer_presets_count : defaultEqPresetCount

  return {
    detected: true,
    connected: isConnected(caps, status),
    deviceName: dev.device || "",
    batteryLevel: level,
    batteryStatus: status,
    chatmixLevel: chatmix,
    eqPresetCount: presets,
    capabilities: caps
  }
}

// Labels for the preset buttons: real names where the device has them,
// otherwise the index, which is what `-p` takes either way.
function eqPresetLabels(deviceName, count) {
  var n = typeof count === "number" && count > 0 ? count : defaultEqPresetCount
  var names = eqPresetNames[deviceName]
  var out = []
  for (var i = 0; i < n; i++) {
    out.push(names && names[i] ? names[i] : String(i))
  }
  return out
}

// Long names need fewer, wider buttons; bare indices still fit four across.
function eqPresetColumns(deviceName) {
  return eqPresetNames[deviceName] ? 2 : 4
}

// A supported device's dongle/base station is always reported as "success"
// even when the headset itself is off. The only reliable live signal is the
// battery: mirror `headsetcontrol --connected`, which only counts a battery
// that is actually reporting as connected. Headsets without a battery chip
// count as connected whenever they are detected at all.
//
// A battery that is not reporting does not by itself mean the headset is off.
// A dongle can also end up in a state where it enumerates, plays audio and
// still applies setting writes, while answering every status query with an
// empty frame until it is physically replugged. Observed on an Audeze Maxwell 2
// (3329:4b29): audio streaming at 48kHz/24-bit, sidetone changes audible, and
// `BATTERY_UNAVAILABLE` throughout. See Sapd/HeadsetControl#573.
//
// The two are indistinguishable from this output, which is why `detected` is
// reported separately: the panel can say the device was found without claiming
// to know whether the headset is off or the dongle needs a replug.
function isConnected(caps, batteryStatus) {
  if (!hasCapability(caps, "CAP_BATTERY_STATUS")) return true
  return batteryStatus === "BATTERY_AVAILABLE" || batteryStatus === "BATTERY_CHARGING"
}

function hasCapability(caps, name) {
  return !!(caps && caps[name])
}

function batteryIcon(level, status) {
  if (typeof level !== "number" || level < 0) return ""
  var charging = status === "BATTERY_CHARGING"
  var index = clampIndex(Math.floor(level / 10))
  return charging ? chargingIcons[index] : defaultIcons[index]
}

function batteryLabel(level, status) {
  if (typeof level !== "number" || level < 0) return "Battery unavailable"
  var state = batteryStatusLabel(status)
  return level + "%" + (state ? " \u00b7 " + state : "")
}

function batteryStatusLabel(status) {
  switch (status) {
    case "BATTERY_CHARGING": return "charging"
    case "BATTERY_DISCHARGING": return "discharging"
    default: return ""
  }
}

function chatmixLabel(level) {
  if (typeof level !== "number" || level < 0) return "N/A"
  return (level > 64 ? "Chat" : "Game") + " (" + level + ")"
}

if (typeof module !== "undefined") {
  module.exports = {
    clampIndex: clampIndex,
    parseState: parseState,
    disconnectedState: disconnectedState,
    isConnected: isConnected,
    hasCapability: hasCapability,
    batteryIcon: batteryIcon,
    batteryLabel: batteryLabel,
    batteryStatusLabel: batteryStatusLabel,
    chatmixLabel: chatmixLabel,
    eqPresetLabels: eqPresetLabels,
    eqPresetColumns: eqPresetColumns
  }
}
