-- Example ~/.hammerspoon/init.lua with every Blobby option
blobby = require("blobby")
blobby.start({
  focusMinutes   = 25,          -- right-click menu also offers 2x this
  stretchMinutes = 60,
  waterMinutes   = 90,
  wander         = 300,         -- px either side of where you drop Blobby
  birthday       = "07-14",     -- MM-DD: party hat, cake & confetti 🎂
  specialDays    = {
    -- One-off days (launches, conferences, anniversaries). Costumes: launch, birthday, newyear, halloween, christmas…
    { date = "2030-01-15", days = 1, costume = "launch", prop = "🚀", greeting = "Launch day! Ship it! 🚀" },
  },
  hotkeyMods     = { "ctrl", "alt", "cmd" },
  hotkeyToggle   = "B",         -- ⌃⌥⌘B hides / shows Blobby
})
