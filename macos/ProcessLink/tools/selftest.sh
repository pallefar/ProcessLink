#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -u
rm -rf ~/Library/Saved\ Application\ State/com.te.processlink.savedState
store=/tmp/ProcessLink-self.store
rm -f $store $store-shm $store-wal
APP_STORE=$store ~/Applications/ProcessLink.app/Contents/MacOS/ProcessLink --selftest
