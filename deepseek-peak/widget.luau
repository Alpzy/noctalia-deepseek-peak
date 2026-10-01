--!nonstrict
-- DeepSeek Peak Hours - Noctalia v5 bar widget entry.
-- API: global update()/onClick(); noctalia.*; barWidget.*; ui.*
-- Schedule logic lives in lib/schedule.luau (mirrors v4 peak.js semantics).

local schedule = require("./lib/schedule.luau")

local isPeakNow = false
local secondsToNext = 0
local drift = false

local function config(key, fallback)
  local value = noctalia.getConfig(key)
  if value == nil then
    return fallback
  end
  return value
end

local function provider()
  if config("provider", "deepseek") == "ollama" then
    return "ollama"
  end
  return "deepseek"
end

local function color()
  if drift then
    return config("driftColor", "#fbbf24")
  end
  if isPeakNow then
    return config("peakColor", "#f87171")
  end
  return config("offPeakColor", "#4ade80")
end

local function label()
  local mode = config("displayMode", "compact")
  local countdown = schedule.formatCountdown(secondsToNext)
  if mode == "icon" then
    return ""
  elseif mode == "full" then
    return (isPeakNow and noctalia.tr("bar.peak") .. " " or noctalia.tr("bar.offPeak") .. " ")
      .. countdown
  end
  return countdown
end

local function render()
  local mode = config("displayMode", "compact")
  local container = barWidget.isVertical() and ui.column or ui.row
  barWidget.render(container({ gap = 6, align = "center" }, {
    ui.glyph({ name = "circle-filled", size = 10, color = color() }),
    ui.label({
      text = label(),
      fontWeight = "bold",
      color = color(),
      visible = mode ~= "icon",
    }),
  }))
  if config("showTooltip", true) then
    local state = isPeakNow and noctalia.tr("bar.tooltipPeak") or noctalia.tr("bar.tooltipOffPeak")
    local suffix = drift and (" — " .. noctalia.tr("bar.driftSuffix")) or ""
    barWidget.setTooltip(state .. " — " .. noctalia.tr("bar.nextFlip") .. " "
      .. schedule.formatCountdown(secondsToNext) .. suffix)
  else
    barWidget.clearTooltip()
  end
end

function update()
  local now = os.time()
  isPeakNow = schedule.isPeakAt(now, provider())
  secondsToNext = schedule.secondsUntilNext(now, provider())
  render()
end

function onClick()
  noctalia.togglePanel("alpzy/deepseek-peak:panel")
end

drift = noctalia.state.get("deepseek-peak.drift") == true
noctalia.state.watch("deepseek-peak.drift", function(value)
  drift = value == true
  render()
end)

noctalia.setUpdateInterval(1000)
update()
