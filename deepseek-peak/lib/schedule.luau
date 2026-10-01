--!nonstrict
-- Shared schedule logic for the DeepSeek Peak Hours v5 port.
-- Single source of truth: schedule.json (provider profiles + bundled Chinese
-- holidays), read at runtime from the plugin directory. Mirrors the v4
-- semantics of deepseek-peak/peak.js.

local M = {}

local FALLBACK = {
  providers = {
    deepseek = {
      name = "DeepSeek",
      peakWindowsUtc = { { "01:00", "04:00" }, { "06:00", "10:00" } },
      weekendMode = "beijing-anchored",
      holidayOffPeak = true,
      sourceUrl = "https://api-docs.deepseek.com/quick_start/pricing/",
      fallbackUrls = {
        "https://api-docs.deepseek.com/quick_start/pricing/",
        "https://www.deepseek.com/en/pricing",
      },
    },
    ollama = {
      name = "Ollama",
      peakWindowsUtc = { { "12:00", "18:00" } },
      weekendMode = "utc",
      holidayOffPeak = false,
      sourceUrl = "https://ollama.com/pricing",
      fallbackUrls = { "https://ollama.com/pricing", "https://docs.ollama.com/cloud" },
    },
  },
  holidays = {},
}

local data = nil

local function load()
  if data ~= nil then
    return data
  end
  local raw = noctalia.readFile("schedule.json")
  if raw then
    local parsed = noctalia.json.decode(raw)
    if type(parsed) == "table" and type(parsed.providers) == "table" then
      data = parsed
      return data
    end
  end
  data = FALLBACK
  return data
end

local function profile(provider)
  local profiles = load().providers
  return profiles[provider] or profiles.deepseek
end

function M.providerName(provider)
  return profile(provider).name
end

function M.sourceUrl(provider)
  return profile(provider).sourceUrl
end

function M.fallbackUrls(provider)
  return profile(provider).fallbackUrls or {}
end

local function toMinutes(hhmm)
  local h, m = string.match(hhmm, "^(%d%d):(%d%d)$")
  return tonumber(h) * 60 + tonumber(m)
end

function M.scheduleWindows(provider)
  local out = {}
  for _, w in ipairs(profile(provider).peakWindowsUtc) do
    table.insert(out, w[1] .. "-" .. w[2])
  end
  return out
end

function M.scheduleText(provider)
  return table.concat(M.scheduleWindows(provider), ", ") .. " UTC"
end

local function isHoliday(now, provider)
  local p = profile(provider)
  if not p.holidayOffPeak then
    return false
  end
  local bj = os.date("!*t", now + 8 * 3600)
  local year = string.format("%04d", bj.year)
  local key = year .. "-" .. string.format("%02d", bj.month) .. "-" .. string.format("%02d", bj.day)
  local days = load().holidays[year]
  if days == nil then
    return false
  end
  for _, d in ipairs(days) do
    if d == key then
      return true
    end
  end
  return false
end

local function isWeekendOffDay(now, weekendMode)
  local day
  if weekendMode == "utc" then
    day = os.date("!*t", now).wday
  else
    day = os.date("!*t", now + 8 * 3600).wday
  end
  return day == 1 or day == 7
end

function M.isPeakAt(now, provider)
  local p = profile(provider)
  if isWeekendOffDay(now, p.weekendMode) then
    return false
  end
  if isHoliday(now, provider) then
    return false
  end
  local utc = os.date("!*t", now)
  local minutes = utc.hour * 60 + utc.min
  for _, w in ipairs(p.peakWindowsUtc) do
    if minutes >= toMinutes(w[1]) and minutes < toMinutes(w[2]) then
      return true
    end
  end
  return false
end

function M.secondsUntilNext(now, provider)
  local peak = M.isPeakAt(now, provider)
  local coarse = 0
  for s = 60, 7 * 86400, 60 do
    if M.isPeakAt(now + s, provider) ~= peak then
      coarse = s
      break
    end
  end
  if coarse == 0 then
    return 0
  end
  for t = coarse - 59, coarse do
    if M.isPeakAt(now + t, provider) ~= peak then
      return t
    end
  end
  return coarse
