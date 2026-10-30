#!/usr/bin/env bash
# Tests update.sh and install-autoupdate.sh against a throwaway git remote, with macOS-only
# commands (brew, open, osascript, pgrep, launchctl) stubbed. Run from the repository root:
#   bash tests/test_update.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

pass=0 fail=0
ok() { pass=$((pass + 1)); echo "ok    $1"; }
not_ok() { fail=$((fail + 1)); echo "FAIL  $1"; }
check() { local name="$1"; shift; if "$@"; then ok "$name"; else not_ok "$name"; fi; }
not() { ! "$@"; }
called() { grep -q "$1" "$CALLS"; }
installed_has() { grep -q "$1" "$DEST/blob.html"; }

export HOME="$WORK/home" CALLS="$WORK/calls" HS_QUIT="$WORK/hs_quit"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkdir -p "$HOME" "$WORK/bin"

# Stubs record their arguments in $CALLS. STUB_HS_RUNNING=0 means Hammerspoon isn't running,
# STUB_APPLESCRIPT=0 means "execute lua code" is disabled, STUB_QUIT_IGNORED=1 means Hammerspoon won't quit.
for cmd in brew open launchctl; do
  # shellcheck disable=SC2016 # $* and $CALLS expand when the stub runs
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$CALLS"\n' "$cmd" > "$WORK/bin/$cmd"
done
cat > "$WORK/bin/pgrep" <<'STUB'
#!/usr/bin/env bash
echo "pgrep $*" >> "$CALLS"
[ "${STUB_HS_RUNNING:-1}" = 1 ] && [ ! -e "$HS_QUIT" ]
STUB
cat > "$WORK/bin/osascript" <<'STUB'
#!/usr/bin/env bash
echo "osascript $*" >> "$CALLS"
case "$*" in
  *"execute lua code"*) [ "${STUB_APPLESCRIPT:-1}" = 1 ] ;;
  *"to quit"*) [ "${STUB_QUIT_IGNORED:-0}" = 1 ] || touch "$HS_QUIT" ;;
esac
STUB
chmod +x "$WORK/bin/"*
export PATH="$WORK/bin:$PATH"

# A remote with the current working tree as its only commit, and a clone of it
git init -q -b main "$WORK/seed"
(cd "$ROOT" && tar --exclude=.git --exclude=node_modules -cf - .) | tar -xf - -C "$WORK/seed"
git -C "$WORK/seed" add -A && git -C "$WORK/seed" commit -qm initial
git clone -q --bare "$WORK/seed" "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/clone"
CLONE="$WORK/clone"
DEST="$HOME/.hammerspoon/blobby"

push_change() {
  git -C "$WORK/seed" pull -q --ff-only "$WORK/origin.git" main
  echo "<!-- $1 -->" >> "$WORK/seed/blobby/blob.html"
  git -C "$WORK/seed" commit -qam "$1"
  git -C "$WORK/seed" push -q "$WORK/origin.git" main
}
run_update() { : > "$CALLS"; rm -f "$HS_QUIT"; "$CLONE/update.sh" "$@" > "$WORK/out" 2>&1; }

"$CLONE/install.sh" > /dev/null
check "install.sh copies Blobby" cmp -s "$CLONE/blobby/blob.html" "$DEST/blob.html"

push_change "update one"
check "update.sh pulls and reinstalls" run_update
check "installed files match the new version" cmp -s "$CLONE/blobby/blob.html" "$DEST/blob.html"
check "update lists the new commits" grep -q "update one" "$WORK/out"
check "only looks for this user's Hammerspoon" called "^pgrep -x -u $(id -u) Hammerspoon"
check "reloads Hammerspoon via AppleScript" called 'execute lua code "hs.reload()"'
check "doesn't restart Hammerspoon when reload works" not called "^open "
check "init.lua lines are added only once" test "$(grep -c 'require("blobby")' "$HOME/.hammerspoon/init.lua")" = 1

check "no-op when already up to date" run_update
check "says it's up to date" grep -q "Already up to date" "$WORK/out"
check "doesn't reload when nothing changed" not grep -qv "^pgrep " "$CALLS"

git -C "$WORK/seed" pull -q --ff-only "$WORK/origin.git" main
echo "<!-- pulled by hand -->" >> "$WORK/seed/blobby/blob.html"
git -C "$WORK/seed" commit -qam "pulled by hand" && git -C "$WORK/seed" push -q "$WORK/origin.git" main
git -C "$CLONE" pull -q --ff-only
check "reinstalls after a manual git pull" run_update
check "installed files match after a manual git pull" installed_has "pulled by hand"

check "--force reinstalls anyway" run_update --force
check "--force reloads" called "hs.reload"
check "rejects unknown options" not run_update --bogus

