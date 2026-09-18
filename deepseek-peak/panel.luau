local panel = {}

panel.sourceUrl = "https://api-docs.deepseek.com/quick_start/pricing/"
panel.fallbackUrls = {
	"https://api-docs.deepseek.com/quick_start/pricing/",
	"https://www.deepseek.com/en/pricing",
}
panel.checkedAt = "2026-09-14T00:00:00Z"
panel.bundledPeak = "01:00-04:00, 06:00-10:00 UTC"
panel.checkTimeoutS = 10
panel.windows = { { "01:00", "04:00" }, { "06:00", "10:00" } }

local settings = {
	weekendMode = "beijing-anchored",
	customSourceUrl = "",
	offlineOnly = false,
	autoCheck = true,
	checkIntervalH = 6,
}

local drift = false

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

local function formatHMS(s)
	s = math.max(0, math.floor(s))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	local sec = s % 60
	return string.format("%02d:%02d:%02d", h, m, sec)
end

function panel.getState(now)
	now = now or os.time()
	local peak = isPeakAt(now)
	local secs = secondsUntilNext(now)
	return {
		isPeak = peak,
		state = peak and "PEAK 2x" or "OFF-PEAK",
		countdown = secs,
		countdownHMS = formatHMS(secs),
		windows = panel.windows,
		source = panel.getSourceUrl(),
		checkedAt = panel.checkedAt,
		drift = drift,
	}
end

function panel.getSourceUrl()
	if settings.customSourceUrl ~= nil and settings.customSourceUrl ~= "" then
		return settings.customSourceUrl
	end
	return panel.sourceUrl
end

function panel.isDrift()
	return drift
end

function panel.setDrift(value)
	drift = value == true
	return drift
end

function panel.configure(newSettings)
	for k, v in pairs(newSettings) do
		settings[k] = v
	end
	if newSettings.drift ~= nil then
		drift = newSettings.drift == true
	end
end

function panel.checkDrift()
	if settings.autoCheck == false or settings.offlineOnly == true then
		return false
	end
	return drift
end

return panel
