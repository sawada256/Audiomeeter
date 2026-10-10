#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=========================================================="
echo "  Voicemeeter Banana for Mac - Virtual Audio Driver Setup"
echo "=========================================================="
echo ""
echo "This installer builds four stereo loopback devices with per-application trim support."
echo "  Playback: Voicemeeter (VAIO), Voicemeeter AUX"
echo "  Virtual microphones: Voicemeeter B1, Voicemeeter B2"
echo ""
echo "Cleaning up previous drivers and compiling..."

# Compile before touching installed drivers. Build products never require sudo.
./Drivers/build_all_drivers.sh

"$DIR/install_built_drivers.sh"

echo ""
echo "=========================================================="
echo "  Installation Successful!"
echo "  All 4 clean Voicemeeter devices are active in macOS:"
echo "   - Voicemeeter     (Playback: VAIO strip)"
echo "   - Voicemeeter AUX (Playback: AUX strip)"
echo "   - Voicemeeter B1  (Record: Bus B1 / Virtual Mic)"
echo "   - Voicemeeter B2  (Record: Bus B2 / Secondary Out)"
echo "=========================================================="