end

function M.formatCountdown(s)
  local h = math.floor(s / 3600)
  local m = math.floor((s % 3600) / 60)
  if h > 0 then
    return h .. "h" .. m .. "m"
  end
  return m .. "m"
end

function M.formatHMS(s)
  s = math.max(0, math.floor(s))
  return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
end

-- Extract canonical "HH:MM-HH:MM" windows from a pricing page.
-- Mirrors v4 peak.js/Main.qml windowsFromPage: DeepSeek states
-- "Peak hours are 01:00 - 04:00 ..." and Ollama states "Off-peak pricing
-- apply outside 12:00 and 18:00 UTC on weekdays". Returns nil when no known
-- phrasing is found (callers must not infer drift from a nil result).
function M.windowsFromPage(text)
  if type(text) ~= "string" then
    return nil
  end
  local peak = string.match(text, "Peak hours are ([^<]+)")
  if peak then
    local found = {}
    for a, b in string.gmatch(peak, "(%d%d:%d%d)%s*%-%s*(%d%d:%d%d)") do
      table.insert(found, a .. "-" .. b)
    end
    if #found > 0 then
      table.sort(found)
      return found
    end
  end
  local a, b = string.match(text, "[Oo]utside%s+(%d%d:%d%d)%s+and%s+(%d%d:%d%d)%s+UTC")
  if a and b then
    return { a .. "-" .. b }
  end
  return nil
end

-- Order-independent window-set comparison. Both sides are canonical
-- "HH:MM-HH:MM" strings; duplicates are ignored.
function M.sameWindows(left, right)
  local function key(list)
    local copy = {}
    for _, item in ipairs(list or {}) do
      table.insert(copy, item)
    end
    table.sort(copy)
    return table.concat(copy, ",")
  end
  return key(left) == key(right)
end

local function toMinutes(hhmm)
  local h, m = string.match(hhmm, "^(%d%d):(%d%d)$")
  return tonumber(h) * 60 + tonumber(m)
end

-- Bounds of the current peak/off-peak block. Coarse 15-minute scan backwards
-- (max 10 days) refined to the second; peaks are hours long, so a 15-minute
-- probe never skips a transition. Mirrors v4 peak.js blockBounds.
function M.blockBounds(now, provider)
  local peak = M.isPeakAt(now, provider)
  local maxBack = 10 * 86400
  local step = 900
  local back = 0
  for s = step, maxBack, step do
    if M.isPeakAt(now - s, provider) ~= peak then
      back = s
      break
    end
  end
  local startMs = now - back
  if back > 0 then
    for t = back - (step - 1), back do
      if M.isPeakAt(now - t, provider) ~= peak then
        startMs = now - (t - 1)
        break
      end
    end
  end
  local forward = M.secondsUntilNext(now, provider)
  local endMs = forward > 0 and (now + forward) or (now + maxBack)
  return { provider = provider, isPeak = peak, startMs = startMs, endMs = endMs }
end

-- Fraction (0..1) of the current block elapsed, plus the block itself.
function M.progress(now, provider)
  local block = M.blockBounds(now, provider)
  local total = block.endMs - block.startMs
  local ratio = 0
  if total > 0 then
    ratio = math.min(1, math.max(0, (now - block.startMs) / total))
  end
  return ratio, block
end

local function pad2(n)
  return string.format("%02d", n)
end

-- Canonical windows in a display zone: "utc" | "beijing" | "local". Mirrors
-- v4 fmtHM/windowLine. Returns nil on weekend days (host shows "all day").
function M.windowLine(now, provider, tz)
  local p = profile(provider)
  local weekend
  if p.weekendMode == "utc" then
    local w = os.date("!*t", now).wday
    weekend = w == 1 or w == 7
  else
    local w = os.date("!*t", now + 8 * 3600).wday
    weekend = w == 1 or w == 7
  end
  if weekend then
    return nil
  end
  local function hm(minutes)
    local h = math.floor(minutes / 60) % 24
    local m = minutes % 60
    if tz == "utc" then
      return pad2(h) .. ":" .. pad2(m)
    end
    if tz == "beijing" then
      h = (h + 8) % 24
      return pad2(h) .. ":" .. pad2(m)
    end
    -- local: convert from the UTC wall time using the process timezone
    local utc = os.date("!*t", now)
    local localTs = os.time({ year = utc.year, month = utc.month, day = utc.day,
                              hour = h, min = m, sec = 0, isdst = false })
    local lt = os.date("*t", localTs)
    return pad2(lt.hour) .. ":" .. pad2(lt.min)
  end
  local parts = {}
  for _, w in ipairs(p.peakWindowsUtc) do
    table.insert(parts, hm(toMinutes(w[1])) .. "-" .. hm(toMinutes(w[2])))
  end
  return table.concat(parts, " · ")
