#!/usr/bin/env bash
# Links the ffmpeg and ffprobe command-line tools, as compiled by the FFmpeg build, into
# shared libraries that an app can call in-process:
#
#   libmediany_ffmpeg.so   exports  int mediany_ffmpeg_main(int argc, char **argv)
#   libmediany_ffprobe.so  exports  int mediany_ffprobe_main(int argc, char **argv)
#
# The FFmpeg sources are not modified: each tool's `main` symbol is renamed with objcopy,
# and a version script keeps every other symbol local, so the two tools (which share
# cmdutils) cannot interpose each other's globals. The tools keep global state, so the
# caller must run at most one invocation per process.
#
# Usage: scripts/link-fftools.sh <arm64-v8a|x86_64>   (run after build-ffmpeg.sh's make)
set -euo pipefail

ABI="${1:?usage: link-fftools.sh <arm64-v8a|x86_64>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../versions.env
source "$ROOT/versions.env"

case "$ABI" in
  arm64-v8a) TRIPLE=aarch64-linux-android ;;
  x86_64)    TRIPLE=x86_64-linux-android ;;
  *) echo "Unsupported ABI: $ABI" >&2; exit 1 ;;
esac

TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
CC="$TOOLCHAIN/bin/${TRIPLE}${ANDROID_API}-clang"
OBJCOPY="$TOOLCHAIN/bin/llvm-objcopy"
FFTOOLS="$ROOT/build/$ABI/ffmpeg/fftools"
PREFIX="$ROOT/out/$ABI"
WORK="$ROOT/build/$ABI/fftools-link"
rm -rf "$WORK"
mkdir -p "$WORK"

FFMPEG_LIBS=(-L"$PREFIX/lib" -lavfilter -lavformat -lavcodec -lswresample -lswscale -lavutil -lm)
LDFLAGS=(-shared -Wl,--no-undefined -Wl,-z,max-page-size=16384 -Wl,-z,relro -Wl,-z,now)

# link_tool <tool> <objects...>
link_tool() {
  local tool="$1"; shift
  local entry="mediany_${tool}_main"
  local main_obj="$WORK/${tool}_main.o"
  "$OBJCOPY" --redefine-sym "main=$entry" "$FFTOOLS/$tool.o" "$main_obj"
  printf '{\n  global: %s;\n  local: *;\n};\n' "$entry" > "$WORK/$tool.map"
  "$CC" "${LDFLAGS[@]}" -Wl,-soname,"libmediany_$tool.so" \
    -Wl,--version-script="$WORK/$tool.map" \
    -o "$PREFIX/lib/libmediany_$tool.so" "$main_obj" "$@" "${FFMPEG_LIBS[@]}"
  echo "Linked libmediany_$tool.so"
}

shopt -s nullglob
TEXTFORMAT=("$FFTOOLS"/textformat/*.o)
COMMON=("$FFTOOLS/cmdutils.o" "$FFTOOLS/opt_common.o")

# The ffmpeg tool also links the compat objects configure selected (fftools/Makefile:
# OBJS-ffmpeg += $(COMPAT_OBJS:%=compat/%)), e.g. android/binder.o when MediaCodec is on.
# In the app's engine process the binder thread pool already runs; starting it again is a
# no-op.
BUILD_DIR="$ROOT/build/$ABI/ffmpeg"
COMPAT=()
for obj in $(sed -n 's/^COMPAT_OBJS=//p' "$BUILD_DIR/ffbuild/config.mak"); do
  COMPAT+=("$BUILD_DIR/compat/$obj")
done

link_tool ffmpeg "${COMMON[@]}" "$FFTOOLS"/ffmpeg_*.o "$FFTOOLS/sync_queue.o" \
  "$FFTOOLS/thread_queue.o" "$FFTOOLS"/graph/*.o "$FFTOOLS"/resources/*.o "${TEXTFORMAT[@]}" \
  "${COMPAT[@]}"
link_tool ffprobe "${COMMON[@]}" "${TEXTFORMAT[@]}"
