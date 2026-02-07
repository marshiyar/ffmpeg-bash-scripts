#!/usr/bin/env bash
# Mux video, external audio, and SRT subtitle into one MP4.
# Usage: ./mux_video_audio_subtitle_mp4.sh <video_input> <audio_input> <subtitle.srt> [output.mp4]
# Env: AUDIO_CODEC=aac, AUDIO_BITRATE=192k, MUX_SHORTEST=1|0 (default 1)
set -euo pipefail

script_name="$(basename "$0")"

video_input="${1:-}"
audio_input="${2:-}"
subtitle_input="${3:-}"
output="${4:-}"

if [[ -z "$video_input" || -z "$audio_input" || -z "$subtitle_input" ]]; then
  echo "Usage: ${script_name} <video_input> <audio_input> <subtitle.srt> [output.mp4]"
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${video_input%.*}_muxed.mp4"
fi

audio_codec="${AUDIO_CODEC:-aac}"
audio_bitrate="${AUDIO_BITRATE:-192k}"
shortest="${MUX_SHORTEST:-1}"
shortest_args=()
if [[ "$shortest" == "1" ]]; then
  shortest_args+=( -shortest )
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$video_input" -i "$audio_input" -i "$subtitle_input" \
  -map 0:v:0 -map 1:a:0 -map 2:0 \
  -c:v copy -c:a "$audio_codec" -b:a "$audio_bitrate" -c:s mov_text \
  "${shortest_args[@]}" \
  "$output"
