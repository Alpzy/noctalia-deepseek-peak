--!nonstrict
-- DeepSeek Peak Hours - Noctalia v5 checker service.
-- Runs while the plugin is enabled (not only while the panel is open), fetches
-- the provider's pricing page at the configured interval, and publishes drift
-- state for the bar and panel. Offline-first: publishing "no drift" is the
-- default. Schedule/profile/extraction logic lives in lib/schedule.luau.

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

local function publish(value)
  drift = value
  noctalia.state.set("deepseek-peak.drift", drift)
end

local function applyPage(text)
  local found = schedule.windowsFromPage(text)
  if found == nil then
    return
  end
  if not schedule.sameWindows(found, schedule.scheduleWindows(provider())) then
    publish(true)
    noctalia.notify(noctalia.tr("notice.policyChanged"),
      schedule.providerName(provider()) .. " · " .. table.concat(found, ", ") .. " UTC")
  else
    publish(false)
  end
end

local function tryUrls(urls, index)
  if index > #urls then
    return
  end
  noctalia.http({ url = urls[index], method = "GET" }, function(response)
    if response.ok and response.body then
      lastChecked = noctalia.formatTime("%H:%M")
      noctalia.state.set("deepseek-peak.checkedAt", lastChecked)
      applyPage(response.body)
    else
      tryUrls(urls, index + 1)
    end
  end)
end

local function check(force)
  if not force and config("offlineOnly", false) then
    return
  end
  if not force and not config("autoCheck", true) then
    return
  end
  local which = provider()
  local sourceUrl = config("customSourceUrl", "")
  if sourceUrl == nil or sourceUrl == "" then
    sourceUrl = schedule.sourceUrl(which)
  end
  noctalia.state.set("deepseek-peak.source", sourceUrl)
  local urls = { sourceUrl }
  if sourceUrl == schedule.sourceUrl(which) then
    for _, url in ipairs(schedule.fallbackUrls(which)) do
      table.insert(urls, url)
    end
  end
  tryUrls(urls, 1)
end

noctalia.state.watch("deepseek-peak.cmd", function(value)
  if value == "CHECK" then
    noctalia.state.set("deepseek-peak.cmd", "done")
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
