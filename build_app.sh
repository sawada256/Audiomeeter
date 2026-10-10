#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "Building Audiomeeter (Release ARM64)..."
"$DIR/build_plugin_host.sh"
swift build -c release

APP_NAME="Audiomeeter.app"
APP_DIR="$DIR/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Packaging $APP_NAME..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$CONTENTS_DIR/Frameworks"
cp "$DIR/Assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$DIR/.build/plugin-host/libVMPluginHost.dylib" "$CONTENTS_DIR/Frameworks/"

cp -R "$DIR/LICENSES" "$RESOURCES_DIR/LICENSES"
cp "$DIR/THIRD_PARTY_NOTICES.md" "$RESOURCES_DIR/THIRD_PARTY_NOTICES.md"
python3 "$DIR/Tools/collect_dependency_notices.py" "$DIR/.build/dependencies/JUCE" "$RESOURCES_DIR/LICENSES/JUCE-dependencies"
WORKER_CONTENTS="$CONTENTS_DIR/Helpers/VMPluginWorker.app/Contents"
mkdir -p "$WORKER_CONTENTS/MacOS"
cp "$DIR/.build/plugin-host/VMPluginWorker" "$WORKER_CONTENTS/MacOS/VMPluginWorker"
cat << 'WORKER_EOF' > "$WORKER_CONTENTS/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VMPluginWorker</string>
<key>CFBundleIdentifier</key><string>local.audiomeeter.pluginworker</string>
<key>CFBundleName</key><string>Audiomeeter Plugin</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
WORKER_EOF
cp "$DIR/.build/release/Audiomeeter" "$MACOS_DIR/Audiomeeter"

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ja</string>
    <key>CFBundleExecutable</key>
    <string>Audiomeeter</string>
    <key>CFBundleIdentifier</key>
    <string>local.audiomeeter</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Audiomeeter</string>
    <key>CFBundleDisplayName</key>
    <string>Audiomeeter</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>2</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleLocalizations</key>
    <array><string>ja</string><string>en</string></array>
    <key>NSMicrophoneUsageDescription</key>
    <string>Audiomeeter requires microphone access to route audio streams.</string>
</dict>
</plist>
EOF

# A certificate-backed identity keeps the designated requirement stable across
# updates, so macOS privacy permissions can follow subsequent builds.
VM_SIGNING_IDENTITY="${VM_CODESIGN_IDENTITY:-}"
if [ -z "$VM_SIGNING_IDENTITY" ]; then
    VM_SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk '/"Apple Development:/{print $2; exit}')"
fi
if [ -n "$VM_SIGNING_IDENTITY" ]; then
    codesign --force --deep --sign "$VM_SIGNING_IDENTITY" "$APP_DIR"
else
    echo "No development signing identity found; ad-hoc updates may require privacy permissions to be renewed."
    codesign --force --deep --sign - "$APP_DIR"
fi

echo "Successfully built and packaged: $APP_DIR"
echo "You can launch it directly with: open \"$APP_DIR\""
