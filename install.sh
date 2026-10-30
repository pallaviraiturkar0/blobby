#!/usr/bin/env bash
# Blobby installer: installs Hammerspoon (if needed) and drops Blobby into ~/.hammerspoon
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/blobby"
DEST="$HOME/.hammerspoon"
INIT="$DEST/init.lua"

if [ ! -d "/Applications/Hammerspoon.app" ]; then
  if command -v brew >/dev/null; then
    echo "→ Installing Hammerspoon via Homebrew"
    brew install --cask hammerspoon
  else
    echo "✗ Please install Hammerspoon first: https://www.hammerspoon.org" >&2
    exit 1
  fi
fi

mkdir -p "$DEST/blobby"
cp "$SRC/init.lua" "$SRC/blob.html" "$DEST/blobby/"
echo "→ Copied Blobby to $DEST/blobby"

touch "$INIT"
if ! grep -q 'require("blobby")' "$INIT"; then
  cat >> "$INIT" <<'LUA'

-- Blobby 💚 https://github.com/pallaviraiturkar0/blobby
blobby = require("blobby")
blobby.start({
  -- birthday = "MM-DD",
  -- focusMinutes = 25,
})
LUA
  echo "→ Added Blobby to $INIT"
fi

# update.sh sets BLOBBY_NO_RELOAD=1 and reloads Hammerspoon itself
if [ -n "${BLOBBY_NO_RELOAD:-}" ]; then exit 0; fi

open -a Hammerspoon
osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null 2>&1 || true
echo
echo "✓ Done! If Blobby doesn't appear, open Hammerspoon → Preferences and enable Accessibility,"
echo "  then click the 🔨 menu-bar icon → Reload Config."
