#!/usr/bin/env bash
# Fails unless the FFmpeg build configuration is LGPL v2.1 or later:
# no GPL, no nonfree, no (L)GPLv3 upgrade.
#
# Usage: scripts/check-license.sh <path/to/config.h>
set -euo pipefail

CONFIG_H="${1:?usage: check-license.sh <path/to/config.h>}"
status=0

require_line() {
  if ! grep -qxF "$1" "$CONFIG_H"; then
    echo "LICENSE CHECK FAILED: expected '$1' in $CONFIG_H" >&2
    status=1
  fi
}

require_line '#define CONFIG_GPL 0'
require_line '#define CONFIG_NONFREE 0'
require_line '#define CONFIG_VERSION3 0'
require_line '#define FFMPEG_LICENSE "LGPL version 2.1 or later"'

if [[ $status -eq 0 ]]; then
  echo "License check passed: LGPL version 2.1 or later"
fi
exit $status
