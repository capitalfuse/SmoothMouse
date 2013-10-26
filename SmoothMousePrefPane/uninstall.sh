#!/bin/sh

# NOTE: Uninstaller currently ONLY supports system-wide installation.

# PARAMETERS:
#  -k : keep preferences

KEXT="/System/Library/Extensions/SmoothMouse.kext"
KEXT2="/Library/Extensions/SmoothMouse.kext"
KEXT_IDENTIFIER="com.cyberic.SmoothMouse"
PREFPANE="/Library/PreferencePanes/SmoothMouse.prefPane"
DAEMON="SmoothMouseDaemon"
DAEMON_OLD="smoothmoused"

while getopts “k” OPTION
do
    case $OPTION in
        k)
            KEEP_PREFERENCES=1
            ;;
    esac
done

#env > /tmp/sm

/sbin/kextunload -b "$KEXT_IDENTIFIER"
rm -rf $KEXT
rm -rf $KEXT2

rm -rf $PREFPANE

if [ -z "$KEEP_PREFERENCES" ]
then
    rm -f ~/Library/Preferences/com.cyberic.SmoothMouse.plist
    rm -f ~/Library/Preferences/com.cyberic.SmoothMouseUpdater.plist
fi

rm -f ~/Library/LaunchAgents/com.cyberic.smoothmouse.plist
rm -f ~/Library/LaunchAgents/com.cyberic.smoothmouseupdater.plist
rm /usr/bin/smoothmouse

pkgutil --forget "com.cyberic.pkg.SmoothMouseKext"
pkgutil --forget "com.cyberic.pkg.SmoothMouseKext2"
pkgutil --forget "com.cyberic.pkg.SmoothMousePrefPane"

/usr/bin/killall $DAEMON
/usr/bin/killall $DAEMON_OLD

/usr/bin/killall -u $USER "System Preferences"
sudo -u $USER /usr/bin/open "/Applications/System Preferences.app"