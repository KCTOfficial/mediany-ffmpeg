#!/usr/bin/env bash
# Cross-compiles the external codec libraries as static, position-independent libraries
# for one Android ABI, installed into build/<abi>/deps. FFmpeg links them in statically.
#
# Usage: scripts/build-deps.sh <arm64-v8a|x86_64>
# Requires: ANDROID_NDK_HOME, cmake, ninja, meson, nasm, make, git, curl, sha256sum.
set -euo pipefail
# Make failures inside $(...) (such as fetch) stop the script too.
shopt -s inherit_errexit

ABI="${1:?usage: build-deps.sh <arm64-v8a|x86_64>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"
: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point to NDK ${NDK_VERSION}}"

case "$ABI" in
  arm64-v8a)
    TRIPLE=aarch64-linux-android; MESON_CPU_FAMILY=aarch64; MESON_CPU=armv8
    VPX_TARGET=arm64-android-gcc; AOM_CPU=arm64 ;;
  x86_64)
    TRIPLE=x86_64-linux-android; MESON_CPU_FAMILY=x86_64; MESON_CPU=x86_64
    VPX_TARGET=x86_64-android-gcc; AOM_CPU=x86_64 ;;
  *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
export CC="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang"
export CXX="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export NM="$TOOLCHAIN/bin/llvm-nm"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export CFLAGS="-O2 -fPIC -fstack-protector-strong -D_FORTIFY_SOURCE=2"
export CXXFLAGS="$CFLAGS"

DOWNLOADS="$ROOT/build/downloads"
WORK="$ROOT/build/$ABI/deps-src"
DEPS="$ROOT/build/$ABI/deps"
JOBS="$(nproc)"
mkdir -p "$DOWNLOADS" "$WORK" "$DEPS"

