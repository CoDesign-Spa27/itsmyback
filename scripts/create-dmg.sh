#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

app="$PWD/build/Build/Products/Release/ItsMyBack.app"
output="$PWD/build/distribution/ItsMyBack.dmg"
staging="$PWD/build/dmg-staging"
read_write="$PWD/build/distribution/ItsMyBack-rw.dmg"
temporary_output="$PWD/build/distribution/ItsMyBack-new.dmg"
volume_name="ItsMyBack Setup"

if [[ ! -d "$app" ]]; then
  echo "Release app not found. Run ./scripts/build.sh first."
  exit 1
fi

rm -rf "$staging" "$read_write" "$temporary_output"
mkdir -p "$staging/.background" "$PWD/build/distribution"
device=""
cleanup() {
  if [[ -n "$device" ]]; then hdiutil detach "$device" -quiet >/dev/null 2>&1 || true; fi
  rm -rf "$staging" "$read_write" "$temporary_output"
}
trap cleanup EXIT
cp -R "$app" "$staging/"
cp "$PWD/Resources/dmg-background.png" "$staging/.background/ItsMyBack-installer.png"
ln -s /Applications "$staging/Applications"

# Create a writable image first so Finder can save the custom window layout.
hdiutil create \
  -volname "$volume_name" \
  -fs HFS+ \
  -srcfolder "$staging" \
  -ov \
  -format UDRW \
  "$read_write" >/dev/null

attach_output=$(hdiutil attach "$read_write" -nobrowse)
device=$(printf '%s\n' "$attach_output" | awk '/\/Volumes\// {print $1; exit}')
mount_point=$(printf '%s\n' "$attach_output" | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | head -1)
if [[ -z "$device" || -z "$mount_point" ]]; then
  echo "Could not determine the mounted DMG device."
  exit 1
fi
osascript <<APPLESCRIPT
tell application "Finder"
  set installerDisk to (POSIX file "$mount_point" as alias)
  open installerDisk
  delay 2
  set theWindow to container window of installerDisk
  set current view of theWindow to icon view
  set bounds of theWindow to {50, 50, 1714, 838}

  set viewOptions to icon view options of theWindow
  set arrangement of viewOptions to not arranged
  set icon size of viewOptions to 104
  set text size of viewOptions to 13
  set background picture of viewOptions to (POSIX file "$mount_point/.background/ItsMyBack-installer.png" as alias)

  set position of item "ItsMyBack.app" of installerDisk to {460, 410}
  set position of item "Applications" of installerDisk to {1204, 410}
  update installerDisk without registering applications
  delay 2
end tell
APPLESCRIPT

hdiutil detach "$device" -quiet
device=""

# Compress the configured image for distribution.
hdiutil convert "$read_write" -format UDZO -imagekey zlib-level=9 -ov -o "$temporary_output" >/dev/null
mv "$temporary_output" "$output"

echo "Created: $output"
