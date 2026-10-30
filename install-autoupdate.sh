#!/usr/bin/env bash
# Opt-in: install a launchd agent that runs update.sh at login and once a day.
# Usage: ./install-autoupdate.sh [--hour 0-23]   (default 10, i.e. 10:00 local time)
#        ./install-autoupdate.sh --uninstall
set -euo pipefail

LABEL="com.github.pallaviraiturkar0.blobby.update"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$DIR/launchd/$LABEL.plist"
AGENTS="$HOME/Library/LaunchAgents"
PLIST="$AGENTS/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/blobby-update.log"
DOMAIN="gui/$(id -u)"

usage() { echo "Usage: $0 [--hour 0-23] | --uninstall" >&2; exit 2; }

xml_escape() {
  local s="$1" amp="&amp;" lt="&lt;" gt="&gt;"
  s="${s//&/$amp}"; s="${s//</$lt}"; s="${s//>/$gt}"
  printf '%s' "$s"
}

unload() { launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true; }

hour=10
case "${1:-}" in
  "") ;;
  --uninstall)
    [ $# -eq 1 ] || usage
    unload
    rm -f "$PLIST"
    echo "✓ Blobby auto-update removed. Update manually any time with: $DIR/update.sh"
    exit 0
    ;;
  --hour)
    [ $# -eq 2 ] || usage
    case "$2" in ''|*[!0-9]*) usage ;; esac
    hour=$((10#$2))
    [ "$hour" -le 23 ] || usage
    ;;
  *) usage ;;
esac

if ! git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ $DIR is not a git clone, so it can't update itself." >&2
  echo "  Install with: git clone https://github.com/pallaviraiturkar0/blobby.git && cd blobby && ./install.sh" >&2
  exit 1
fi

mkdir -p "$AGENTS" "$(dirname "$LOG_FILE")"
# Keep "&" literal in ${var//pat/rep} on bash 5.2+ (macOS's bash 3.2 doesn't have this option)
shopt -u patsub_replacement 2>/dev/null || true
dir_xml="$(xml_escape "$DIR")"
log_xml="$(xml_escape "$LOG_FILE")"
plist="$(cat "$TEMPLATE")"
plist="${plist//__BLOBBY_DIR__/$dir_xml}"
plist="${plist//__LOG_FILE__/$log_xml}"
plist="${plist//__HOUR__/$hour}"
printf '%s\n' "$plist" > "$PLIST"
if command -v plutil >/dev/null; then plutil -lint -s "$PLIST"; fi

unload
launchctl bootstrap "$DOMAIN" "$PLIST"
printf '✓ Blobby will update itself when you log in and every day at %02d:00.\n' "$hour"
echo "  Log: $LOG_FILE"
echo "  Turn off with: $DIR/install-autoupdate.sh --uninstall"
