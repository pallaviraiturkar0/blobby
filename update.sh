#!/usr/bin/env bash
# Blobby updater: fast-forwards this clone to the latest default branch,
# reinstalls Blobby into ~/.hammerspoon and reloads Hammerspoon.
# Usage: ./update.sh [--force]   (--force reinstalls even when already up to date)
set -euo pipefail

# Everything lives in main() so bash has read the whole script before `git pull` can rewrite this file.
main() {
  local force=0
  case "${1:-}" in
    "") ;;
    --force) force=1 ;;
    *) echo "Usage: $0 [--force]" >&2; return 2 ;;
  esac

  cd "$(dirname "${BASH_SOURCE[0]}")"
  log "Checking for Blobby updates in $PWD"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    log "✗ $PWD is not a git clone. Re-install with: git clone https://github.com/pallaviraiturkar0/blobby.git"
    return 1
  fi

  local default branch
  default="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)"
  default="${default#origin/}"
  branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || echo "(detached)")"
  if [ "$branch" != "$default" ]; then
    log "✗ On branch '$branch', not '$default'. Run: git checkout $default"
    return 1
  fi
  if ! git diff --quiet || ! git diff --cached --quiet; then
    log "✗ You have local changes. Commit or stash them (git stash), then run this again."
    return 1
  fi

  local before after
  before="$(git rev-parse HEAD)"
  if ! git pull --ff-only --quiet origin "$default"; then
    log "✗ Couldn't fast-forward '$default' (no network, or local commits that aren't on GitHub)."
    return 1
  fi
  after="$(git rev-parse HEAD)"

  if [ "$before" = "$after" ] && [ "$force" -eq 0 ] && installed_matches; then
    log "✓ Already up to date ($(git rev-parse --short HEAD))"
    return 0
  fi
  if [ "$before" != "$after" ]; then
    log "→ Updated $(git rev-parse --short "$before") → $(git rev-parse --short "$after"):"
    git --no-pager log --format='    %s' "$before..$after"
  fi

  BLOBBY_NO_RELOAD=1 ./install.sh
  reload_hammerspoon
  log "✓ Blobby is up to date ($(git rev-parse --short HEAD))"
}

# True when ~/.hammerspoon/blobby already has this clone's files (e.g. not after a manual git pull)
installed_matches() {
  local f
  for f in init.lua blob.html; do
    cmp -s "blobby/$f" "$HOME/.hammerspoon/blobby/$f" || return 1
  done
}

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }

hammerspoon_running() { pgrep -x Hammerspoon >/dev/null 2>&1; }

reload_hammerspoon() {
  if ! hammerspoon_running; then
    log "→ Hammerspoon isn't running; Blobby will load the new version next time it starts"
    return 0
  fi
  # Works when the config has hs.allowAppleScript(true); otherwise restart Hammerspoon to load the new files
  if osascript -e 'tell application "Hammerspoon" to execute lua code "hs.reload()"' >/dev/null 2>&1; then
    log "→ Reloaded Hammerspoon"
  else
    osascript -e 'tell application "Hammerspoon" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do hammerspoon_running || break; sleep 0.5; done
    open -a Hammerspoon
    log "→ Restarted Hammerspoon"
  fi
}

main "$@"
