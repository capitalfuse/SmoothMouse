#!/bin/sh

# Usage:
# 1) Build packages for archiving (important!)
# 2) Place them in this directory under Root/
# 3) Run this script. Optionally specify the certificate name as an argument.

PACKAGE_NAME="SmoothMouse"
IDENTIFIER="com.cyberic"

if [ ! -d "Components" ] 
then
    mkdir -p "Components"
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
    "$PACKAGE_NAME $VERSION (unsigned).pkg"

# Signing and zip-archiving
if [[ -z "$1" ]]
then
    echo "Not signing the package because certificate was not specified"
    zip -r "$PACKAGE_NAME $VERSION (unsigned).zip" "$PACKAGE_NAME $VERSION (unsigned).pkg" 
else
    productsign --sign "Developer ID Installer: $1" "$PACKAGE_NAME $VERSION (unsigned).pkg" "$PACKAGE_NAME $VERSION.pkg"
    rm -rf "$PACKAGE_NAME $VERSION (unsigned).pkg"
    zip -r "$PACKAGE_NAME $VERSION.zip" "$PACKAGE_NAME $VERSION.pkg"
fi