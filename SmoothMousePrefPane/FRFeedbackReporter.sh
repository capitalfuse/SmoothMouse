#!/bin/sh

# Computer model identifier, CPU name
sysctl -n hw.model machdep.cpu.brand_string

# GPU and monitor
system_profiler SPDisplaysDataType

# OS X version and build number
sw_vers

# OS X bitness
getconf LONG_BIT

# SmoothMouse settings
defaults read ~/Library/Preferences/com.cyberic.SmoothMouse.plist

# Read versions
defaults read /Library/PreferencePanes/SmoothMouse.prefPane/Contents/Info.plist CFBundleVersion
defaults read /System/Library/Extensions/SmoothMouse.kext/Contents/Info.plist CFBundleVersion

# Display all loaded kexts
kextstat

# Check if the prefpane is loaded
system_profiler SPPrefPaneDataType | grep -i "SmoothMouse"

# Check if the daemon is running
ps aux | grep -i "SmoothMouse" | grep -v grep
