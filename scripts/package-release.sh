#!/usr/bin/env bash
# Packages the CI build outputs into GitHub release assets.
#
# Usage: scripts/package-release.sh <tag>
# Expects workflow artifacts in artifacts/ffmpeg-<version>-<abi>/ (lib/, bin/, include/, config.h).
# Writes the assets to dist/ and the release notes to RELEASE_NOTES.md.
set -euo pipefail

TAG="${1:?usage: package-release.sh <tag>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"

ABIS=(arm64-v8a x86_64)
ARTIFACTS="$ROOT/artifacts"
DIST="$ROOT/dist"
NAME="ffmpeg-${FFMPEG_VERSION}-android"

artifact_dir() { echo "$ARTIFACTS/ffmpeg-${FFMPEG_VERSION}-$1"; }

rm -rf "$DIST"
mkdir -p "$DIST"

# 1. Shared libraries (+ ffmpeg/ffprobe for on-device smoke tests) per ABI.
for abi in "${ABIS[@]}"; do
  dir="$(artifact_dir "$abi")"
  [[ -d "$dir/lib" && -f "$dir/config.h" ]] || { echo "Missing build output: $dir" >&2; exit 1; }
  chmod +x "$dir"/bin/*  # upload-artifact does not preserve file modes
  tar -C "$dir" -czf "$DIST/${NAME}-${abi}.tar.gz" lib bin config.h
done

# 2. C headers. They are ABI-independent; fail if that ever stops being true.
diff -r "$(artifact_dir "${ABIS[0]}")/include" "$(artifact_dir "${ABIS[1]}")/include"
tar -C "$(artifact_dir "${ABIS[0]}")" -czf "$DIST/${NAME}-headers.tar.gz" include

# 3. Exact FFmpeg source used by this build (LGPL source offer).
curl -fsSL --retry 3 -o "$DIST/ffmpeg-${FFMPEG_VERSION}.tar.xz" \
  "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
echo "$FFMPEG_SHA256  $DIST/ffmpeg-${FFMPEG_VERSION}.tar.xz" | sha256sum -c -

# 4. Build scripts at this tag.
git -C "$ROOT" archive --format=tar.gz --prefix="mediany-ffmpeg-${TAG}/" \
  -o "$DIST/mediany-ffmpeg-${TAG}-build-scripts.tar.gz" HEAD

# 5. Component manifest, read by the app's open-source licenses screen.
cat > "$DIST/components.json" <<EOF
{
  "build": "${TAG}",
  "components": [
    {
      "name": "FFmpeg",
      "version": "${FFMPEG_VERSION}",
      "license": "LGPL-2.1-or-later",
      "url": "https://ffmpeg.org",
      "source": "https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"
    }
  ]
}
EOF

(cd "$DIST" && sha256sum -- * > SHA256SUMS)

cat > "$ROOT/RELEASE_NOTES.md" <<EOF
FFmpeg ${FFMPEG_VERSION} built for Android (${ABIS[*]}), NDK ${NDK_VERSION}, API ${ANDROID_API}.

- License: LGPL version 2.1 or later (no GPL, nonfree, or version3 components).
- Shared libraries, 16 KB page aligned. Network support disabled.
- \`ffmpeg-${FFMPEG_VERSION}.tar.xz\` is the exact, checksum-verified FFmpeg source used.
- \`mediany-ffmpeg-${TAG}-build-scripts.tar.gz\` contains the build scripts and configuration.
- Verify downloads with \`SHA256SUMS\`.
EOF

ls -l "$DIST"
