#!/bin/bash
# Build 影之刃零补丁.app (Apple silicon, macOS 26+) around ../pbz-crossover-patch, and zip it.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH="$HERE/../patch"
APP="$HERE/影之刃零补丁.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/PBZPatch" "$HERE/PBZPatch.swift" "$HERE/Strings.swift"
ditto --norsrc --noextattr "$PATCH" "$APP/Contents/Resources/patch"
cp "$HERE/donate-alipay.png" "$APP/Contents/Resources/donate-alipay.png"
cp "$HERE/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
ditto "$HERE/art" "$APP/Contents/Resources/art"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>PBZPatch</string>
    <key>CFBundleIdentifier</key><string>local.pbzpatch.app</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleName</key><string>影之刃零补丁</string>
    <key>CFBundleDisplayName</key><string>影之刃零补丁</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSArchitecturePriority</key><array><string>arm64</string></array>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF
codesign --force --deep -s - "$APP"
cd "$HERE" && rm -f 影之刃零补丁.zip && ditto -c -k --norsrc --noextattr --keepParent "影之刃零补丁.app" 影之刃零补丁.zip
ls -la "$HERE/影之刃零补丁.zip"
