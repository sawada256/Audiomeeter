#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$TASK_ROOT"
mkdir -p .build/audio-tests
if [ ! -d .build/dependencies/JUCE ]; then ./build_plugin_host.sh; fi
swift build > .build/audio-tests/build.log 2>&1
swiftc Sources/Localization/*.swift Tests/LocalizationTests.swift -o .build/audio-tests/localization
.build/audio-tests/localization
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift Sources/State/DesktopControlsPreferences.swift Tests/DesktopControlsTests.swift -o .build/audio-tests/desktop-controls
.build/audio-tests/desktop-controls
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift Sources/State/DesktopControlsPreferences.swift Sources/State/MediaKeyCapture.swift Tests/MediaCaptureLifecycleTests.swift -o .build/audio-tests/media-capture
.build/audio-tests/media-capture
MODULE_MAP="$TASK_ROOT/.build/arm64-apple-macosx/debug/VMNative.build/module.modulemap"
clang -c Native/Realtime/VMNative.c -I Native/Realtime/include -o .build/audio-tests/native.o
clang -c Native/Realtime/PluginWorkerBridge.c -I Native/Realtime/include -o .build/audio-tests/worker.o
SWIFT_FLAGS=(.build/audio-tests/worker.o -Xcc "-fmodule-map-file=$MODULE_MAP" .build/audio-tests/native.o)
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/RingBuffer.swift Tests/PlaybackBufferTests.swift -o .build/audio-tests/playback
.build/audio-tests/playback
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift -O "${SWIFT_FLAGS[@]}" Sources/AudioEngine/RingBuffer.swift Sources/AudioEngine/Resampler.swift Tests/LongRunClockDriftTests.swift -o .build/audio-tests/drift
.build/audio-tests/drift
cmake -S Native/PluginHost -B .build/plugin-host -DJUCE_SOURCE="$TASK_ROOT/.build/dependencies/JUCE" -DCMAKE_BUILD_TYPE=Release -DVM_BUILD_TEST_PLUGIN=ON > .build/audio-tests/plugin-build.log 2>&1
cmake --build .build/plugin-host --parallel 4 >> .build/audio-tests/plugin-build.log 2>&1
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/AudioTypes.swift Sources/AudioEngine/RingBuffer.swift Sources/AudioEngine/AudioBufferIO.swift Sources/AudioEngine/DSPProcessor.swift Sources/AudioEngine/Resampler.swift Sources/AudioEngine/AudioRecorderPlayer.swift Tests/AudioRegressionTests.swift -o .build/audio-tests/regression
.build/audio-tests/regression "$TASK_ROOT/.build/audio-tests" "$TASK_ROOT/.build/plugin-host"
swiftc Sources/Localization/*.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/AudioTypes.swift Sources/AudioEngine/RingBuffer.swift Sources/AudioEngine/AudioRecorderPlayer.swift Tests/RecorderLifecycleTests.swift -o .build/audio-tests/recorder-lifecycle
.build/audio-tests/recorder-lifecycle

clang -O2 -Wno-format-extra-args -framework CoreAudio -framework CoreFoundation -framework Accelerate Tests/DriverTrimTests.c -o .build/audio-tests/driver-trim
.build/audio-tests/driver-trim

# The HAL integration test is opt-in because it needs the revised installed driver.
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/AppTrimTransport.swift Tests/AppTrimHALTests.swift -o .build/audio-tests/hal-trim
if [ "${VM_TEST_INSTALLED_HAL:-0}" = 1 ]; then .build/audio-tests/hal-trim; fi

clang -O2 -Wno-format-extra-args -framework CoreAudio -framework CoreFoundation -framework Accelerate Tests/DriverDuplexTests.c -o .build/audio-tests/driver-duplex
.build/audio-tests/driver-duplex
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/AudioTypes.swift Sources/AudioEngine/LatencyCompensation.swift Sources/AudioEngine/PluginInserts.swift Tests/PluginWorkerTests.swift -o .build/audio-tests/plugin-worker
.build/audio-tests/plugin-worker

ENGINE_TEST_SOURCES=(Sources/AudioEngine/AudioTypes.swift Sources/AudioEngine/RingBuffer.swift Sources/AudioEngine/Resampler.swift Sources/AudioEngine/AudioBufferIO.swift Sources/AudioEngine/AudioDeviceManager.swift Sources/AudioEngine/AudioDeviceIO.swift Sources/AudioEngine/DSPProcessor.swift Sources/AudioEngine/AudioRecorderPlayer.swift Sources/AudioEngine/DAWDuplexTransport.swift Sources/AudioEngine/LatencyCompensation.swift Sources/AudioEngine/PluginInserts.swift Sources/AudioEngine/SidechainRouting.swift Sources/AudioEngine/AudiomeeterEngine.swift)
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift -DVM_AUDIO_TESTS "${SWIFT_FLAGS[@]}" "${ENGINE_TEST_SOURCES[@]}" Tests/MixerLatencyTests.swift -o .build/audio-tests/mixer-latency
.build/audio-tests/mixer-latency
.build/audio-tests/mixer-latency --virtual
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift -DVM_AUDIO_TESTS "${SWIFT_FLAGS[@]}" "${ENGINE_TEST_SOURCES[@]}" Tests/BusRoutingTests.swift -o .build/audio-tests/bus-routing
.build/audio-tests/bus-routing
.build/audio-tests/bus-routing --b2
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift -DVM_AUDIO_TESTS "${SWIFT_FLAGS[@]}" "${ENGINE_TEST_SOURCES[@]}" Tests/SidechainRoutingTests.swift -o .build/audio-tests/sidechain-routing
.build/audio-tests/sidechain-routing
swiftc Sources/Localization/Localization.swift Sources/Localization/EnglishCatalog.swift Sources/Localization/JapaneseCatalog.swift "${SWIFT_FLAGS[@]}" Sources/AudioEngine/DAWDuplexTransport.swift Tests/DAWDuplexHALTests.swift -o .build/audio-tests/hal-duplex
if [ "${VM_TEST_DUPLEX_HAL:-0}" = 1 ]; then
    if pgrep -x Audiomeeter >/dev/null; then
        echo "Quit Audiomeeter before VM_TEST_DUPLEX_HAL=1: the test needs exclusive B1 return ownership." >&2
        exit 1
    fi
    .build/audio-tests/hal-duplex
    .build/audio-tests/hal-duplex AudiomeeterAUX_UID
fi
