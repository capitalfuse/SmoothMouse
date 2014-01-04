INSTALLER_ROOT="${PROJECT_DIR}/Installer/Root"

PREFPANE="SmoothMousePrefs.prefPane"
PREFPANE_PLIST="${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/Info.plist"

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
rm -rf "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/SmoothMouseUpdater.app"
rm -rf "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/SmoothMouseDaemon.app"
rm -rf "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/SmoothMouseFeedback.app"
rm -rf "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/SmoothMousePlayground.app"
mv "${BUILT_PRODUCTS_DIR}/SmoothMouseUpdater.app" "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/"
mv "${BUILT_PRODUCTS_DIR}/SmoothMouseDaemon.app" "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/"
mv "${BUILT_PRODUCTS_DIR}/SmoothMouseFeedback.app" "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/"
mv "${BUILT_PRODUCTS_DIR}/SmoothMousePlayground.app" "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/"
chmod ug+x "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/Resources/uninstall.sh"
chmod a+x  "${BUILT_PRODUCTS_DIR}/${PREFPANE}/Contents/SmoothMouseFeedback.app/Contents/Resources/FRFeedbackReporter.sh"

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
	export SMKEXTCFBUNDLEVERSION="$CFBUNDLEVERSION"
	export SMKEXTCFBUNDLESHORTVERSIONSTRING="$CFBUNDLESHORTVERSIONSTRING"
	xcodebuild -project "Kext/SmoothMouseKext.xcodeproj" | head -1 # remove this for debugging
	unset SMKEXTCFBUNDLEVERSION
	unset SMKEXTCFBUNDLESHORTVERSIONSTRING
	
	# Build an installer
	"${INSTALLER_ROOT}/../package.py" --reveal
fi