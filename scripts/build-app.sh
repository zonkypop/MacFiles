#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Files.app"
mkdir -p "$ROOT/.build/module-cache" "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/Files"
ICONSET="$ROOT/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Files</string>
<key>CFBundleIdentifier</key><string>local.mintfiles.app</string>
<key>CFBundleName</key><string>Files</string>
<key>CFBundleDisplayName</key><string>Files</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSDesktopFolderUsageDescription</key><string>Browse and manage the files you select on your Desktop.</string>
<key>NSDocumentsFolderUsageDescription</key><string>Browse and manage the files you select in Documents.</string>
<key>NSDownloadsFolderUsageDescription</key><string>Browse and manage the files you select in Downloads.</string>
<key>NSRemovableVolumesUsageDescription</key><string>Browse and manage files on connected drives.</string>
<key>NSNetworkVolumesUsageDescription</key><string>Browse and manage files on mounted network drives.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
printf 'Built %s\n' "$APP"
