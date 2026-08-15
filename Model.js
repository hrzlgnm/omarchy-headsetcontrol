// Helpers for the HeadsetControl bar widget. Kept in JS so the pure
// parsing/formatting logic stays testable and out of QML bindings.

const chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"]
const defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰁂", "󰁂", "󰁹"]

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
    return { connected: false }
  }
  var dev = json.devices[0] || {}
  if (dev.status !== "success") return { connected: false }

  var caps = {}
  if (Array.isArray(dev.capabilities)) {
    for (var i = 0; i < dev.capabilities.length; i++) {
      if (typeof dev.capabilities[i] === "string") caps[dev.capabilities[i]] = true
    }
  }

  var battery = dev.battery || {}
  var level = typeof battery.level === "number" && battery.level >= 0 ? battery.level : -1
  var chatmix = typeof dev.chatmix === "number" ? dev.chatmix : -1

  return {
    connected: true,
    deviceName: dev.device || "",
    batteryLevel: level,
    batteryStatus: typeof battery.status === "string" ? battery.status : "BATTERY_UNAVAILABLE",
    chatmixLevel: chatmix,
    capabilities: caps
  }
}

function hasCapability(caps, name) {
  return !!(caps && caps[name])
}

function batteryIcon(level, status) {
  if (typeof level !== "number" || level < 0) return ""
  if (status === "BATTERY_FULL" || level >= 100) return "󰂅"
  var index = clampIndex(Math.floor(level / 10))
  return status === "BATTERY_CHARGING" ? chargingIcons[index] : defaultIcons[index]
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
    case "BATTERY_FULL": return "full"
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
    hasCapability: hasCapability,
    batteryIcon: batteryIcon,
    batteryLabel: batteryLabel,
    batteryStatusLabel: batteryStatusLabel,
    chatmixLabel: chatmixLabel
  }
}
