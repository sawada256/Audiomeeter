#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${VM_DRIVER_OUTPUT_DIR:-$DIR/../.build/drivers}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "Building Voicemeeter Virtual Audio Drivers for macOS..."

SDK_PATH="$(xcrun --show-sdk-path)"

build_driver() {
    local BUNDLE_NAME="$1"
    local DRIVER_NAME="$2"
    local DEVICE_NAME="$3"
    local BUNDLE_ID="$4"
    local CHANNELS="$5"
    local DUPLEX="${6:-0}"

    echo "Compiling $BUNDLE_NAME ($DEVICE_NAME)..."
    rm -rf "$BUNDLE_NAME"
    mkdir -p "$BUNDLE_NAME/Contents/MacOS"

    clang -bundle -arch arm64 \
        -isysroot "$SDK_PATH" \
        -framework CoreAudio -framework CoreFoundation -framework Accelerate \
        -DkDriver_Name="\"$DRIVER_NAME\"" \
        -DkDevice_Name="\"$DEVICE_NAME\"" \
        -DkHas_Driver_Name_Format=false \
        -DkPlugIn_BundleID="\"$BUNDLE_ID\"" \
        -DkNumber_Of_Channels=$CHANNELS \
        -DVM_DAW_DUPLEX=$DUPLEX \
        -O2 -Wno-format-extra-args \
        "$DIR/BlackHoleCore.c" -o "$BUNDLE_NAME/Contents/MacOS/$DRIVER_NAME"

    cat << EOF > "$BUNDLE_NAME/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$DRIVER_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$DRIVER_NAME</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.2.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFPlugInFactories</key>
    <dict>
        <key>D1350F65-A1F3-4FA4-887F-70190B9FB3D7</key>
        <string>BlackHole_Create</string>
    </dict>
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array>
            <string>D1350F65-A1F3-4FA4-887F-70190B9FB3D7</string>
        </array>
    </dict>
</dict>
</plist>
EOF

    codesign --force --deep --sign - "$BUNDLE_NAME"
    echo "Successfully built $BUNDLE_NAME"
}

# 1. Virtual Input 1: Voicemeeter (VAIO Playback -> Strip 4 VAIO)
build_driver "Voicemeeter.driver" "Voicemeeter" "Voicemeeter" "com.antigravity.voicemeeter" 2 1

# 2. Virtual Input 2: Voicemeeter AUX (AUX Playback -> Strip 5 AUX)
build_driver "VoicemeeterAUX.driver" "VoicemeeterAUX" "Voicemeeter AUX" "com.antigravity.voicemeeter.aux" 2 1

# 3. Virtual Output 1: Voicemeeter B1 (Master Bus B1 -> Virtual Mic / Discord / DAW In)
build_driver "VoicemeeterB1.driver" "VoicemeeterB1" "Voicemeeter B1" "com.antigravity.voicemeeter.b1" 2

# 4. Virtual Output 2: Voicemeeter B2 (Master Bus B2 -> Secondary Out / DAW In)
build_driver "VoicemeeterB2.driver" "VoicemeeterB2" "Voicemeeter B2" "com.antigravity.voicemeeter.b2" 2

echo "All 4 Voicemeeter Audio Drivers built successfully!"
