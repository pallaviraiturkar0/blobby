std = "lua54"
globals = { "hs", "blobby" }
max_line_length = 180
exclude_files = { ".lua/**", ".luarocks/**", "scripts/node_modules/**" }
-- The test harness swaps in a fake clock
files["tests/"] = { globals = { "os" } }
