#!/bin/bash
# SPDX-License-Identifier: AGPL-3.0-only
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
exec python3 "$TASK_ROOT/Tools/build_installers.py" "$@"
