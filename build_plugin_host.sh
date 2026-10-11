#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
JUCE_DIR="$TASK_ROOT/.build/dependencies/JUCE"
if [ -f "$JUCE_DIR/.audiomeeter-source-revision" ]; then
    test "$(cat "$JUCE_DIR/.audiomeeter-source-revision")" = "29396c22c93392d6738e021b83196283d6e4d850" || exit 1
elif [ ! -d "$JUCE_DIR/.git" ]; then
    mkdir -p "$(dirname "$JUCE_DIR")"
    git clone --depth 1 --branch 8.0.12 https://github.com/juce-framework/JUCE.git "$JUCE_DIR"
fi
if [ -d "$JUCE_DIR/.git" ]; then
test "$(git -C "$JUCE_DIR" rev-parse HEAD)" = "29396c22c93392d6738e021b83196283d6e4d850" || { echo "Unexpected JUCE revision" >&2; exit 1; }
fi
cmake -S "$TASK_ROOT/Native/PluginHost" -B "$TASK_ROOT/.build/plugin-host" -DJUCE_SOURCE="$JUCE_DIR" -DCMAKE_BUILD_TYPE=Release -DVM_BUILD_TEST_PLUGIN=OFF
cmake --build "$TASK_ROOT/.build/plugin-host" --parallel 4
