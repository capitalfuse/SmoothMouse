#!/bin/sh

# Usage:
# 1) Build packages for archiving (important!)
# 2) Place them in this directory under Root/
# 3) Run this script. Optionally specify the certificate name as an argument.

PACKAGE_NAME="SmoothMouse"
IDENTIFIER="com.cyberic"
WELCOME="Resources/Welcome.rtf"

mkdir -p "Components"

VERSION=$(defaults read "$(pwd)/Root/SmoothMouse.prefPane/Contents/Info" CFBundleVersion)

# Patch Welcome.rtf to include version number
if [ -f $WELCOME ]
then
	sed -i .tpl "s/%VERSION%/$VERSION/g" "$WELCOME"
fi

# Parameters: file name, internal name, identifier, install location
c_pkgbuild () {
    C_VERSION=$(defaults read "$(pwd)/Root/$1/Contents/Info" CFBundleVersion)
    
    echo "\nBuilding a component package: 
    file name: $1
    internal name: $2
    identifier: $IDENTIFIER.pkg.$3
    install location: $4
    version: $C_VERSION\n"
    
    pkgbuild \
        --identifier "$IDENTIFIER.pkg.$3" \
        --component "Root/$1" \
        --scripts "Scripts/$2/" \
        --install-location "$4" \
        --version "$C_VERSION" \
        "Components/$2.pkg"
}

c_pkgbuild "SmoothMouse.kext" "Kext" "SmoothMouseKext" "/System/Library/Extensions/"
c_pkgbuild "SmoothMouse.prefPane" "PrefPane" "SmoothMousePrefPane" "/Library/PreferencePanes/"

productbuild \
    --distribution "Distribution.xml" \
    --package-path "Components/" \
    --resources "Resources/" \
    "$PACKAGE_NAME (unsigned).pkg"

# Put back Welcome.rtf after patching
if [ -f $WELCOME ]
then
	mv "$WELCOME.tpl" "$WELCOME"
fi

# Signing and zip-archiving
if [[ -z "$1" ]]
then
    echo "Not signing the package because certificate was not specified"
    zip -r "$PACKAGE_NAME $VERSION (unsigned).zip" "$PACKAGE_NAME (unsigned).pkg" 
else
    productsign --sign "Developer ID Installer: $1" "$PACKAGE_NAME (unsigned).pkg" "$PACKAGE_NAME.pkg"
    rm -rf "$PACKAGE_NAME (unsigned).pkg"
    zip -r "$PACKAGE_NAME $VERSION.zip" "$PACKAGE_NAME.pkg"
fi
