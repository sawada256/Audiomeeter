#!/bin/bash
set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

echo "=========================================================="
echo "  Audiomeeter for Mac - Virtual Audio Driver Setup"
echo "=========================================================="
echo ""
echo "This installer builds four stereo loopback devices with per-application trim support."
echo "  Playback: Audiomeeter (VAIO), Audiomeeter AUX"
echo "  Virtual microphones: Audiomeeter B1, Audiomeeter B2"
echo ""
echo "Cleaning up previous drivers and compiling..."

# Compile before touching installed drivers. Build products never require sudo.
./Drivers/build_all_drivers.sh

"$DIR/install_built_drivers.sh"

echo ""
echo "=========================================================="
echo "  Installation Successful!"
echo "  All 4 clean Audiomeeter devices are active in macOS:"
echo "   - Audiomeeter     (Playback: VAIO strip)"
echo "   - Audiomeeter AUX (Playback: AUX strip)"
echo "   - Audiomeeter B1  (Record: Bus B1 / Virtual Mic)"
echo "   - Audiomeeter B2  (Record: Bus B2 / Secondary Out)"
echo "=========================================================="
