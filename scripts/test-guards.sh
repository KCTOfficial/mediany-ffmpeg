#!/usr/bin/env bash
# Proves the release guards reject what they must: check-license.sh fails on a GPL, nonfree,
# or (L)GPLv3 configuration, and check-alignment.sh fails on 4 KB-aligned ELF files. Each
# guard must also pass a compliant input, so a guard that always fails is caught too.
#
# The config.h fixtures use the exact lines FFmpeg's configure writes for each license.
#
# Usage: scripts/test-guards.sh
# Requires: ANDROID_NDK_HOME (llvm-readelf, clang).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0

# expect <pass|fail> <description> <command...>
expect() {
  local want="$1" what="$2"; shift 2
  if "$@" >"$WORK/out.txt" 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    echo "ok    $what ($got)"
  else
    echo "WRONG $what: expected $want, got $got" >&2
    sed 's/^/      /' "$WORK/out.txt" >&2
    failures=$((failures + 1))
  fi
}

# config_h <file> <gpl> <nonfree> <version3> <license>
config_h() {
  printf '#define CONFIG_GPL %s\n#define CONFIG_NONFREE %s\n#define CONFIG_VERSION3 %s\n#define FFMPEG_LICENSE "%s"\n' \
    "$2" "$3" "$4" "$5" > "$1"
}

config_h "$WORK/lgpl.h" 0 0 0 "LGPL version 2.1 or later"
config_h "$WORK/gpl.h" 1 0 0 "GPL version 2 or later"
config_h "$WORK/nonfree.h" 0 1 0 "nonfree and unredistributable"
config_h "$WORK/lgpl3.h" 0 0 1 "LGPL version 3 or later"
config_h "$WORK/gpl3.h" 1 0 1 "GPL version 3 or later"

expect pass "license: LGPL v2.1+" bash "$ROOT/scripts/check-license.sh" "$WORK/lgpl.h"
expect fail "license: --enable-gpl" bash "$ROOT/scripts/check-license.sh" "$WORK/gpl.h"
expect fail "license: --enable-nonfree" bash "$ROOT/scripts/check-license.sh" "$WORK/nonfree.h"
expect fail "license: --enable-version3" bash "$ROOT/scripts/check-license.sh" "$WORK/lgpl3.h"
expect fail "license: --enable-gpl --enable-version3" \
  bash "$ROOT/scripts/check-license.sh" "$WORK/gpl3.h"

CC="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android26-clang"
echo 'int mediany_guard_test(void) { return 0; }' > "$WORK/lib.c"
for page in 4096 16384; do
  mkdir -p "$WORK/align-$page/lib"
  "$CC" -shared -fPIC -Wl,-z,max-page-size=$page -o "$WORK/align-$page/lib/libtest.so" "$WORK/lib.c"
done

expect pass "alignment: 16 KB" bash "$ROOT/scripts/check-alignment.sh" "$WORK/align-16384"
expect fail "alignment: 4 KB" bash "$ROOT/scripts/check-alignment.sh" "$WORK/align-4096"
mkdir -p "$WORK/empty"
expect fail "alignment: no ELF files" bash "$ROOT/scripts/check-alignment.sh" "$WORK/empty"

if (( failures > 0 )); then
  echo "Guard self-test FAILED: $failures case(s)" >&2
  exit 1
fi
echo "Guard self-test passed"
