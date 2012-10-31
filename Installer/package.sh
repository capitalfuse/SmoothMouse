#!/bin/sh
# Usage:
# 1) Build packages for archiving (important!)
# 2) Place them in this directory under Root/
# 3) Run this script

PACKAGE_NAME="SmoothMouse"
IDENTIFIER="com.cyberic"

if [ ! -d "Components" ] 
then
    mkdir -p "Components"
fi

# Parameters: file name, internal name, identifier, install location 
c_pkgbuild () {    
    if [ -f "Root/$1" ]; then  
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
    fi
}

c_pkgbuild "SmoothMouse.kext" "Kext" "SmoothMouseKext" "/System/Library/Extensions/"
c_pkgbuild "SmoothMouse.prefPane" "PrefPane" "SmoothMousePrefPane" "/Library/PreferencePanes/"

productbuild \
    --distribution "Distribution.xml" \
    --package-path "Components/" \
    --resources "Resources/" \
    "$PACKAGE_NAME.pkg"

zip -r "$PACKAGE_NAME.zip" "$PACKAGE_NAME.pkg"