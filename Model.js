// SPDX-FileCopyrightText: 2026 hrzlgnm
// SPDX-License-Identifier: MIT

// Helpers for the HeadsetControl bar widget. Kept in JS so the pure
// parsing/formatting logic stays testable and out of QML bindings.

const chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
const defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰁂", "󰁂", "󰁹"]

function disconnectedState() {
  return { connected: false, deviceName: "", batteryLevel: -1, batteryStatus: "BATTERY_UNAVAILABLE", chatmixLevel: -1, capabilities: {} }
}

function clampIndex(index) {
  return Math.max(0, Math.min(9, index))
}

// Parse `headsetcontrol -o json` output into a plain state object.
// Returns null on unparseable output, otherwise a state object:
//   connected       bool
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

  return {
    connected: isConnected(caps, status),
    deviceName: dev.device || "",
    batteryLevel: level,
    batteryStatus: status,
    chatmixLevel: chatmix,
    capabilities: caps
  }
}

// A supported device's dongle/base station is always reported as "success"
// even when the headset itself is off. The only reliable live signal is the
// battery: mirror `headsetcontrol --connected`, which only counts a battery
// that is actually reporting as connected. Headsets without a battery chip
// count as connected whenever they are detected at all.
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
    chatmixLabel: chatmixLabel
  }
}
