#/usr/bin/env bash

# redirect stdout+stderr to logfile
#LOGFILE=report.txt
#exec > $LOGFILE 2>&1

function start {
    echo "=== ${@} ==="
}

function end {
    echo "==="
}

start Computer model

sysctl -n hw.model machdep.cpu.brand_string

start GPU and monitor

system_profiler SPDisplaysDataType

start OS X version and build number

sw_vers

start Endianness

# OS X bitness
getconf LONG_BIT

start SmoothMouse settings

# SmoothMouse settings
defaults read ~/Library/Preferences/com.cyberic.SmoothMouse.plist

start SmoothMouse version information

# Read versions
defaults read /Library/PreferencePanes/SmoothMouse.prefPane/Contents/Info.plist CFBundleVersion
defaults read /System/Library/Extensions/SmoothMouse.kext/Contents/Info.plist CFBundleVersion

start Loaded kexts

# Display all loaded kexts
kextstat

start Prefpane information

system_profiler SPPrefPaneDataType | grep -i "SmoothMouse"

start Daemon running
ps aux | grep -i "SmoothMouse" | grep -v grep

start Daemon runtime information
killall -SIGUSR SmoothMouseDaemon

start KEXT plist

cat /System/Library/Extensions/SmoothMouse.kext/Contents/Info.plist

start PREFPANE plist

cat /Library/PreferencePanes/SmoothMouse.prefPane/Contents/Info.plist