end

-- Semantic relative "last checked" info. Keys live under "checked" in i18n.
function M.checkedInfo(nowMs, checkedMs)
  if checkedMs == nil or checkedMs <= 0 then
    return { key = "", n = 0, text = "" }
  end
  local diff = math.max(0, math.floor((nowMs - checkedMs) / 1000))
  if diff < 60 then
    return { key = "checked.justNow", n = 0, text = "" }
  end
  if diff < 3600 then
    return { key = "checked.minutesAgo", n = math.floor(diff / 60), text = "" }
  end
  if diff < 86400 then
    return { key = "checked.hoursAgo", n = math.floor(diff / 3600), text = "" }
  end
  return { key = "checked.date", n = 0, text = os.date("%m-%d %H:%M", checkedMs) }
end

local function dateKeyToMs(key)
  local y, mo, d = string.match(key, "^(%d%d%d%d)-(%d%d)-(%d%d)$")
  return os.time({ year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                   hour = 12, min = 0, sec = 0, isdst = false })
end

local function isNextDay(a, b)
  return math.floor((dateKeyToMs(b) - dateKeyToMs(a)) / 86400 + 0.5) == 1
end

-- Current or next bundled holiday range when active or starting within a
-- week. nil for providers without holidayOffPeak or outside that window.
function M.holidayRangeInfo(now, provider)
  local p = profile(provider)
  if not p.holidayOffPeak then
    return nil
  end
  local byYear = load().holidays or {}
  local all = {}
  for _, days in pairs(byYear) do
    for _, d in ipairs(days) do
      table.insert(all, d)
    end
  end
  if #all == 0 then
    return nil
  end
  table.sort(all)
  local bj = os.date("!*t", now + 8 * 3600)
  local todayKey = string.format("%04d-%02d-%02d", bj.year, bj.month, bj.day)
  local todayMs = os.time({ year = bj.year, month = bj.month, day = bj.day,
                            hour = 0, min = 0, sec = 0, isdst = false })
  local idx = 1
  while idx <= #all and all[idx] < todayKey do
    idx = idx + 1
  end
  if idx > #all then
    return nil
  end
  local startIdx, endIdx = idx, idx
  if all[idx] == todayKey then
    while startIdx - 1 >= 1 and isNextDay(all[startIdx - 1], all[startIdx]) do
      startIdx = startIdx - 1
    end
    while endIdx + 1 <= #all and isNextDay(all[endIdx], all[endIdx + 1]) do
      endIdx = endIdx + 1
    end
    return { active = true, startMs = dateKeyToMs(all[startIdx]),
             endMs = dateKeyToMs(all[endIdx]), inDays = 0 }
  end
  while endIdx + 1 <= #all and isNextDay(all[endIdx], all[endIdx + 1]) do
    endIdx = endIdx + 1
  end
  local inDays = math.floor((dateKeyToMs(all[startIdx]) - todayMs) / 86400 + 0.5)
  if inDays > 7 then
    return nil
  end
  return { active = false, startMs = dateKeyToMs(all[startIdx]),
           endMs = dateKeyToMs(all[endIdx]), inDays = inDays }
end

-- The countdown label semantics: while peak, count down to off-peak and
-- vice versa. Mirrors v4 (isPeak ? offPeakIn : peakIn).
function M.countdownLabelKey(isPeak)
  if isPeak then
    return "panel.offPeakIn"
  end
  return "panel.peakIn"
end

return M
