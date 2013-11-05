#!/bin/sh

# This script should complement FeedbackReporter, so try to make sure
# not to gather redundant information -- it will just take extra time
# before a report can be submitted.

# Read versions
echo "Preference Pane CFBundleVersion: $(defaults read /Library/PreferencePanes/SmoothMouse.prefPane/Contents/Info.plist CFBundleVersion)"
echo "Preference Pane SMCommitID: $(defaults read /Library/PreferencePanes/SmoothMouse.prefPane/Contents/Info.plist SMCommitID)"
echo ""
echo "Kext CFBundleVersion: $(defaults read /Library/Extensions/SmoothMouse.kext/Contents/Info.plist CFBundleVersion)"
echo "Kext SMCommitID: $(defaults read /Library/Extensions/SmoothMouse.kext/Contents/Info.plist SMCommitID)"

echo

# GPU and monitor
system_profiler SPDisplaysDataType

echo

# Display all loaded kexts
kextstat

echo

# Check if the prefpane is loaded
system_profiler SPPrefPaneDataType | grep -i "SmoothMouse"

echo

# Check if the daemon is running
ps aux | grep -i "SmoothMouse" | grep -v grep