push_change "update two"
export STUB_APPLESCRIPT=0
check "restarts Hammerspoon when AppleScript is disabled" run_update
unset STUB_APPLESCRIPT
check "restart quits Hammerspoon" called "to quit"
check "restart reopens Hammerspoon" called "^open -a Hammerspoon"

push_change "update 2b"
export STUB_APPLESCRIPT=0 STUB_QUIT_IGNORED=1
check "fails when Hammerspoon won't quit" not run_update
unset STUB_APPLESCRIPT STUB_QUIT_IGNORED
check "tells you to restart Hammerspoon" grep -q "Restart Hammerspoon" "$WORK/out"
check "doesn't claim it restarted" not called "^open "

push_change "update three"
export STUB_HS_RUNNING=0
check "updates files when Hammerspoon isn't running" run_update
unset STUB_HS_RUNNING
check "doesn't start Hammerspoon when it wasn't running" not called "^open "
check "doesn't talk to Hammerspoon when it wasn't running" not called osascript
check "installed files match after update three" cmp -s "$CLONE/blobby/blob.html" "$DEST/blob.html"

push_change "update four"
echo "-- local tweak" >> "$CLONE/blobby/init.lua"
check "refuses to update with local changes" not run_update
check "explains the local changes" grep -q "local changes" "$WORK/out"
check "leaves the install untouched" not installed_has "update four"
git -C "$CLONE" checkout -q -- blobby/init.lua

git -C "$CLONE" checkout -q -b experiment
check "refuses to update off the default branch" not run_update
git -C "$CLONE" checkout -q main

echo "local" > "$CLONE/local.txt"
git -C "$CLONE" add local.txt && git -C "$CLONE" commit -qm "local commit"
check "refuses to update a diverged clone" not run_update
check "leaves the install untouched when diverged" not installed_has "update four"
git -C "$CLONE" reset -q --hard origin/main
check "updates once the clone is clean again" run_update
check "installed files match after update four" cmp -s "$CLONE/blobby/blob.html" "$DEST/blob.html"

echo "<!-- unpushed -->" >> "$CLONE/blobby/blob.html"
git -C "$CLONE" commit -qam "unpushed"
check "refuses to install unpushed local commits" not run_update
check "explains the unpushed commits" grep -q "local commits" "$WORK/out"
check "doesn't install the unpushed commit" not installed_has "unpushed"
git -C "$CLONE" reset -q --hard origin/main
check "updates after dropping the unpushed commit" run_update

# install-autoupdate.sh
PLIST="$HOME/Library/LaunchAgents/com.github.pallaviraiturkar0.blobby.update.plist"
read_plist() {
  python3 - "$PLIST" "$1" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
print({"program": p["ProgramArguments"][-1], "hour": p["StartCalendarInterval"]["Hour"],
       "log": p["StandardOutPath"], "label": p["Label"], "load": p["RunAtLoad"]}[sys.argv[2]])
PY
}
: > "$CALLS"
autoupdate() { "$1/install-autoupdate.sh" "${@:2}" > /dev/null 2>&1; }
check "install-autoupdate.sh installs the agent" autoupdate "$CLONE"
check "plist is valid and runs update.sh" test "$(read_plist program)" = "$CLONE/update.sh"
check "runs daily at 10:00 by default" test "$(read_plist hour)" = 10
check "runs at login" test "$(read_plist load)" = True
check "logs to ~/Library/Logs" test "$(read_plist log)" = "$HOME/Library/Logs/blobby-update.log"
check "loads the agent with launchctl" called "^launchctl bootstrap gui/$(id -u) $PLIST"
check "--hour sets the time" autoupdate "$CLONE" --hour 07
check "hour 07 is stored as 7" test "$(read_plist hour)" = 7
check "rejects an invalid hour" not autoupdate "$CLONE" --hour 24
check "rejects a non-numeric hour" not autoupdate "$CLONE" --hour 9am
check "--uninstall succeeds" autoupdate "$CLONE" --uninstall
check "--uninstall removes the plist" test ! -e "$PLIST"
check "--uninstall unloads it with launchctl" called "^launchctl bootout gui/$(id -u)/com.github.pallaviraiturkar0.blobby.update"

# Paths with XML special characters are escaped
ODD="$WORK/a & <b> --x"
git clone -q "$WORK/origin.git" "$ODD"
check "handles paths with &, <> and --" autoupdate "$ODD"
check "generated plist is well-formed XML" python3 -c 'import sys, xml.dom.minidom; xml.dom.minidom.parse(sys.argv[1])' "$PLIST"
check "escaped path round-trips" test "$(read_plist program)" = "$ODD/update.sh"

echo
echo "$((pass + fail)) tests, $fail failures"
[ "$fail" -eq 0 ]
