PREFPANE="SmoothMouse.prefPane"
PREFPANE_PLIST="${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/Info.plist"
INSTALLER_ROOT="${PROJECT_DIR}/Installer/Root"
KEXT_PLIST="${INSTALLER_ROOT}/SmoothMouse.kext/Contents/Info.plist"

# Auxiliary functions
# -----------------------------------------------------------------------
finalize_plist () {
	plutil -convert xml1 "$1"
	chmod 755 "$1"
}

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
echo "Updating the plist with the commit ID"
SMCOMMITID=`git log --pretty=format:'%h' -n 1`
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

echo "PREFPANE_PLIST: ${PREFPANE_PLIST}"
echo "LAST_TAG: ${LAST_TAG}"
echo "COMMITS_SINCE_LAST_TAG: ${COMMITS_SINCE_LAST_TAG}"
echo "CFBUNDLEVERSION: ${CFBUNDLEVERSION}"
echo "CFBUNDLESHORTVERSIONSTRING: ${CFBUNDLESHORTVERSIONSTRING}"
defaults write "$PREFPANE_PLIST" CFBundleVersion "$CFBUNDLEVERSION"
defaults write "$PREFPANE_PLIST" CFBundleShortVersionString "$CFBUNDLESHORTVERSIONSTRING"
finalize_plist "$PREFPANE_PLIST"

# Copy the prefpane into the installer root
echo "Copying the prefpane into the installer root"
BUILT_PREFPANE="${BUILT_PRODUCTS_DIR}/${PREFPANE}"
ROOT_PREFPANE="${INSTALLER_ROOT}/${PREFPANE}"
if [ -d "$ROOT_PREFPANE" ]; then
	echo "Deleting existing prefpane"
	rm -r "$ROOT_PREFPANE"
fi
cp -R "$BUILT_PREFPANE" "$INSTALLER_ROOT"

if [ $CONFIGURATION == "Release" ]; then
	xcodebuild -project "Kext/SmoothMouseKext.xcodeproj"
fi

if [ -f "$KEXT_PLIST" ]; then
	# Copy version strings to the kext
	echo "Copying CFBundleVersion ${CFBUNDLEVERSION} to the kext"
	echo "Copying CFBundleShortVersionString ${CFBUNDLESHORTVERSIONSTRING} to the kext"
	defaults write "$KEXT_PLIST" CFBundleVersion "$CFBUNDLEVERSION"
	defaults write "$KEXT_PLIST" CFBundleShortVersionString "$CFBUNDLESHORTVERSIONSTRING"
	finalize_plist "$KEXT_PLIST"

	echo "Invoking the installer build script"
	"${INSTALLER_ROOT}/../package.py"
fi