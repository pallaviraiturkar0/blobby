-- Minimal stand-in for the Hammerspoon `hs` API, plus a controllable clock.
-- Each call to new() loads a fresh copy of blobby/init.lua so module state never leaks between tests.
local Stub = {}

local realTime, realDate, realPrint = os.time, os.date, print

-- Undo the global patches made by new(); safe to call more than once
function Stub.reset() os.time, os.date, _G.print, _G.hs = realTime, realDate, realPrint, nil end

local function chain(obj)
  return setmetatable(obj or {}, { __index = function() return function(self) return self end end })
end

function Stub.new(opts)
  opts = opts or {}
  local env = { js = {}, prints = {}, settings = {}, timers = {}, menuItems = nil, inCall = false }
  env.now = opts.now or realTime({ year = 2026, month = 3, day = 4, hour = 10 })

  function env.at(y, m, d, h) return realTime({ year = y, month = m, day = d, hour = h or 10 }) end
  function env.said()
    local out = {}
    for _, code in ipairs(env.js) do
      local text = code:match('^say%("(.*)",%d+%)$')
      if text then out[#out + 1] = text end
    end
    return out
  end
  function env.lastSaid() local s = env.said(); return s[#s] end
  function env.tick(n) for _ = 1, n or 1 do env.brain() end end
  function env.advance(sec) env.now = env.now + sec end
  env.restore = Stub.reset

  os.time = function(t) if t then return realTime(t) end return env.now end
  os.date = function(fmt, t) return realDate(fmt, t or env.now) end
  _G.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    env.prints[#env.prints + 1] = table.concat(parts, "\t")
  end

  local frame = { x = 0, y = 0, w = 1440, h = 900 }
  local screenObj = { name = function() return "Built-in Retina Display" end, frame = function() return frame end }
  local webview = chain({
    evaluateJavaScript = function(self, code) env.js[#env.js + 1] = code; return self end,
    hswindow = function() return nil end,
    isVisible = function() return true end,
    frame = function(self, f) if f then return self end return frame end,
  })

  local function timer(fn, interval)
    local t = { fn = fn, interval = interval, stopped = false }
    function t.stop(self) self.stopped = true; return self end
    env.timers[#env.timers + 1] = t
    return t
  end

  _G.hs = {
    configdir = ".",
    settings = {
      get = function(k) return env.settings[k] end,
      set = function(k, v) env.settings[k] = v end,
    },
    screen = {
      allScreens = function() return { screenObj } end,
      mainScreen = function() return screenObj end,
      watcher = { new = function() return chain({}) end },
    },
    audiodevice = { allInputDevices = function() return { { inUse = function() return env.inCall end } } end },
    geometry = { rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end },
    webview = {
      new = function() return webview end,
      usercontent = { new = function() return chain({ setCallback = function(self) return self end }) end },
    },
    drawing = { windowLevels = { floating = 3 }, windowBehaviors = { canJoinAllSpaces = 1, stationary = 16 } },
    hotkey = { bind = function() return chain({}) end },
    timer = {
      doEvery = function(interval, fn) return timer(fn, interval) end,
      doAfter = function(_, fn) return timer(fn, nil) end,
    },
    sound = { getByName = function() return chain({}) end },
    notify = { new = function() return chain({}) end },
    mouse = { absolutePosition = function() return { x = 0, y = 0 } end },
    eventtap = { checkMouseButtons = function() return { left = false } end },
    menubar = {
      new = function()
        return chain({ setMenu = function(self, items) env.menuItems = items; return self end })
      end,
    },
  }

  env.M = dofile("blobby/init.lua")
  function env.start(cfg)
    env.M.start(cfg)
    for _, t in ipairs(env.timers) do if t.interval == 1 then env.brain = t.fn end end
  end
  function env.menuItem(prefix)
    env.M.showMenu()
    for _, item in ipairs(env.menuItems) do
      if item.title and item.title:sub(1, #prefix) == prefix then return item end
    end
    error("no menu item starting with " .. prefix)
  end
  return env
end

return Stub
