--!nonstrict
-- DeepSeek Peak Hours - Noctalia v5 checker service.
-- Runs while the plugin is enabled (not only while the panel is open), fetches
-- the provider's pricing page at the configured interval, and publishes drift
-- state for the bar and panel. Offline-first: publishing "no drift" is the
-- default. Schedule/profile data comes from lib/schedule.luau.

local schedule = require("./lib/schedule.luau")

local lastChecked = "never"
local drift = false
local timerElapsedH = 0

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

local function extractWindows(text)
  local found = {}
  for a, b in string.gmatch(text, "(%d%d:%d%d)%s*%-%s*(%d%d:%d%d)") do
    table.insert(found, a .. "-" .. b)
  end
  table.sort(found)
  local unique = {}
  for _, window in ipairs(found) do
    if unique[#unique] ~= window then
      table.insert(unique, window)
    end
  end
  return table.concat(unique, ", ")
end

local function expectedWindows()
  return table.concat(schedule.scheduleWindows(provider()), ", ")
end

local function publish(value)
  drift = value
  noctalia.state.set("deepseek-peak.drift", drift)
end

local function check(force)
  if not force and config("offlineOnly", false) then
    return
  end
  if not force and not config("autoCheck", true) then
    return
  end
  local url = config("customSourceUrl", "")
  if url == nil or url == "" then
    url = schedule.sourceUrl(provider())
  end
  noctalia.state.set("deepseek-peak.source", url)
  noctalia.http({ url = url, method = "GET" }, function(response)
    lastChecked = noctalia.formatTime("%H:%M")
    noctalia.state.set("deepseek-peak.checkedAt", lastChecked)
    if response.ok and response.body then
      local found = extractWindows(response.body)
      if found ~= "" and found ~= expectedWindows() then
        publish(true)
        noctalia.notify(noctalia.tr("notice.policyChanged"), found)
      else
        publish(false)
      end
    end
  end)
end

noctalia.state.watch("deepseek-peak.cmd", function(value)
  if value == "CHECK" then
    noctalia.state.set("deepseek-peak.cmd", nil)
    check(true)
  end
end)

function onIpc(event, _payload)
  if event == "check" then
    check(true)
  elseif event == "refresh" then
    check(false)
  end
end

noctalia.setUpdateInterval(60000)

function update()
  timerElapsedH = timerElapsedH + 1 / 60
  local interval = math.max(1, config("checkIntervalH", 6))
  if timerElapsedH >= interval then
    timerElapsedH = 0
    check(false)
  end
end

check(false)
