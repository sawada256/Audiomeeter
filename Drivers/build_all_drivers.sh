#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_DIR="${VM_DRIVER_OUTPUT_DIR:-$DIR/../.build/drivers}"
mkdir -p "$OUTPUT_DIR"
cd "$OUTPUT_DIR"

echo "Building Audiomeeter Virtual Audio Drivers for macOS..."

SDK_PATH="$(xcrun --show-sdk-path)"

build_driver() {
    local BUNDLE_NAME="$1"
    local DRIVER_NAME="$2"
    local DEVICE_NAME="$3"
    local BUNDLE_ID="$4"
    local CHANNELS="$5"
    local DUPLEX="${6:-0}"
    local FACTORY_ID
    case "$DRIVER_NAME" in
        Audiomeeter) FACTORY_ID=3A38E842-3447-4944-9FC9-FEB812FEE231 ;;
        AudiomeeterAUX) FACTORY_ID=B5C8057E-5127-4D84-B70A-45372D02928C ;;
        AudiomeeterB1) FACTORY_ID=878BF115-78EA-44DD-8D88-9FDF4DB4DB89 ;;
        AudiomeeterB2) FACTORY_ID=A687868C-7BEA-4C5C-8A83-C7232B3A14D8 ;;
        *) echo "Unknown driver: $DRIVER_NAME" >&2; return 1 ;;
    esac

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
    <string>1.0.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFPlugInFactories</key>
    <dict>
        <key>$FACTORY_ID</key>
        <string>BlackHole_Create</string>
    </dict>
    <key>CFPlugInTypes</key>
    <dict>
        <key>443ABAB8-E7B3-491A-B985-BEB9187030DB</key>
        <array>
            <string>$FACTORY_ID</string>
        </array>
    </dict>
</dict>
</plist>
EOF

    mkdir -p "$BUNDLE_NAME/Contents/Resources"
    cp "$DIR/../LICENSES/BlackHole-GPL-3.0.txt" "$BUNDLE_NAME/Contents/Resources/LICENSE.txt"
    codesign --force --deep --sign - "$BUNDLE_NAME"
    echo "Successfully built $BUNDLE_NAME"
}

# 1. Virtual Input 1: Audiomeeter (VAIO Playback -> Strip 4 VAIO)
build_driver "Audiomeeter.driver" "Audiomeeter" "Audiomeeter" "local.audiomeeter" 2 1

# 2. Virtual Input 2: Audiomeeter AUX (AUX Playback -> Strip 5 AUX)
build_driver "AudiomeeterAUX.driver" "AudiomeeterAUX" "Audiomeeter AUX" "local.audiomeeter.aux" 2 1

# 3. Virtual Output 1: Audiomeeter B1 (Master Bus B1 -> Virtual Mic / Discord / DAW In)
build_driver "AudiomeeterB1.driver" "AudiomeeterB1" "Audiomeeter B1" "local.audiomeeter.b1" 2

# 4. Virtual Output 2: Audiomeeter B2 (Master Bus B2 -> Secondary Out / DAW In)
build_driver "AudiomeeterB2.driver" "AudiomeeterB2" "Audiomeeter B2" "local.audiomeeter.b2" 2

echo "All 4 Audiomeeter Audio Drivers built successfully!"
