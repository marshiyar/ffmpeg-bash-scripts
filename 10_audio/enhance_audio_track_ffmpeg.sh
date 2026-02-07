#!/usr/bin/env bash
# Enhance audio in an audio file or video container using FFmpeg filter presets.
# Usage:
#   ./enhance_audio_track_ffmpeg.sh <input> [output] [profile] [audio_codec] [audio_quality]
#
# Profiles:
#   - subtle   : light cleanup and leveling
#   - balanced : practical default for mixed content
#   - voice    : speech-focused cleanup and intelligibility
#   - strong   : stronger denoise/compression and louder result
#
# Audio codec:
#   - auto (default): chosen from output extension
#   - aac | libopus | libmp3lame | flac | pcm_s24le | any ffmpeg audio encoder
#
# Audio quality:
#   - bitrate for lossy codecs (default 192k, or 160k for opus)
#   - ignored for lossless PCM/FLAC
#
# Env:
#   AUDIO_RATE=48000
#   AUDIO_CHANNELS=2
#   ENABLE_LOUDNORM=1        (set 0 to disable final loudness normalize)
#   TARGET_LUFS=-16
#   TARGET_LRA=11
#   TARGET_TP=-1.5
#   KEEP_SUBS=1              (copy subtitle streams when present)
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
profile="${3:-balanced}"
audio_codec="${4:-auto}"
audio_quality="${5:-}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [profile] [audio_codec] [audio_quality]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${input%.*}_audio_enhanced.${input##*.}"
fi

for tool in ffmpeg ffprobe; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool missing from PATH: $tool" >&2
    exit 2
  fi
done

has_audio="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$input" | head -n1 || true)"
if [[ -z "$has_audio" ]]; then
  echo "Error: input has no audio stream to enhance: $input" >&2
  exit 1
fi

has_video=0
if ffprobe -v error -select_streams v:0 -show_entries stream=index -of csv=p=0 "$input" >/dev/null 2>&1; then
  has_video=1
fi

audio_rate="${AUDIO_RATE:-48000}"
audio_channels="${AUDIO_CHANNELS:-2}"
enable_loudnorm="${ENABLE_LOUDNORM:-1}"
target_lufs="${TARGET_LUFS:--16}"
target_lra="${TARGET_LRA:-11}"
target_tp="${TARGET_TP:--1.5}"
keep_subs="${KEEP_SUBS:-1}"

denoise_expr=""
tone_expr=""
control_expr=""

case "$profile" in
  subtle)
    denoise_expr="highpass=f=35,lowpass=f=18000,afftdn=nr=6:nf=-48:tn=1"
    tone_expr="equalizer=f=3000:t=q:w=1.2:g=1.2"
    control_expr="acompressor=threshold=0.12:ratio=1.8:attack=20:release=220:makeup=1.12,alimiter=limit=0.97:attack=5:release=80"
    ;;
  balanced)
    denoise_expr="highpass=f=45,lowpass=f=16500,afftdn=nr=10:nf=-45:tn=1,deesser=i=0.22:m=0.5:f=0.5"
    tone_expr="equalizer=f=180:t=q:w=1.0:g=-1.0,equalizer=f=3200:t=q:w=1.0:g=2.2"
    control_expr="acompressor=threshold=0.10:ratio=2.4:attack=15:release=180:makeup=1.40,alimiter=limit=0.95:attack=4:release=60"
    ;;
  voice)
    denoise_expr="highpass=f=70,lowpass=f=9000,afftdn=nr=12:nf=-44:tn=1,deesser=i=0.30:m=0.5:f=0.5"
    tone_expr="equalizer=f=220:t=q:w=1.2:g=-2.0,equalizer=f=3500:t=q:w=1.0:g=3.2"
    control_expr="acompressor=threshold=0.09:ratio=3.0:attack=10:release=140:makeup=1.70,alimiter=limit=0.94:attack=3:release=55"
    ;;
  strong)
    denoise_expr="highpass=f=50,lowpass=f=15000,afftdn=nr=14:nf=-42:tn=1,deesser=i=0.30:m=0.55:f=0.52"
    tone_expr="equalizer=f=200:t=q:w=1.1:g=-1.5,equalizer=f=3400:t=q:w=0.9:g=3.0"
    control_expr="acompressor=threshold=0.085:ratio=3.4:attack=8:release=120:makeup=1.9,alimiter=limit=0.93:attack=3:release=50"
    ;;
  *)
    echo "Error: unsupported profile '${profile}'. Use: subtle|balanced|voice|strong" >&2
    exit 1
    ;;
esac

af_chain="${denoise_expr},${tone_expr},${control_expr}"
if [[ "$enable_loudnorm" == "1" ]]; then
  af_chain+=",loudnorm=I=${target_lufs}:LRA=${target_lra}:TP=${target_tp}"
fi

if [[ "$audio_codec" == "auto" ]]; then
  ext="${output##*.}"
  ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    wav) audio_codec="pcm_s24le" ;;
    flac) audio_codec="flac" ;;
    mp3) audio_codec="libmp3lame" ;;
    opus|ogg|webm) audio_codec="libopus" ;;
    *) audio_codec="aac" ;;
  esac
fi

if [[ -z "$audio_quality" ]]; then
  if [[ "$audio_codec" == "libopus" ]]; then
    audio_quality="160k"
  else
    audio_quality="192k"
  fi
fi

cmd=(ffmpeg -hide_banner -nostdin -y -i "$input")

if [[ "$has_video" == "1" ]]; then
  cmd+=( -map 0:v? -c:v copy )
fi
cmd+=( -map 0:a:0 -af "$af_chain" )

case "$audio_codec" in
  flac|pcm_s16le|pcm_s24le|pcm_s32le)
    cmd+=( -c:a "$audio_codec" )
    ;;
  *)
    cmd+=( -c:a "$audio_codec" -b:a "$audio_quality" -ar "$audio_rate" -ac "$audio_channels" )
    ;;
esac

if [[ "$keep_subs" == "1" ]]; then
  cmd+=( -map 0:s? -c:s copy )
fi

if [[ "$output" == *.mp4 || "$output" == *.m4a || "$output" == *.mov ]]; then
  cmd+=( -movflags +faststart )
fi
cmd+=( "$output" )

echo "Audio enhancement pipeline:"
echo "  Input    : $input"
echo "  Output   : $output"
echo "  Profile  : $profile"
echo "  Codec    : $audio_codec"
echo "  Quality  : $audio_quality"
echo "  Loudnorm : $enable_loudnorm (I=${target_lufs}, LRA=${target_lra}, TP=${target_tp})"
echo "  AF chain : $af_chain"

"${cmd[@]}"

echo "Done: $output"
