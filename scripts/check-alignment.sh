#!/usr/bin/env bash
# Fails unless every ELF file under the given directory has all LOAD segments
# aligned to at least 16 KB (0x4000), as required for 16 KB page-size devices.
#
# Usage: scripts/check-alignment.sh <install-prefix>
# Requires: ANDROID_NDK_HOME (for llvm-readelf).
set -euo pipefail

DIR="${1:?usage: check-alignment.sh <install-prefix>}"
READELF="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"
MIN_ALIGN=$((0x4000))
status=0
checked=0

while IFS= read -r -d '' file; do
  # Skip non-ELF files (headers, pkg-config files, config.h).
  [[ "$(head -c 4 "$file" | od -An -c | tr -d ' \n')" == "177ELF" ]] || continue
  checked=$((checked + 1))
  # The last column of a LOAD row is its alignment as a hex literal (e.g. 0x4000).
  while read -r align_hex; do
    if (( align_hex < MIN_ALIGN )); then
      echo "ALIGNMENT CHECK FAILED: $file has LOAD alignment $align_hex" >&2
      status=1
    fi
  done < <("$READELF" -lW "$file" | awk '$1 == "LOAD" { print $NF }')
done < <(find "$DIR" -type f \( -name '*.so' -o -path '*/bin/*' \) -print0)

if (( checked == 0 )); then
  echo "ALIGNMENT CHECK FAILED: no ELF files found under $DIR" >&2
  exit 1
fi
if (( status == 0 )); then
  echo "Alignment check passed: $checked ELF files aligned to >= 16 KB"
fi
exit $status
