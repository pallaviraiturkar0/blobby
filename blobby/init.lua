-- Blobby: a tiny productivity pet for macOS, powered by Hammerspoon.
-- https://github.com/pallaviraiturkar0/blobby
--
-- Click = start/stop a focus session. Wears headphones during calls (mic in use).
-- Nudges you to stretch and hydrate. Dresses up for holidays and your birthday.
local M = {}

local HERE = debug.getinfo(1, "S").source:match("^@(.*/)") or (hs.configdir .. "/blobby/")

local config = {
  focusMinutes   = 25,
  stretchMinutes = 60,
  waterMinutes   = 90,
  wander         = 300,   -- px Blobby roams either side of its home spot
  birthday       = nil,   -- "MM-DD", e.g. "07-14"
  specialDays    = {},    -- { { date = "YYYY-MM-DD", days = 1, costume = "launch", prop = "🚀", greeting = "Ship it!" } }
  hotkeyMods     = { "ctrl", "alt", "cmd" },
  hotkeyToggle   = "B",
}

local FOCUS_MIN, STRETCH_MIN, WATER_MIN
local W, H = 240, 190
local wv, moveTimer, brainTimer
local x, y, homeX, targetX, dir = nil, nil, nil, nil, nil
local dragTimer
local WANDER
local state = "idle"
local focusEnd, transientUntil = nil, 0
local lastStretch, lastWater, lastPet = os.time(), os.time(), 0
local tomatoes = 0
local awayUntil, awayLabel = nil, nil
local menu

-- Prefer an external monitor; fall back to the main screen
local function screen()
  for _, s in ipairs(hs.screen.allScreens()) do
    local n = s:name() or ""
    if not (n:find("Built%-in") or n:find("Color LCD")) then return s end
  end
  return hs.screen.mainScreen()
end

local function js(code) if wv then wv:evaluateJavaScript(code) end end
local function say(text, ms) js(string.format("say(%q,%d)", text, ms or 5000)) end
local function setState(s) state = s; js(string.format("setState(%q,%q)", s, dir or "")) end

local function today() return os.date("%Y-%m-%d") end
local function loadTomatoes()
  local saved = hs.settings.get("blob.tomatoes")
  tomatoes = (saved and saved.day == today()) and saved.n or 0
end
local function saveTomatoes() hs.settings.set("blob.tomatoes", { day = today(), n = tomatoes }) end

local function inCall()
  for _, d in ipairs(hs.audiodevice.allInputDevices()) do
    if d:inUse() then return true end
  end
  return false
end

local function frameFor(px) return hs.geometry.rect(px, y, W, H) end

local function currentScreen()
  return (wv and wv:hswindow() and wv:hswindow():screen()) or screen()
end

local function pickTarget()
  local f = currentScreen():frame()
  local lo = math.max(f.x, homeX - WANDER)
  local hi = math.min(f.x + f.w - W, homeX + WANDER)
  targetX = math.random(math.floor(lo), math.floor(hi))
end

local function startDrag()
  if dragTimer then return end
  local m0 = hs.mouse.absolutePosition()
  local ox, oy, moved = m0.x - x, m0.y - y, false
  targetX = nil
  dragTimer = hs.timer.doEvery(0.016, function()
    local m = hs.mouse.absolutePosition()
    if math.abs(m.x - m0.x) > 4 or math.abs(m.y - m0.y) > 4 then
      if not moved then moved = true; if state ~= "call" then js("setState('alert','')") end end
    end
    if moved then x, y = m.x - ox, m.y - oy; wv:frame(frameFor(x)) end
    if not hs.eventtap.checkMouseButtons().left then
      dragTimer:stop(); dragTimer = nil
      if moved then
        homeX = x
        hs.settings.set("blob.pos", { x = x, y = y })
        setState(state == "walk" and "idle" or state)
        say("ooh, nice spot 🏡", 2000)
      else
        M.onClick()
      end
    end
  end)
end

local function step()
  if state ~= "walk" or not targetX then return end
  local d = targetX - x
  if math.abs(d) < 2 then targetX = nil; setState("idle"); return end
  local newDir = d > 0 and "right" or "left"
  if newDir ~= dir then dir = newDir; setState("walk") end
  x = x + (d > 0 and 1.5 or -1.5)
  wv:frame(frameFor(x))
end

local function startFocus()
  focusEnd = os.time() + FOCUS_MIN * 60
  targetX = nil; dir = nil
  setState("focus")
  say("Let's focus! " .. FOCUS_MIN .. " min 💪", 3000)
end

local function stopFocus(done)
  focusEnd = nil
  js("setTimer('')")
  if done then
    tomatoes = tomatoes + 1; saveTomatoes()
    lastStretch = os.time()
    hs.sound.getByName("Glass"):play()
    hs.notify.new({ title = "Blobby 🍅", informativeText = "Focus done! " .. tomatoes .. " today. Take 5." }):send()
    setState("happy"); transientUntil = os.time() + 8
    say("Nice!! 🍅 x" .. tomatoes .. " today. Take a 5-min break ☕", 8000)
  else
    setState("idle")
    say("Focus cancelled. No worries 💚", 3000)
  end
