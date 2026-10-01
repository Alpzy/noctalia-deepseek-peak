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

return M
