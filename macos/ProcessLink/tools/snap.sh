#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages
#        APP_SNAPSHOT_PAGES=all,settings tools/snap.sh
set -u
app=~/Applications/ProcessLink.app/Contents/MacOS/ProcessLink
store=/tmp/ProcessLink-test.store
shots=/tmp/ProcessLink-shots
maps=/tmp/ProcessLink-maps
# A crashed run leaves saved window state, and the next launch would wait on a "reopen windows?" alert.
rm -rf ~/Library/Saved\ Application\ State/com.te.processlink.savedState
# The window frame is persisted separately and a single oversized run would
# otherwise make every later screenshot 1510 pt wide.
defaults delete com.te.processlink "NSWindow Frame main" 2>/dev/null || true
# Seed data only fills an empty store, so start from nothing.
rm -f $store $store-shm $store-wal
rm -rf $shots $maps
# Launch in the background, then bring the app forward once. A snapshot of an
# inactive window is dimmed (and Stage Manager may shrink it), so the run has
# to be the key window for the whole capture.
APP_STORE=$store APP_MAPS_DIR=$maps APP_SEED=1 APP_SNAPSHOT=$shots $app &
pid=$!
sleep 1
osascript -e 'tell application "ProcessLink" to activate' >/dev/null 2>&1 || true
wait $pid
