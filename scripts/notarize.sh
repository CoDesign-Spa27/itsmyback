#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SIGNING_IDENTITY:?Set SIGNING_IDENTITY to your Developer ID Application identity}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile}"
xcodebuild -project PostureBuddy.xcodeproj -scheme PostureBuddy -configuration Release -derivedDataPath build \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS=--timestamp build
app="$PWD/build/Build/Products/Release/ItsMyBack.app"
codesign --verify --deep --strict "$app"
mkdir -p build/distribution
ditto -c -k --keepParent "$app" build/distribution/ItsMyBack-notarization.zip
xcrun notarytool submit build/distribution/ItsMyBack-notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
ditto -c -k --keepParent "$app" build/distribution/ItsMyBack.zip
printf '\nNotarized archive: %s/build/distribution/ItsMyBack.zip\n' "$PWD"
