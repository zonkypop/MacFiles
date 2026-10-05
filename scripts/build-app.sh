#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/MintFiles.app"
mkdir -p "$ROOT/.build/module-cache" "$APP/Contents/MacOS"
swiftc -target "$(uname -m)-apple-macosx13.0" -swift-version 5 -module-cache-path "$ROOT/.build/module-cache" "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/MintFiles"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MintFiles</string>
<key>CFBundleIdentifier</key><string>local.mintfiles.app</string>
<key>CFBundleName</key><string>MintFiles</string>
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
