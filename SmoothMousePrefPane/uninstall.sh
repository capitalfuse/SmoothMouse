#!/bin/sh

# NOTE: Uninstaller currently ONLY supports system-wide installation.

KEXT="/System/Library/Extensions/SmoothMouse.kext"
PREFPANE="/Library/PreferencePanes/SmoothMouse.prefPane"
DAEMON="smoothmoused"

#env > /tmp/sm

/sbin/kextunload $KEXT
rm -rf $KEXT

rm -rf $PREFPANE
rm -f ~/Library/Preferences/com.cyberic.SmoothMouse.plist
rm -f ~/Library/Preferences/com.cyberic.SmoothMouseUpdater.plist
rm -f ~/Library/LaunchAgents/com.cyberic.smoothmouse.plist
rm -f ~/Library/LaunchAgents/com.cyberic.smoothmouseupdater.plist
rm /usr/bin/smoothmouse

/usr/bin/killall $DAEMON

/usr/bin/killall -u $USER "System Preferences"
sudo -u $USER /usr/bin/open "/Applications/System Preferences.app"

