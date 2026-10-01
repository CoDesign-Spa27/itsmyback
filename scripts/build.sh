#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project PostureBuddy.xcodeproj -scheme PostureBuddy -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build
printf '\nBuilt: %s/build/Build/Products/Release/ItsMyBack.app\n' "$PWD"