CMAKE_ANDROID=(
  -G Ninja
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
  -DANDROID_ABI="$ABI"
  -DANDROID_PLATFORM="android-$ANDROID_API"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$DEPS"
  -DCMAKE_PREFIX_PATH="$DEPS"
  # The NDK toolchain only searches its sysroot; also search the libraries built here.
  -DCMAKE_FIND_ROOT_PATH="$DEPS"
  -DCMAKE_INSTALL_LIBDIR=lib
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  # Some older projects (soxr) declare a CMake minimum that CMake 4 no longer accepts.
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

# Downloads a tarball once, verifies its pinned SHA-256, and extracts it into $WORK.
# Prints the extracted directory.
fetch() {
  local url="$1" sha="$2" file
  file="$DOWNLOADS/$(basename "$url")"
  if [[ ! -f "$file" ]]; then
    # Mirrors drop connections now and then; retry those too, and never keep a partial file.
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  echo "$sha  $file" | sha256sum -c - >&2
  # Extract into a fresh directory and return the archive's single top-level directory.
  local out
  out="$(mktemp -d -p "$WORK")"
  tar -xf "$file" -C "$out"
  local dirs=("$out"/*)
  [[ ${#dirs[@]} -eq 1 && -d "${dirs[0]}" ]] || { echo "Unexpected layout in $file" >&2; exit 1; }
  echo "${dirs[0]}"
}

cmake_install() {
  local src="$1"; shift
  cmake -S "$src" -B "$src/build-android" "${CMAKE_ANDROID[@]}" "$@"
  cmake --build "$src/build-android" -j "$JOBS"
  cmake --install "$src/build-android"
}

build_ogg() {
  local src
  src="$(fetch "https://downloads.xiph.org/releases/ogg/libogg-$OGG_VERSION.tar.xz" "$OGG_SHA256")"
  cmake_install "$src" -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF
}

build_vorbis() {
  local src
  src="$(fetch "https://downloads.xiph.org/releases/vorbis/libvorbis-$VORBIS_VERSION.tar.xz" "$VORBIS_SHA256")"
  cmake_install "$src" -DBUILD_TESTING=OFF     -DOGG_INCLUDE_DIR="$DEPS/include" -DOGG_LIBRARY="$DEPS/lib/libogg.a"
}

build_opus() {
  local src
  src="$(fetch "https://downloads.xiph.org/releases/opus/opus-$OPUS_VERSION.tar.gz" "$OPUS_SHA256")"
  cmake_install "$src" -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
}

build_lame() {
  local src
  src="$(fetch "https://downloads.sourceforge.net/project/lame/lame/$LAME_VERSION/lame-$LAME_VERSION.tar.gz" "$LAME_SHA256")"
  (
    cd "$src"
    ./configure --host="$TRIPLE" --prefix="$DEPS" --enable-static --disable-shared \
      --disable-frontend --disable-decoder --disable-gtktest --with-pic
    make -j "$JOBS"
    make install
  )
}

build_vpx() {
  local src="$WORK/libvpx"
  rm -rf "$src"
  git clone --quiet --depth 1 --branch "v$VPX_VERSION" \
    https://chromium.googlesource.com/webm/libvpx "$src"
  local head
  head="$(git -C "$src" rev-parse HEAD)"
  if [[ "$head" != "$VPX_COMMIT" ]]; then
    echo "libvpx v$VPX_VERSION is $head, expected $VPX_COMMIT" >&2
    exit 1
  fi
  local as_flags=()
  [[ "$ABI" == x86_64 ]] && as_flags=(--as=nasm)
  (
    cd "$src"
    LD="$CC" AS="${AS:-$CC}" ./configure --target="$VPX_TARGET" --prefix="$DEPS" \
      "${as_flags[@]}" --enable-pic --enable-static --disable-shared \
      --enable-vp8 --enable-vp9 --disable-examples --disable-tools --disable-docs \
      --disable-unit-tests --disable-webm-io --disable-libyuv
    make -j "$JOBS"
    make install
  )
}

build_dav1d() {
  local src
  src="$(fetch "https://downloads.videolan.org/pub/videolan/dav1d/$DAV1D_VERSION/dav1d-$DAV1D_VERSION.tar.xz" "$DAV1D_SHA256")"
  local cross="$src/android-cross.txt"
  cat > "$cross" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
nasm = 'nasm'

[host_machine]
system = 'android'
cpu_family = '$MESON_CPU_FAMILY'
cpu = '$MESON_CPU'
endian = 'little'
EOF
  meson setup "$src/build-android" "$src" --cross-file "$cross" --prefix "$DEPS" --libdir lib \
    --buildtype release --default-library static -Db_staticpic=true \
    -Denable_tools=false -Denable_tests=false
  ninja -C "$src/build-android" install
}

build_aom() {
  local src
  src="$(fetch "https://storage.googleapis.com/aom-releases/libaom-$AOM_VERSION.tar.gz" "$AOM_SHA256")"
  # Decoding AV1 is done by dav1d; libaom is only the (software) AV1/AVIF encoder.
  cmake_install "$src" -DAOM_TARGET_CPU="$AOM_CPU" -DCONFIG_AV1_DECODER=0 \
    -DENABLE_DOCS=0 -DENABLE_EXAMPLES=0 -DENABLE_TESTS=0 -DENABLE_TESTDATA=0 -DENABLE_TOOLS=0
}

build_webp() {
  local src
  src="$(fetch "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$WEBP_VERSION.tar.gz" "$WEBP_SHA256")"
  cmake_install "$src" -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
    -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
    -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF \
    -DWEBP_BUILD_LIBWEBPMUX=ON
}

build_soxr() {
  local src
  src="$(fetch "https://downloads.sourceforge.net/project/soxr/soxr-$SOXR_VERSION-Source.tar.xz" "$SOXR_SHA256")"
  cmake_install "$src" -DBUILD_TESTS=OFF -DBUILD_EXAMPLES=OFF -DWITH_OPENMP=OFF \
    -DWITH_LSR_BINDINGS=OFF -DWITH_CR32S=ON -DWITH_CR64S=ON
}

build_ogg
build_vorbis
build_opus
build_lame
build_vpx
build_dav1d
build_aom
build_webp
build_soxr
echo "Codec libraries for $ABI installed to $DEPS"
ls -l "$DEPS/lib"
