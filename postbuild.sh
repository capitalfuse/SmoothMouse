INSTALLER_ROOT="${PROJECT_DIR}/Installer/Root"

PREFPANE="SmoothMouse.prefPane"
PREFPANE_PLIST="${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/Info.plist"

KEXT="SmoothMouse.kext"
KEXT_PLIST="${INSTALLER_ROOT}/${KEXT}/Contents/Info.plist"

# Auxiliary stuff
# -----------------------------------------------------------------------
finalize_plist () {
	plutil -convert xml1 "$1"
	chmod 755 "$1"
}

# If INSTALLER_ROOT does not exist, it would be necessary to make it
if [ ! -d "$INSTALLER_ROOT" ]; then
	echo "Making INSTALLER_ROOT"
	mkdir -p "$INSTALLER_ROOT"
fi

# Preparation
# -----------------------------------------------------------------------
set -o errexit # exit shell when a command exits with non-zero status
set -o nounset # indicate an error when trying to use an undefined variable

# Logic
# -----------------------------------------------------------------------
# Merge the daemon and updater with the prefpane
echo "Merging the daemon and updater with the prefpane"
rm -rf "${BUILT_PRODUCTS_DIR}/SmoothMouse.prefPane/Contents/SmoothMouseUpdater.app"
rm -rf "${BUILT_PRODUCTS_DIR}/SmoothMouse.prefPane/Contents/SmoothMouseDaemon.app"
mv "${BUILT_PRODUCTS_DIR}/SmoothMouseUpdater.app" "${BUILT_PRODUCTS_DIR}/SmoothMouse.prefPane/Contents/"
mv "${BUILT_PRODUCTS_DIR}/SmoothMouseDaemon.app" "${BUILT_PRODUCTS_DIR}/SmoothMouse.prefPane/Contents/"
chmod ug+x "${BUILT_PRODUCTS_DIR}/SmoothMouse.prefPane/Contents/Resources/uninstall.sh"

# Add commit ID to the plist
SMCOMMITID=`git log --pretty=format:'%h' -n 1`
echo "Updating the plist with the commit ID"
defaults write "$PREFPANE_PLIST" SMCommitID "$SMCOMMITID"

# Assemble version strings
LAST_TAG=$(git tag | sort -r | head -1)
COMMITS_SINCE_LAST_TAG=$(git rev-list ${LAST_TAG}..HEAD | wc | grep -o "\d\+" | head -1)
CFBUNDLEVERSION=$(git tag | wc | grep -o "\d\+" | head -1)
CFBUNDLESHORTVERSIONSTRING=$LAST_TAG

if [[ $COMMITS_SINCE_LAST_TAG -ne "0" ]]; then
	CFBUNDLEVERSION="${CFBUNDLEVERSION}.${COMMITS_SINCE_LAST_TAG}"
	CFBUNDLESHORTVERSIONSTRING="${CFBUNDLESHORTVERSIONSTRING}.${COMMITS_SINCE_LAST_TAG}"
fi

if git diff-index --quiet HEAD --; then
	echo "Tree not dirty";
else
	echo "Tree dirty";
	CFBUNDLESHORTVERSIONSTRING="${CFBUNDLESHORTVERSIONSTRING}-dirty"
fi

# Write version strings to the prefpane plist
echo "PREFPANE_PLIST: ${PREFPANE_PLIST}"
echo "LAST_TAG: ${LAST_TAG}"
echo "COMMITS_SINCE_LAST_TAG: ${COMMITS_SINCE_LAST_TAG}"
echo "CFBUNDLEVERSION: ${CFBUNDLEVERSION}"
echo "CFBUNDLESHORTVERSIONSTRING: ${CFBUNDLESHORTVERSIONSTRING}"
defaults write "$PREFPANE_PLIST" CFBundleVersion "$CFBUNDLEVERSION"
defaults write "$PREFPANE_PLIST" CFBundleShortVersionString "$CFBUNDLESHORTVERSIONSTRING"
finalize_plist "$PREFPANE_PLIST"

# Copy the prefpane into the installer root
BUILT_PREFPANE="${BUILT_PRODUCTS_DIR}/${PREFPANE}"
ROOT_PREFPANE="${INSTALLER_ROOT}/${PREFPANE}"

if [ -d "$ROOT_PREFPANE" ]; then
	echo "Deleting existing prefpane"
	rm -r "$ROOT_PREFPANE"
fi

echo "Copying the prefpane into the installer root"
cp -R "$BUILT_PREFPANE" "$INSTALLER_ROOT"

# Build the kext if the project exists
if [ $CONFIGURATION == "Release" ] && [ -d "Kext/SmoothMouseKext.xcodeproj" ]; then
	echo "Building the kext"
	xcodebuild -project "Kext/SmoothMouseKext.xcodeproj" | head -1 # remove this for debugging
fi

if [ -f "$KEXT_PLIST" ]; then
	# Write version strings to the kext
	echo "Writing CFBundleVersion ${CFBUNDLEVERSION} to the kext"
	defaults write "$KEXT_PLIST" CFBundleVersion "$CFBUNDLEVERSION"
	echo "Writing CFBundleShortVersionString ${CFBUNDLESHORTVERSIONSTRING} to the kext"
	defaults write "$KEXT_PLIST" CFBundleShortVersionString "$CFBUNDLESHORTVERSIONSTRING"
	finalize_plist "$KEXT_PLIST"

	# Build an installer
	if [ $CONFIGURATION == "Release" ]; then
		echo "Invoking the installer build script"
		if [[ "$SM_CERTIFICATE_IDENTITY" ]]; then
			echo "SM_CERTIFICATE_IDENTITY: ${SM_CERTIFICATE_IDENTITY}"
			"${INSTALLER_ROOT}/../package.py" -c "$SM_CERTIFICATE_IDENTITY" --reveal
		else
			"${INSTALLER_ROOT}/../package.py" --reveal
		fi
	fi
fi