end

local function fmt(sec) return string.format("%d:%02d", sec // 60, sec % 60) end

local function startAway(label, mins)
  if focusEnd then focusEnd = nil end
  awayUntil, awayLabel = os.time() + mins * 60, label
  targetX, dir = nil, nil
  js(string.format("setSign(%q)", label))
  setState("away")
  js(string.format("setTimer('back in %s')", fmt(mins * 60)))
end

local function endAway(early)
  awayUntil, awayLabel = nil, nil
  lastStretch, lastWater = os.time(), os.time()
  js("setTimer('')")
  setState("happy"); transientUntil = os.time() + 4
  if not early then hs.sound.getByName("Pop"):play() end
  say("Welcome back! 👋 Click me to focus.", 4000)
end

-- Festivals: {key, prop emoji, greeting}. Date ranges are "MM-DD" inclusive.
local FIXED = {
  { "12-31", "01-01", "newyear",   "🎉", "Happy New Year! 🎉" },
  { "02-14", "02-14", "valentine", "💘", "Happy Valentine's Day 💘" },
  { "03-17", "03-17", "stpatricks","🍀", "Happy St. Patrick's Day 🍀" },
  { "10-24", "10-31", "halloween", "🎃", "Happy Halloween! 🎃👻" },
  { "12-20", "12-26", "christmas", "🎄", "Merry Christmas! 🎄" },
}
-- Lunar-calendar festivals move every year: "YYYY-MM-DD" start, number of days
local DATED = {
  { "2026-11-06", 5, "diwali", "🪔", "Happy Diwali! 🪔✨" },
  { "2027-10-27", 5, "diwali", "🪔", "Happy Diwali! 🪔✨" },
  { "2027-02-06", 3, "lunarny", "🧧", "Happy Lunar New Year! 🧧" },
  { "2027-03-21", 2, "holi", "🎨", "Happy Holi! 🌈" },
  { "2027-03-28", 1, "easter", "🐣", "Happy Easter! 🐣" },
}

local function inRange(t, date, days)
  local yr, m, dd = date:match("(%d+)-(%d+)-(%d+)")
  local start = os.time({ year = tonumber(yr), month = tonumber(m), day = tonumber(dd), hour = 0 })
  return t >= start and t < start + (days or 1) * 86400
end

local function festivalFor(t)
  local md = os.date("%m-%d", t)
  for _, d in ipairs(config.specialDays) do
    if inRange(t, d.date, d.days) then return d.costume or "launch", d.prop or "🚀", d.greeting or "Big day! 🚀" end
  end
  if md == config.birthday then return "birthday", "🎂", "HAPPY BIRTHDAY!! 🎂🥳 Hope it's a great one!" end
  local d = os.date("*t", t)
  if d.month == 11 and d.wday == 5 and d.day >= 22 and d.day <= 28 then return "thanksgiving", "🦃", "Happy Thanksgiving! 🦃" end
  for _, f in ipairs(DATED) do
    if inRange(t, f[1], f[2]) then return f[3], f[4], f[5] end
  end
  for _, f in ipairs(FIXED) do
    local a, b = f[1], f[2]
    if (a <= b and md >= a and md <= b) or (a > b and (md >= a or md <= b)) then return f[3], f[4], f[5] end
  end
end

local festDay
local function applyFestival(force)
  local day = today()
  if not force and festDay == day then return end
  festDay = day
  local key, prop, greet = festivalFor(os.time())
  js(key and string.format("setFest(%q,%q)", key, prop) or "setFest(null)")
  if key and hs.settings.get("blob.festGreeted") ~= day and not inCall() then
    hs.settings.set("blob.festGreeted", day)
    hs.timer.doAfter(7, function() say(greet, 8000) end)
  end
end

local function brain()
  local now = os.time()
  applyFestival(false)
  if awayUntil then
    local left = awayUntil - now
    if left <= 0 then endAway(false) else js(string.format("setTimer('back in %s')", fmt(left))) end
    return
  end
  local calling = inCall()

  if calling and not focusEnd then
    if state ~= "call" then targetX = nil; dir = nil; setState("call") end
    return
  elseif state == "call" then
    setState(focusEnd and "focus" or "idle")
    say("Call done! 👋", 3000)
  end

  if focusEnd then
    local left = focusEnd - now
    if left <= 0 then stopFocus(true) else
      js(string.format("setTimer('%d:%02d')", left // 60, left % 60))
    end
    return
  end

  if now < transientUntil then return end
  if state == "happy" or state == "alert" then setState("idle") end

  if now - lastStretch >= STRETCH_MIN * 60 then
    lastStretch = now; targetX = nil
    setState("alert"); transientUntil = now + 12
    say("Stretch break! 🧘 Stand up & roll your shoulders", 12000)
    return
  end
  if now - lastWater >= WATER_MIN * 60 then
    lastWater = now; targetX = nil
    setState("alert"); transientUntil = now + 10
    say("Sip some water 💧", 10000)
    return
  end

  if state == "idle" and math.random() < 0.08 then pickTarget(); setState("walk") end
end

local PETS = { "hehe 💚", "*happy wiggle*", "you're doing great!", "boop!", "🍅 x%d today", "click me to focus!" }

function M.start(opts)
  for k, v in pairs(opts or {}) do config[k] = v end
  FOCUS_MIN, STRETCH_MIN, WATER_MIN = config.focusMinutes, config.stretchMinutes, config.waterMinutes
  WANDER = config.wander
  loadTomatoes()
  local f = screen():frame()
  local saved = hs.settings.get("blob.pos")
  x = saved and saved.x or (f.x + f.w / 2 - W / 2)
  y = saved and saved.y or (f.y + f.h - H)
  homeX = x

  local uc = hs.webview.usercontent.new("blob")
  uc:setCallback(function(msg)
    if msg.body == "down" then
      startDrag()
    elseif msg.body == "menu" then
      M.showMenu()
    elseif msg.body == "pet" and os.time() - lastPet > 20 and state ~= "focus" and state ~= "call" then
      lastPet = os.time()
      say(string.format(PETS[math.random(#PETS)], tomatoes), 2500)
    end
  end)

  wv = hs.webview.new(frameFor(x), { developerExtrasEnabled = false }, uc)
    :windowStyle({ "borderless", "nonactivating" })
    :transparent(true)
    :allowTextEntry(false)
    :level(hs.drawing.windowLevels.floating)
    :behavior(hs.drawing.windowBehaviors.canJoinAllSpaces + hs.drawing.windowBehaviors.stationary)
    :shadow(false)
    :url("file://" .. HERE .. "blob.html")
    :show()

  M.hotkey = hs.hotkey.bind(config.hotkeyMods, config.hotkeyToggle, M.toggle)
  M.screenWatcher = hs.screen.watcher.new(M.reposition):start()

  moveTimer = hs.timer.doEvery(0.03, step)
  brainTimer = hs.timer.doEvery(1, brain)
  hs.timer.doAfter(1.0, function() applyFestival(true) end)
  hs.timer.doAfter(1.5, function()
    if inCall() then return end
    local h = tonumber(os.date("%H"))
    local hi = h < 12 and "Good morning" or (h < 17 and "Good afternoon" or "Good evening")
    say(hi .. "! I'm Blobby 💚 Click me to focus.", 5000)
  end)
end

function M.onClick()
  if awayUntil then endAway(true); return end
  if focusEnd then stopFocus(false) else startFocus() end
end

function M.fest(key, prop) js(key and string.format("setFest(%q,%q)", key, prop or "") or "setFest(null)") end
function M.festivalFor(t) return festivalFor(t) end
function M.away(label, mins) startAway(label, mins) end

function M.showMenu()
  local away = awayUntil ~= nil
  local items = {
    { title = "🎯 Focus " .. config.focusMinutes .. " min", fn = function() if awayUntil then endAway(true) end; FOCUS_MIN = config.focusMinutes; startFocus() end },
    { title = "🎯 Focus " .. config.focusMinutes * 2 .. " min", fn = function() if awayUntil then endAway(true) end; FOCUS_MIN = config.focusMinutes * 2; startFocus() end },
    { title = "-" },
    { title = "🍜 Out for lunch (1 hr)", fn = function() startAway("🍜 Out for lunch", 60) end },
    { title = "☕ Coffee break (15 min)", fn = function() startAway("☕ On a break", 15) end },
    { title = "🚶 Walk (30 min)", fn = function() startAway("🚶 Out for a walk", 30) end },
    { title = "⏳ BRB (5 min)", fn = function() startAway("⏳ BRB", 5) end },
    { title = "👋 I'm back", disabled = not away, fn = function() endAway(true) end },
    { title = "-" },
    { title = "🍅 Today: " .. tomatoes, disabled = true },
    { title = "Hide Blobby (⌃⌥⌘B)", fn = M.toggle },
  }
  if focusEnd then table.insert(items, 3, { title = "⏹ Stop focus", fn = function() stopFocus(false) end }) end
  menu = menu or hs.menubar.new(false)
  menu:setMenu(items):popupMenu(hs.mouse.absolutePosition(), true)
end

function M.stop()
  for _, t in ipairs({ moveTimer, brainTimer, dragTimer }) do if t then t:stop() end end
  if M.hotkey then M.hotkey:delete() end
  if M.screenWatcher then M.screenWatcher:stop() end
  if wv then wv:delete() end
  wv, moveTimer, brainTimer, dragTimer = nil, nil, nil, nil
end

function M.toggle()
  if not wv then return end
  if wv:isVisible() then wv:hide() else wv:show() end
end

function M.reposition()
  if not wv then return end
  local f = currentScreen():frame()
  if x < f.x or x > f.x + f.w - W or y < f.y or y > f.y + f.h - H then
    f = screen():frame()
    x, y, homeX, targetX = f.x + f.w / 2 - W / 2, f.y + f.h - H, nil, nil
    homeX = x
    wv:frame(frameFor(x))
  end
end

function M.debug()
  local f = wv and wv:frame()
  return { state = state, away = awayLabel, focusing = focusEnd ~= nil, visible = wv and wv:isVisible(), frame = f and { x = f.x, y = f.y } }
end

return M
