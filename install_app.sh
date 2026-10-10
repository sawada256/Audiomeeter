#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$TASK_ROOT"
if pgrep -x Audiomeeter >/dev/null; then
    echo 'Quit Audiomeeter before installing an update.' >&2
    exit 1
fi
./build_app.sh
TASK_TARGET=/Applications/Audiomeeter.app
TASK_STAGE=/Applications/Audiomeeter.update.app
TASK_BACKUP="$TASK_ROOT/.build/installation-backup/$(date +%Y%m%d-%H%M%S)-app"
mkdir -p "$TASK_BACKUP"
ditto Audiomeeter.app "$TASK_STAGE"
codesign --verify --deep --strict "$TASK_STAGE"
if [ -d "$TASK_TARGET" ]; then mv "$TASK_TARGET" "$TASK_BACKUP/Audiomeeter.app"; fi
if ! mv "$TASK_STAGE" "$TASK_TARGET"; then
    if [ -d "$TASK_BACKUP/Audiomeeter.app" ]; then mv "$TASK_BACKUP/Audiomeeter.app" "$TASK_TARGET"; fi
    exit 1
fi
printf 'Installed %s. Previous app backup: %s\n' "$TASK_TARGET" "$TASK_BACKUP"
