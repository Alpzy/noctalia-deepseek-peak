import json
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCHEDULE = ROOT / "deepseek-peak" / "schedule.json"
MODULE = ROOT / "deepseek-peak" / "lib" / "schedule.luau"


def _lua():
    return shutil.which("lua5.4") or shutil.which("lua") or shutil.which("luajit")


def to_lua(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value)
    if isinstance(value, list):
        return "{" + ",".join(to_lua(v) for v in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{json.dumps(k)}]={to_lua(v)}" for k, v in value.items()) + "}"
    raise TypeError(type(value))


HARNESS = """
assert(arg[1], "module path")
assert(arg[2], "data path")
local data = dofile(arg[2])
noctalia = { readFile = function() return "stub" end,
             json = { decode = function() return data end } }
local schedule = dofile(arg[1])

local function at(y, mo, d, h, mi, s)
  return os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s or 0 })
end
local function check(name, got, want)
  if got ~= want then
    error(name .. ": got " .. tostring(got) .. " want " .. tostring(want))
  end
  print("ok " .. name)
end

-- 2026-10-01 is a bundled Chinese holiday AND a Thursday; 03:00 UTC is inside
-- the DeepSeek peak window, so only the holiday rule can make it off-peak.
check("deepseek holiday off-peak", schedule.isPeakAt(at(2026,10,1,3,0), "deepseek"), false)
-- 13:00 UTC is peak for Ollama, off-peak for DeepSeek.
check("ollama peak window", schedule.isPeakAt(at(2026,10,1,13,0), "ollama"), true)
check("deepseek outside windows", schedule.isPeakAt(at(2026,10,1,13,0), "deepseek"), false)
-- Holidays never apply to Ollama: 2026-10-02 at 13:00 UTC is still peak.
check("ollama ignores holidays", schedule.isPeakAt(at(2026,10,2,13,0), "ollama"), true)
-- Saturday 2026-10-03 02:00 UTC is off-peak for both (Beijing and UTC weekends).
check("weekend off-peak deepseek", schedule.isPeakAt(at(2026,10,3,2,0), "deepseek"), false)
check("weekend off-peak ollama", schedule.isPeakAt(at(2026,10,3,2,0), "ollama"), false)
-- Countdown: Wed 2026-09-30 00:59:30 UTC flips to peak at 01:00:00.
check("countdown to 01:00", schedule.secondsUntilNext(at(2026,9,30,0,59,30), "deepseek"), 30)
check("schedule text", schedule.scheduleText("ollama"), "12:00-18:00 UTC")

local deepseekPage = "Peak hours are 01:00 - 04:00 and 06:00 - 10:00 UTC, Monday through Friday."
local ollamaPage = "Off-peak pricing apply outside 12:00 and 18:00 UTC on weekdays."
local ds = schedule.windowsFromPage(deepseekPage)
check("deepseek page windows", table.concat(ds, ", "), "01:00-04:00, 06:00-10:00")
local ol = schedule.windowsFromPage(ollamaPage)
check("ollama page window", ol[1], "12:00-18:00")
check("unknown page nil", schedule.windowsFromPage("no schedule here"), nil)
check("sameWindows order free", schedule.sameWindows({"06:00-10:00","01:00-04:00"}, {"01:00-04:00","06:00-10:00"}), true)
check("sameWindows mismatch", schedule.sameWindows({"01:00-04:00"}, {"12:00-18:00"}), false)
print("ALL PASS")
"""


def test_schedule_module_matches_v4_semantics(tmp_path):
    lua = _lua()
    if lua is None:
        pytest.skip("no lua interpreter available")
    assert MODULE.exists(), "deepseek-peak/lib/schedule.luau missing"
    data = json.loads(SCHEDULE.read_text())
    data_lua = tmp_path / "schedule_data.luau"
    data_lua.write_text("return " + to_lua(data) + "\n")
    harness = tmp_path / "harness.luau"
    harness.write_text(HARNESS)
    env = {"PATH": "/usr/bin:/bin", "TZ": "UTC"}
    result = subprocess.run(
        [lua, str(harness), str(MODULE), str(data_lua)],
        capture_output=True, text=True, env=env,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "ALL PASS" in result.stdout
