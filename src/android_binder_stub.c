// SPDX-License-Identifier: LGPL-2.1-or-later
/*
 * Replaces FFmpeg's compat/android/binder.c in libmediany_ffmpeg.so.
 *
 * fftools/ffmpeg.c calls android_binder_threadpool_init_if_required() so that the ffmpeg
 * command-line program, which has no binder thread pool, can use MediaCodec on Android 15+.
 * The upstream helper also calls ABinderProcess_setThreadPoolMaxThreadCount(1). Mediany runs
 * ffmpeg inside an app process, whose binder thread pool is already running, and there that
 * call aborts the process ("Binder threadpool cannot be shrunk after starting"). An app
 * process needs no setup, so this replacement does nothing.
 */
void android_binder_threadpool_init_if_required(void);

void android_binder_threadpool_init_if_required(void) {}
