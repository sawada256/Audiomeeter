#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
if [ "$(id -u)" != 0 ]; then exec sudo /bin/bash "$0"; fi
TASK_PRODUCTS="$TASK_ROOT/.build/drivers"
TASK_HAL=/Library/Audio/Plug-Ins/HAL
TASK_BACKUP="$TASK_ROOT/.build/installation-backup/$(date +%Y%m%d-%H%M%S)-HAL"
TASK_NAMES=(Voicemeeter VoicemeeterAUX VoicemeeterB1 VoicemeeterB2)
for TASK_NAME in "${TASK_NAMES[@]}"; do
    test -d "$TASK_PRODUCTS/$TASK_NAME.driver"
    /usr/bin/codesign --verify --deep --strict "$TASK_PRODUCTS/$TASK_NAME.driver"
done
mkdir -p "$TASK_BACKUP"
rollback() {
    for TASK_NAME in "${TASK_NAMES[@]}"; do
        if [ -d "$TASK_BACKUP/$TASK_NAME.driver" ]; then
            rm -rf "$TASK_HAL/$TASK_NAME.driver"
            /usr/bin/ditto "$TASK_BACKUP/$TASK_NAME.driver" "$TASK_HAL/$TASK_NAME.driver"
        fi
        rm -rf "$TASK_HAL/.$TASK_NAME.update.driver"
    done
    /usr/bin/killall coreaudiod || true
}
trap rollback ERR
for TASK_NAME in "${TASK_NAMES[@]}"; do
    if [ -d "$TASK_HAL/$TASK_NAME.driver" ]; then
        /usr/bin/ditto "$TASK_HAL/$TASK_NAME.driver" "$TASK_BACKUP/$TASK_NAME.driver"
    fi
    /usr/bin/ditto "$TASK_PRODUCTS/$TASK_NAME.driver" "$TASK_HAL/.$TASK_NAME.update.driver"
    chown -R root:wheel "$TASK_HAL/.$TASK_NAME.update.driver"
done
for TASK_NAME in "${TASK_NAMES[@]}"; do
    rm -rf "$TASK_HAL/$TASK_NAME.driver"
    mv "$TASK_HAL/.$TASK_NAME.update.driver" "$TASK_HAL/$TASK_NAME.driver"
done
/usr/bin/killall coreaudiod || true
trap - ERR
printf 'Updated all four drivers. Backup: %s\n' "$TASK_BACKUP"
