#define PREFERENCE_PANE_LOCATION_BASE @"/Library/PreferencePanes/SmoothMousePrefs.prefPane"
#define LAUNCH_AGENT_DAEMON_FILENAME @"/Library/LaunchAgents/com.cyberic.smoothmouse2.plist"
#define LAUNCH_AGENT_UPDATER_FILENAME @"/Library/LaunchAgents/com.cyberic.smoothmouse2updater.plist"
#define PREFERENCES_FILENAME @"/Library/Preferences/com.cyberic.SmoothMouse2.plist"
#define DAEMON_FILENAME_BASE @"/Contents/SmoothMouseDaemon.app/Contents/MacOS/SmoothMouseDaemon"
#define UNINSTALL_SCRIPT_FILENAME_BASE @"/Contents/Resources/uninstall.sh"
#define UPDATER_FILENAME_BASE @"/Contents/SmoothMouseUpdater.app/Contents/MacOS/SmoothMouseUpdater"
#define KEXT_BUNDLE @"/Library/Extensions/SmoothMouse.kext"

#define SETTINGS_DEVICES @"Devices"
// device settings
#define SETTINGS_VENDOR_ID @"VendorID"
#define SETTINGS_PRODUCT_ID @"ProductID"
#define SETTINGS_MANUFACTURER @"Manufacturer"
#define SETTINGS_PRODUCT @"Product"
#define SETTINGS_ENABLED @"Enabled"
#define SETTINGS_ACCELERATION_CURVE @"Curve"
#define SETTINGS_VELOCITY @"Velocity"

#define SETTINGS_DRIVER @"Driver"
#define SETTINGS_FORCE_DRAG_REFRESH @"Force drag refresh"
#define SETTINGS_KEYBOARD_ENABLED @"Keyboard enabled"

#define SETTINGS_EXCLUDED_APPS @"Excluded apps"

#define SETTINGS_ENABLED_DEFAULT (NO)
#define SETTINGS_ACCELERATION_CURVE_DEFAULT @"Linear"
#define SETTINGS_VELOCITY_DEFAULT (1.0)
#define SETTINGS_DRIVER_DEFAULT (2) // IOHID
#define SETTINGS_FORCE_DRAG_REFRESH_DEFAULT (NO)

#define KEY_SELECTED_TAB @"SelectedTab"

#define SETTINGS_CURVE_OFF @"Off"
#define SETTINGS_CURVE_WINDOWS @"Windows"
#define SETTINGS_CURVE_OSX @"OS X"
