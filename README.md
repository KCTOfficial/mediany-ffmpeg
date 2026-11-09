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
| Linking | Shared libraries (`lib*.so`), 16 KB page aligned |
| Hardware codecs | Android MediaCodec (`--enable-jni --enable-mediacodec`) |
| Network | Disabled (`--disable-network`) |

The full configure command is in `scripts/build-ffmpeg.sh`.

## Building

Builds run on GitHub Actions (`.github/workflows/build.yml`). Each run:

1. Downloads the pinned FFmpeg tarball and verifies its SHA-256.
2. Cross-compiles FFmpeg for each ABI with the pinned NDK.
3. Fails unless the configuration is LGPL v2.1+ (`scripts/check-license.sh`).
4. Fails unless every ELF file is 16 KB aligned (`scripts/check-alignment.sh`).
5. Publishes the libraries, headers, and a size report as workflow artifacts.

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
bash scripts/build-ffmpeg.sh arm64-v8a
bash scripts/check-license.sh out/arm64-v8a/config.h
bash scripts/check-alignment.sh out/arm64-v8a
```

## Modifications to FFmpeg

None yet. Any patch applied to the FFmpeg source will be listed here and kept in `patches/`.
