-- Run from the repository root: lua tests/run.lua
package.path = "./tests/?.lua;" .. package.path
local Stub = require("hs_stub")

local tests, failures = {}, 0
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local function eq(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%s: expected %s, got %s", msg or "values differ", tostring(expected), tostring(actual)), 2)
  end
end

local function count(list, pattern)
  local n = 0
  for _, s in ipairs(list) do if s:find(pattern) then n = n + 1 end end
  return n
end

local function completeFocus(env)
  env.M.onClick()
  env.advance(25 * 60)
  env.tick()
end

-- #2: the 🍅 count resets when the day changes while Hammerspoon keeps running
test("tomato count resets at midnight without a reload", function()
  local env = Stub.new()
  env.settings["blob.tomatoes"] = { day = "2026-03-04", n = 3 }
  env.start()
  env.now = env.at(2026, 3, 4, 23)
  completeFocus(env)
  eq(env.settings["blob.tomatoes"].n, 4, "same-day count")
  env.now = env.at(2026, 3, 5, 9)
  env.tick()
  completeFocus(env)
  eq(env.settings["blob.tomatoes"].day, "2026-03-05", "saved day")
  eq(env.settings["blob.tomatoes"].n, 1, "count after midnight")
  env.restore()
end)

test("tomato count from a previous day is not restored on start", function()
  local env = Stub.new()
  env.settings["blob.tomatoes"] = { day = "2026-03-03", n = 7 }
  env.start()
  completeFocus(env)
  eq(env.settings["blob.tomatoes"].n, 1, "count")
  env.restore()
end)

-- #3: a one-off 2x session from the menu doesn't change the click-to-focus length
test("click-to-focus keeps the configured length after a 2x session", function()
  local env = Stub.new()
  env.start({ focusMinutes = 20 })
  env.menuItem("🎯 Focus 40 min").fn()
  eq(env.lastSaid(), "Let's focus! 40 min 💪", "2x session")
  env.M.onClick()
  env.M.onClick()
  eq(env.lastSaid(), "Let's focus! 20 min 💪", "next click")
  env.advance(20 * 60 - 1); env.tick()
  eq(env.M.debug().focusing, true, "still focusing before 20 min")
  env.advance(1); env.tick()
  eq(env.M.debug().focusing, false, "done at 20 min")
  env.restore()
end)

-- #4: lunar-calendar festivals have dates through 2030 and warn when they run out
test("moving festivals are recognised every year through 2030", function()
  local env = Stub.new()
  local expected = {
    { 2027, 2, 6, "lunarny" }, { 2027, 3, 21, "holi" }, { 2027, 3, 28, "easter" }, { 2027, 10, 27, "diwali" },
    { 2028, 1, 26, "lunarny" }, { 2028, 3, 10, "holi" }, { 2028, 4, 16, "easter" }, { 2028, 10, 15, "diwali" },
    { 2029, 2, 13, "lunarny" }, { 2029, 2, 28, "holi" }, { 2029, 4, 1, "easter" }, { 2029, 11, 3, "diwali" },
    { 2030, 2, 3, "lunarny" }, { 2030, 3, 19, "holi" }, { 2030, 4, 21, "easter" }, { 2030, 10, 24, "diwali" },
  }
  for _, e in ipairs(expected) do
    eq(env.M.festivalFor(env.at(e[1], e[2], e[3])), e[4], string.format("%04d-%02d-%02d", e[1], e[2], e[3]))
  end
  env.restore()
end)

test("no stale-festival warning while dates remain", function()
  local env = Stub.new({ now = os.time({ year = 2026, month = 3, day = 4, hour = 10 }) })
  env.start()
  eq(count(env.prints, "no upcoming dates"), 0, "warnings")
  env.restore()
end)

test("warns once per festival after its last listed date", function()
  local env = Stub.new({ now = os.time({ year = 2031, month = 1, day = 15, hour = 10 }) })
  env.start()
  for _, key in ipairs({ "diwali", "lunarny", "holi", "easter" }) do
    eq(count(env.prints, "no upcoming dates for '" .. key .. "'"), 1, key .. " warning")
  end
  env.restore()
end)

-- #5: malformed birthday/specialDays are dropped with a warning instead of crashing brain()
test("malformed specialDays don't crash brain()", function()
  local bad = {
    { { date = "Jan 15" } },
    { "2030-01-15" },
    { { date = "2026-03-04", days = "two" } },
    { { date = "2026-04-31" } },
    { { date = "2026-02-29" } },
    { { date = "2026-03-04", prop = {} } },
  }
  for i, specialDays in ipairs(bad) do
    local env = Stub.new()
    env.start({ specialDays = specialDays })
    local ok, err = pcall(env.tick, 2)
    eq(ok, true, "case " .. i .. " crashed: " .. tostring(err))
    eq(count(env.prints, "ignoring specialDays%[1%]"), 1, "case " .. i .. " warning")
    env.restore()
  end
end)

test("non-list specialDays is ignored with a warning", function()
  local env = Stub.new()
  env.start({ specialDays = "2030-01-15" })
  env.tick(2)
  eq(count(env.prints, "ignoring specialDays"), 1, "warning")
  env.restore()
end)

test("valid special days still apply alongside invalid ones", function()
  local env = Stub.new()
  env.start({ specialDays = { { date = "2026-13-01" }, { date = "2026-03-04", costume = "launch", prop = "🚀" } } })
  env.tick()
  eq(count(env.prints, "ignoring specialDays%[1%]"), 1, "warning for bad entry")
  eq(env.M.festivalFor(env.now), "launch", "valid entry")
  eq(env.M.festivalFor(env.at(2028, 2, 29)), nil, "leap day is not a special day")
  env.restore()
end)

test("leap-day special days are accepted in leap years", function()
  local env = Stub.new()
  env.start({ specialDays = { { date = "2028-02-29", costume = "leap" } } })
  eq(count(env.prints, "ignoring"), 0, "warnings")
  eq(env.M.festivalFor(env.at(2028, 2, 29)), "leap", "leap day")
  env.restore()
end)

test("invalid birthdays are ignored with a warning", function()
  for _, b in ipairs({ 714, "7-14", "04-31", "13-01" }) do
    local env = Stub.new()
    env.start({ birthday = b })
    eq(count(env.prints, "ignoring birthday"), 1, "warning for " .. tostring(b))
    env.restore()
  end
end)

test("valid birthdays, including 02-29, still match", function()
  local env = Stub.new()
  env.start({ birthday = "02-29" })
  eq(count(env.prints, "ignoring"), 0, "warnings")
  eq(env.M.festivalFor(env.at(2028, 2, 29)), "birthday", "leap birthday")
  env.restore()
  env = Stub.new()
  env.start({ birthday = "03-04" })
  eq(env.M.festivalFor(env.now), "birthday", "birthday")
  env.restore()
end)

for _, t in ipairs(tests) do
  local ok, err = pcall(t.fn)
  Stub.reset()
  if ok then
    print("ok    " .. t.name)
  else
    failures = failures + 1
    print("FAIL  " .. t.name .. "\n      " .. tostring(err))
  end
end
print(string.format("\n%d tests, %d failures", #tests, failures))
os.exit(failures == 0 and 0 or 1)
