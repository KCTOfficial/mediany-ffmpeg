# mediany-ffmpeg

Build scripts for the FFmpeg libraries shipped in the Mediany Android app.

This repository exists so that the exact FFmpeg source and build configuration used
by Mediany are publicly available, as required by the GNU Lesser General Public
License (LGPL) v2.1. Mediany uses code of FFmpeg licensed under the LGPLv2.1.

## What gets built

| Item | Value |
|---|---|
| FFmpeg | 8.1.3 (see `versions.env`; tarball checksum pinned, signature verified against the FFmpeg release signing key) |
| License | LGPL version 2.1 or later. GPL, nonfree, and version3 components are never enabled, and CI fails if they are. |
| ABIs | `arm64-v8a`, `x86_64` |
| Android | NDK r28c (28.2.13676358), API level 26 |
| Linking | Shared libraries (`lib*.so`), 16 KB page aligned, symbol tables kept |
| Components | `--disable-everything`, then only the allowlist in `scripts/components.sh` |
| I/O | Protocols `fd` and `pipe` only. Network disabled (`--disable-network`) |
| Hardware codecs | Android MediaCodec (`--enable-jni --enable-mediacodec`) |

### External codec libraries

Built by `scripts/build-deps.sh` as static, position-independent libraries and linked into
the FFmpeg shared libraries. Versions and checksums are pinned in `versions.env`.

| Library | Used for | License |
|---|---|---|
| LAME | MP3 encoding | LGPL-2.0-or-later |
| libogg, libvorbis | Vorbis encoding | BSD-3-Clause |
| Opus | Opus encoding | BSD-3-Clause |
| libvpx | VP8/VP9 encoding | BSD-3-Clause |
| dav1d | AV1 decoding | BSD-2-Clause |
| libaom | AV1 and AVIF encoding | BSD-2-Clause |
| libwebp | WebP encoding | BSD-3-Clause |
| SoX Resampler (soxr) | High-quality audio resampling | LGPL-2.1-or-later |

### Command-line tools as libraries

`scripts/link-fftools.sh` links the unmodified `ffmpeg` and `ffprobe` tools into
`libmediany_ffmpeg.so` and `libmediany_ffprobe.so`, exporting only
`mediany_ffmpeg_main` and `mediany_ffprobe_main` (the tools' `main`, renamed with
`objcopy`). The tools keep global state, so an app must run at most one invocation per
process.

One FFmpeg object is replaced: `compat/android/binder.o` becomes
`src/android_binder_stub.c`, a no-op. The upstream helper prepares a binder thread pool for
the command-line `ffmpeg` on Android 15+, and inside an app process (which already has one)
its `ABinderProcess_setThreadPoolMaxThreadCount` call aborts the process.

The full configure command is in `scripts/build-ffmpeg.sh`.

## Building

Builds run on GitHub Actions (`.github/workflows/build.yml`). Each run:

1. Builds the codec libraries (cached until `versions.env` or `build-deps.sh` changes).
2. Downloads the pinned FFmpeg tarball and verifies its SHA-256.
3. Cross-compiles FFmpeg for each ABI with the pinned NDK and links the tool libraries.
4. Fails unless the configuration is LGPL v2.1+ (`scripts/check-license.sh`).
5. Fails unless every ELF file is 16 KB aligned (`scripts/check-alignment.sh`).
6. Publishes the libraries, headers, and a size report as workflow artifacts.

A separate job (`scripts/test-guards.sh`) proves both checks work: they must reject GPL,
nonfree, and v3 configurations and 4 KB-aligned libraries, and accept compliant ones. Releases
need it to pass.

## Releases

Pushing a tag `v<FFmpeg version>-<build number>` (for example `v8.1.3-1`) builds and publishes
a GitHub release with:

| Asset | Contents |
|---|---|
| `ffmpeg-<version>-android-<abi>.tar.gz` | Shared libraries (`lib/`), `ffmpeg`/`ffprobe` for on-device tests (`bin/`), `config.h` |
| `ffmpeg-<version>-android-headers.tar.gz` | C headers (`include/`) |
| `ffmpeg-<version>.tar.xz` | The exact FFmpeg source used |
| `mediany-ffmpeg-<tag>-build-scripts.tar.gz` | This repository at the tag |
| `components.json` | Component names, versions, and licenses |
| `SHA256SUMS` | Checksums of all assets |

To build locally on Linux (x86_64):

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r28c
bash scripts/build-deps.sh arm64-v8a
bash scripts/build-ffmpeg.sh arm64-v8a
bash scripts/check-license.sh out/arm64-v8a/config.h
bash scripts/check-alignment.sh out/arm64-v8a
```

## Modifications to FFmpeg

None. The FFmpeg source is used unmodified; the tool libraries only rename `main` in the
compiled object files. Any future patch will be listed here and kept in `patches/`.
