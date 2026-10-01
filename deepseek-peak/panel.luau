--!nonstrict
-- DeepSeek Peak Hours - Noctalia v5 panel entry.
-- Info-only panel: state, countdown, schedule, provider, drift status.
-- Schedule logic lives in lib/schedule.luau (v4 peak.js semantics).

local schedule = require("./lib/schedule.luau")

local drift = false
local checkedAt = "never"
local source = schedule.sourceUrl("deepseek")

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

local function row(label, value, color)
  return ui.row({ gap = 8, justify = "space_between" }, {
    ui.label({ text = label, color = "on_surface_variant", fontSize = 12 }),
    ui.label({ text = value, color = color or "on_surface", fontSize = 12,
               fontWeight = "bold" }),
  })
end

local function render()
  local now = os.time()
  local which = provider()
  local peak = schedule.isPeakAt(now, which)
  local state = peak and noctalia.tr("panel.peak") or noctalia.tr("panel.offPeak")
  local stateColor = peak and config("peakColor", "#f87171") or config("offPeakColor", "#4ade80")
  if drift then
    stateColor = config("driftColor", "#fbbf24")
  end

  panel.render(ui.column({ gap = 10, padding = 14 }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "circle-filled", size = 12, color = stateColor }),
      ui.label({ text = state, fontWeight = "bold", color = stateColor, flexGrow = 1 }),
    }),
    row(noctalia.tr("panel.provider"), schedule.providerName(which)),
    row(peak and noctalia.tr("panel.peakIn") or noctalia.tr("panel.offPeakIn"),
        schedule.formatHMS(schedule.secondsUntilNext(now, which))),
    ui.separator({}),
    row(noctalia.tr("panel.schedule"), schedule.scheduleText(which)),
    row(noctalia.tr("panel.checked"), checkedAt),
    drift and ui.label({ text = noctalia.tr("panel.drift"), color = "error", fontSize = 11 }) or ui.spacer({}),
    ui.button({
      text = noctalia.tr("menu.refresh"),
      glyph = "refresh",
      variant = "ghost",
      onClick = function()
        noctalia.state.set("deepseek-peak.cmd", "CHECK")
      end,
    }),
    ui.button({
      text = noctalia.tr("menu.settings"),
      glyph = "settings",
      variant = "ghost",
      onClick = function()
        noctalia.openSettings()
      end,
    }),
    ui.label({ text = source, color = "on_surface_variant", fontSize = 10, maxLines = 2 }),
  }))
end

function onOpen(_context)
  render()
end

function onClose()
end

function update()
  render()
end

drift = noctalia.state.get("deepseek-peak.drift") == true
checkedAt = noctalia.state.get("deepseek-peak.checkedAt") or "never"
source = noctalia.state.get("deepseek-peak.source") or schedule.sourceUrl(provider())

noctalia.state.watch("deepseek-peak.drift", function(value)
  drift = value == true
  render()
end)

noctalia.state.watch("deepseek-peak.checkedAt", function(value)
  checkedAt = value or "never"
  render()
end)

noctalia.state.watch("deepseek-peak.source", function(value)
  source = value or source
  render()
end)

panel.setWantsSecondTicks(true)
