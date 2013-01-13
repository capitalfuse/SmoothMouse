#!/bin/sh

# Usage:
# 1) Build packages for archiving (important!)
# 2) Place them in this directory under Root/
# 3) Run this script
# Optionally, you may specify the version number for the entire package as the first argument.
# Otherwise the script will use the version of PrefPane instead.

PACKAGE_NAME="SmoothMouse"
IDENTIFIER="com.cyberic"

if [ ! -d "Components" ] 
then
    mkdir -p "Components"
fi

# Use version number from args if specified
if [[ -z "$1" ]]
then
    VERSION=$(defaults read "$(pwd)/Root/SmoothMouse.prefPane/Contents/Info" CFBundleVersion)
else
    VERSION=$1
fi

# Parameters: file name, internal name, identifier, install location
c_pkgbuild () {
    VERSION=$(defaults read "$(pwd)/Root/$1/Contents/Info" CFBundleVersion)
    
    echo "\nBuilding a component package: 
    file name: $1
    internal name: $2
    identifier: $IDENTIFIER.$3
    install location: $4
    version: $VERSION\n"
    
    pkgbuild \
        --identifier "$IDENTIFIER.$3" \
        --component "Root/$1" \
        --scripts "Scripts/$2/" \
        --install-location "$4" \
        --version "$VERSION" \
        "Components/$2.pkg"
}

c_pkgbuild "SmoothMouse.kext" "Kext" "SmoothMouseKext" "/System/Library/Extensions/"
c_pkgbuild "SmoothMouse.prefPane" "PrefPane" "SmoothMousePrefPane" "/Library/PreferencePanes/"

productbuild \
    --distribution "Distribution.xml" \
    --package-path "Components/" \
    --resources "Resources/" \
    "$PACKAGE_NAME $VERSION.pkg"

zip -r "$PACKAGE_NAME $VERSION.zip" "$PACKAGE_NAME $VERSION.pkg"