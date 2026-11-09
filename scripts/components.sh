# FFmpeg components built for Mediany (sourced by build-ffmpeg.sh).
#
# The build starts from --disable-everything and enables only what Mediany uses. A format
# missing here cannot be read or written by the app, so additions must come with a test.
# shellcheck shell=bash

# I/O is always through file descriptors handed to the engine (fd:) and the progress
# pipe (pipe:). No file paths, no network, no playlists or concat.
FF_PROTOCOLS=(fd pipe)

FF_DEMUXERS=(
  mov matroska avi flv mpegts mpegps asf ogg wav aiff w64 caf
  mp3 aac flac ac3 eac3 dts truehd ape wv amr mpegvideo h264 hevc m4v
  srt ass webvtt
  image_png_pipe image_jpeg_pipe image_webp_pipe image_bmp_pipe image_tiff_pipe image_gif_pipe
  gif image2pipe
)

FF_MUXERS=(
  mp4 mov ipod matroska webm tgp
  mp3 adts flac wav ogg opus
  image2pipe gif webp apng avif
  srt ass webvtt
)

FF_DECODERS=(
  # Video
  h264 hevc mpeg4 mpeg2video mpeg1video h263 vp8 vp9 libdav1d theora
  msmpeg4v1 msmpeg4v2 msmpeg4v3 wmv1 wmv2 wmv3 vc1 flv mjpeg prores ffv1 dnxhd
  # Audio
  aac aac_latm mp1 mp2 mp3 mp3float flac alac vorbis opus ac3 eac3 dca truehd mlp
  wmav1 wmav2 wmapro wmalossless amrnb amrwb ape wavpack gsm
  pcm_s16le pcm_s16be pcm_s24le pcm_s24be pcm_s32le pcm_f32le pcm_f64le pcm_u8
  pcm_alaw pcm_mulaw adpcm_ms adpcm_ima_wav
  # Image
  png apng webp bmp tiff gif
  # Subtitles
  subrip srt ass ssa webvtt movtext dvdsub
)

FF_ENCODERS=(
  # Video: hardware first, software where no hardware path exists
  h264_mediacodec hevc_mediacodec av1_mediacodec mpeg4 libvpx_vp8 libvpx_vp9 libaom_av1
  # Audio
  aac libmp3lame libopus libvorbis flac alac pcm_s16le pcm_s24le
  # Image
  png mjpeg libwebp libwebp_anim bmp tiff gif apng
  # Subtitles
  subrip srt ass webvtt movtext
)

FF_PARSERS=(
  h264 hevc mpeg4video mpegvideo vp8 vp9 av1 vc1 h263
  aac aac_latm ac3 mpegaudio flac opus vorbis dca mlp
  png mjpeg gif webp bmp
)

FF_BSFS=(
  extract_extradata h264_mp4toannexb hevc_mp4toannexb aac_adtstoasc vp9_superframe
  h264_metadata hevc_metadata av1_metadata null
)

FF_FILTERS=(
  # Plumbing
  null anull copy format aformat setpts asetpts split asplit trim atrim fps
  # Video
  scale transpose hflip vflip crop pad rotate setsar setdar palettegen paletteuse color overlay
  # Audio
  aresample atempo volume loudnorm afade
)

# Prints --enable-<kind>=<name> for each entry of the array named by $2.
ff_enable_flags() {
  local kind="$1" array_name="$2[@]" name
  for name in "${!array_name}"; do
    printf -- '--enable-%s=%s\n' "$kind" "$name"
  done
}
