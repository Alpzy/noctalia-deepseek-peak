import json
import pathlib
import shutil
import subprocess

import pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
MODULE = ROOT / "deepseek-peak" / "lib" / "settings.luau"
LUAU_FILES = [
    "deepseek-peak/widget.luau",
    "deepseek-peak/panel.luau",
    "deepseek-peak/checker.luau",
    "deepseek-peak/lib/schedule.luau",
    "deepseek-peak/lib/settings.luau",
]


def _lua():
    return shutil.which("lua5.4") or shutil.which("lua") or shutil.which("luajit")


def test_settings_module_parses():
    lua = _lua()
    if lua is None:
        pytest.skip("no lua interpreter available")
    assert MODULE.exists(), "deepseek-peak/lib/settings.luau missing"
    result = subprocess.run(
        [lua, "-e", f"assert(loadfile('{MODULE}'))"],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stderr


HARNESS = """
assert(arg[1], "module path")
local files = {}
local state = {}
local listeners = {}
local DATA_DIR = "ram://data"

noctalia = {
  pluginDataDir = function() return DATA_DIR end,
  readFile = function(path) return files[path] end,
  writeFile = function(path, content) files[path] = content return true end,
  json = {
    decode = function(s)
      local out = {}
      for pair in string.gmatch(s, "([^;]+)") do
        local k, v = string.match(pair, "^([^=]+)=(.*)$")
        if k then out[k] = v end
      end
      return out
    end,
    encode = function(t)
      local parts = {}
      for k, v in pairs(t) do
        table.insert(parts, k .. "=" .. tostring(v))
      end
      table.sort(parts)
      return table.concat(parts, ";")
    end,
  },
  getConfig = function(key)
    if key == "provider" then return "deepseek" end
    if key == "peakColor" then return "#f87171" end
    return nil
  end,
  state = {
    set = function(key, value)
      state[key] = value
      for _, fn in ipairs(listeners[key] or {}) do fn(value) end
    end,
    watch = function(key, fn)
      listeners[key] = listeners[key] or {}
      table.insert(listeners[key], fn)
    end,
  },
  nowMs = function() return 123 end,
}

local settings = dofile(arg[1])
local function check(name, got, want)
  if got ~= want then
    error(name .. ": got " .. tostring(got) .. " want " .. tostring(want))
  end
  print("ok " .. name)
end

check("declared fallback", settings.get("provider", "x"), "deepseek")
check("unknown falls back", settings.get("nope", 7), 7)
check("provider helper", settings.provider(), "deepseek")
settings.setOverride("provider", "ollama")
check("override wins", settings.get("provider", "x"), "ollama")
check("provider helper after", settings.provider(), "ollama")
check("file written", files[DATA_DIR .. "/overrides.json"], "provider=ollama")
local got = nil
settings.watch(function() got = settings.provider() end)
-- simulate the watcher firing (state.set triggers listeners synchronously)
noctalia.state.set("deepseek-peak.settings", 999)
check("watch refreshes cache", got, "ollama")
check("toggle", settings.toggleProvider(), "deepseek")
check("toggle persisted", settings.get("provider", "x"), "deepseek")
print("ALL PASS")
"""


def test_settings_overlay_semantics(tmp_path):
    lua = _lua()
    if lua is None:
        pytest.skip("no lua interpreter available")
    harness = tmp_path / "harness.luau"
    harness.write_text(HARNESS)
    result = subprocess.run(
        [lua, str(harness), str(MODULE)],
        capture_output=True, text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "ALL PASS" in result.stdout
