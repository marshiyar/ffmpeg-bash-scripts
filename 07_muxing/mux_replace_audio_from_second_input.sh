#!/usr/bin/env bash
# Replace video input audio with audio from a second input.
# Usage: ./mux_replace_audio_from_second_input.sh <video_input> <audio_input> [output]
# Env: MUX_SHORTEST=1|0 (default 1), AUDIO_CODEC=aac, AUDIO_BITRATE=192k
set -euo pipefail

script_name="$(basename "$0")"

video_input="${1:-}"
audio_input="${2:-}"
output="${3:-}"

if [[ -z "$video_input" || -z "$audio_input" ]]; then
  echo "Usage: ${script_name} <video_input> <audio_input> [output]"
  exit 1
fi

if [[ -z "$output" ]]; then
  ext="${video_input##*.}"
  output="${video_input%.*}_audio_replaced.${ext}"
fi

audio_codec="${AUDIO_CODEC:-aac}"
audio_bitrate="${AUDIO_BITRATE:-192k}"
shortest="${MUX_SHORTEST:-1}"
shortest_args=()
if [[ "$shortest" == "1" ]]; then
  shortest_args+=( -shortest )
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$video_input" -i "$audio_input" \
  -map 0:v:0 -map 1:a:0 -map 0:s? \
  -c:v copy -c:s copy -c:a "$audio_codec" -b:a "$audio_bitrate" \
  "${shortest_args[@]}" \
  "$output"
