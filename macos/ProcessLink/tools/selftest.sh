#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.te.processlink.savedState
store=/tmp/ProcessLink-self.store
maps=/tmp/ProcessLink-maps-self
rm -f $store $store-shm $store-wal
rm -rf $maps
APP_STORE=$store APP_MAPS_DIR=$maps ~/Applications/ProcessLink.app/Contents/MacOS/ProcessLink --selftest
