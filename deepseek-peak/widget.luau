local widget = {}

local settings = {
	displayMode = "compact",
	offPeakColor = "#4ade80",
	peakColor = "#f87171",
	driftColor = "#fbbf24",
	showTooltip = true,
	weekendMode = "beijing-anchored",
	drift = false,
}

local drift = false
local isPeakNow = false
local secondsToNext = 0

local function isPeakAt(now)
	local utc = os.date("!*t", now)
	local bj = os.date("!*t", now + 8 * 3600)
	if settings.weekendMode == "utc" then
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
	for t = coarse - 59, coarse, 1 do
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

function widget.update()
	local now = os.time()
	isPeakNow = isPeakAt(now)
	secondsToNext = secondsUntilNext(now)
	drift = settings.drift == true and true or drift
	local color = isPeakNow and settings.peakColor or settings.offPeakColor
	if drift then
		color = settings.driftColor
	end
	barWidget.setGlyph("zap")
	barWidget.setColor(color)
	if settings.displayMode == "icon" then
		barWidget.setText("")
	elseif settings.displayMode == "full" then
		barWidget.setText((isPeakNow and "PEAK 2x " or "OFF-PEAK ") .. formatCountdown(secondsToNext))
	else
		barWidget.setText(formatCountdown(secondsToNext))
	end
	if settings.showTooltip then
		local suffix = ""
		if drift then
			suffix = " — policy may have changed"
		end
		barWidget.setTooltip((isPeakNow and "PEAK (2x)" or "OFF-PEAK") .. " — next flip in " .. formatCountdown(secondsToNext) .. suffix)
	end
end

-- Shared drift flag: panel.luau checker calls setDrift(true/false) so the
-- bar tints amber. Offline-first: bar renders from bundled schedule regardless.
function widget.setDrift(value)
	drift = value == true
	settings.drift = drift
	widget.update()
end

function widget.isDrift()
	return drift
end

function widget.onClick()
	panel.open()
end

function widget.configure(newSettings)
	for k, v in pairs(newSettings) do
		settings[k] = v
	end
	widget.update()
end

noctalia.setUpdateInterval(1000)

return widget
