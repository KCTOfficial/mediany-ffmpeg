#!/usr/bin/env bash
# Cross-compiles FFmpeg (LGPL v2.1+ only) as shared libraries for one Android ABI, with the
# external codec libraries from build-deps.sh linked in statically, and links the ffmpeg and
# ffprobe command-line tools as shared libraries (link-fftools.sh).
#
# Usage: scripts/build-ffmpeg.sh <arm64-v8a|x86_64>
# Requires: ANDROID_NDK_HOME pointing to the NDK pinned in versions.env, the dependencies
#           built by scripts/build-deps.sh, plus make, pkg-config, curl, sha256sum, tar,
#           and nasm (x86_64 only).
set -euo pipefail

ABI="${1:?usage: build-ffmpeg.sh <arm64-v8a|x86_64>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"
# shellcheck source=components.sh
source "$ROOT/scripts/components.sh"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to NDK ${NDK_VERSION}}"

case "$ABI" in
  arm64-v8a) ARCH=aarch64; CPU=armv8-a; TRIPLE=aarch64-linux-android; ASM_FLAGS=() ;;
  x86_64)    ARCH=x86_64;  CPU=x86-64;  TRIPLE=x86_64-linux-android;  ASM_FLAGS=(--x86asmexe=nasm) ;;
  *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
TARBALL="$ROOT/build/ffmpeg-$FFMPEG_VERSION.tar.xz"
SRC_DIR="$ROOT/build/src/ffmpeg-$FFMPEG_VERSION"
BUILD_DIR="$ROOT/build/$ABI/ffmpeg"
DEPS="$ROOT/build/$ABI/deps"
PREFIX="$ROOT/out/$ABI"

[[ -d "$DEPS/lib" ]] || { echo "Missing $DEPS; run scripts/build-deps.sh $ABI first" >&2; exit 1; }

fetch_source() {
  mkdir -p "$ROOT/build/src"
  if [[ ! -f "$TARBALL" ]]; then
    curl -fsSL --retry 3 -o "$TARBALL" "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
  fi
  # Integrity: the tarball must match the pinned, signature-verified checksum.
  echo "$FFMPEG_SHA256  $TARBALL" | sha256sum -c -
  if [[ ! -d "$SRC_DIR" ]]; then
    tar -xf "$TARBALL" -C "$ROOT/build/src"
  fi
}

configure_ffmpeg() {
  rm -rf "$BUILD_DIR" "$PREFIX"
  mkdir -p "$BUILD_DIR"
  cd "$BUILD_DIR"

  local components=()
  mapfile -t components < <(
    ff_enable_flags protocol FF_PROTOCOLS
    ff_enable_flags demuxer FF_DEMUXERS
    ff_enable_flags muxer FF_MUXERS
    ff_enable_flags decoder FF_DECODERS
    ff_enable_flags encoder FF_ENCODERS
    ff_enable_flags parser FF_PARSERS
    ff_enable_flags bsf FF_BSFS
    ff_enable_flags filter FF_FILTERS
  )

  # Notes:
  # - --enable-gpl / --enable-nonfree / --enable-version3 are never passed (LGPL v2.1+).
  # - --disable-everything, then only the allowlisted components (components.sh).
  # - --disable-autodetect keeps host/system libraries from leaking in; the few we
  #   need (pthreads for MediaCodec, zlib for PNG) are enabled explicitly.
  # - External libraries are found through pkg-config in the deps prefix only.
  # - target-os=android already installs plain lib*.so names with matching SONAMEs.
  PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig:$DEPS/share/pkgconfig" PKG_CONFIG_PATH="" \
  "$SRC_DIR/configure" \
    --prefix="$PREFIX" \
    --target-os=android \
    --arch="$ARCH" \
    --cpu="$CPU" \
    --enable-cross-compile \
    --sysroot="$TOOLCHAIN/sysroot" \
    --cc="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang" \
    --cxx="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang++" \
    --ar="$TOOLCHAIN/bin/llvm-ar" \
    --nm="$TOOLCHAIN/bin/llvm-nm" \
    --ranlib="$TOOLCHAIN/bin/llvm-ranlib" \
    --strip="$TOOLCHAIN/bin/llvm-strip" \
    --pkg-config=pkg-config \
    --pkg-config-flags=--static \
    "${ASM_FLAGS[@]}" \
    --enable-pic \
    --enable-shared \
    --disable-static \
    --disable-doc \
    --disable-debug \
    --disable-network \
    --disable-autodetect \
    --disable-avdevice \
    --disable-ffplay \
    --disable-everything \
    --enable-ffmpeg \
    --enable-ffprobe \
    --enable-avcodec \
    --enable-avformat \
    --enable-avfilter \
    --enable-swresample \
    --enable-swscale \
    --enable-pthreads \
    --enable-zlib \
    --enable-jni \
    --enable-mediacodec \
    --enable-libmp3lame \
    --enable-libopus \
    --enable-libvorbis \
    --enable-libvpx \
    --enable-libdav1d \
    --enable-libaom \
    --enable-libwebp \
    --enable-libsoxr \
    "${components[@]}" \
    --extra-cflags="-O2 -fstack-protector-strong -D_FORTIFY_SOURCE=2 -I$DEPS/include" \
    --extra-ldflags="-L$DEPS/lib -Wl,-z,max-page-size=16384 -Wl,-z,relro -Wl,-z,now" \
    --extra-libs="-lm"
}

build_and_install() {
  make -C "$BUILD_DIR" -j"$(nproc)"
  make -C "$BUILD_DIR" install
  # Shared libraries keep their symbol tables: the app build strips them for the APK and
  # uploads the symbols with the App Bundle, so native crashes can be symbolicated.
  find "$PREFIX/bin" -maxdepth 1 -type f -exec "$TOOLCHAIN/bin/llvm-strip" --strip-unneeded {} +
  cp "$BUILD_DIR/config.h" "$PREFIX/config.h"
}

fetch_source
configure_ffmpeg
build_and_install
bash "$ROOT/scripts/link-fftools.sh" "$ABI"
echo "FFmpeg $FFMPEG_VERSION for $ABI installed to $PREFIX"
