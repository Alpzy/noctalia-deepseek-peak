--!nonstrict
-- DeepSeek Peak Hours - Noctalia v5 bar widget entry.
-- API: global update()/onClick()/onConfigChanged(); noctalia.*; barWidget.*
-- Settings are read with noctalia.getConfig (declared in plugin.toml).

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

local function isPeakAt(now)
  local utc = os.date("!*t", now)
  local bj = os.date("!*t", now + 8 * 3600)
  if config("weekendMode", "beijing-anchored") == "utc" then
    if utc.wday == 1 or utc.wday == 7 then
      return false
    end
  else
    if bj.wday == 1 or bj.wday == 7 then
      return false
    end
    if utc.wday == 7 then
      return false
    end
    if utc.wday == 6 and utc.hour >= 16 then
      return false
    end
    if utc.wday == 1 and utc.hour < 16 then
      return false
    end
  end
  local h = utc.hour + utc.min / 60
  return (h >= 1 and h < 4) or (h >= 6 and h < 10)
end

local function secondsUntilNext(now)
  local peak = isPeakAt(now)
  local coarse = 0
  for s = 60, 7 * 86400, 60 do
    if isPeakAt(now + s) ~= peak then
      coarse = s
      break
    end
  end
  if coarse == 0 then
    return 0
  end
  for t = coarse - 59, coarse do
    if isPeakAt(now + t) ~= peak then
      return t
    end
  end
  return coarse
end

local function formatCountdown(s)
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  if h > 0 then
    return h .. "h" .. m .. "m"
  end
  return m .. "m"
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
  local countdown = formatCountdown(secondsToNext)
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
  barWidget.render(ui.row({ gap = 6, align = "center" }, {
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
      .. formatCountdown(secondsToNext) .. suffix)
  else
    barWidget.clearTooltip()
  end
end

function update()
  local now = os.time()
  isPeakNow = isPeakAt(now)
  secondsToNext = secondsUntilNext(now)
  render()
end

function onConfigChanged()
  render()
end

function onClick()
  noctalia.togglePanel("alpzy/deepseek-peak:panel")
end

noctalia.state.watch("deepseek-peak.drift", function(value)
  drift = value == true
  render()
end)

noctalia.setUpdateInterval(1000)
update()
