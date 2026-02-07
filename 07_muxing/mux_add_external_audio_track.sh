#!/usr/bin/env bash
# Add an external audio track while keeping existing streams.
# Usage: ./mux_add_external_audio_track.sh <video_input> <audio_input> [output]
# Env: AUDIO_CODEC=aac, AUDIO_BITRATE=192k
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
  output="${video_input%.*}_with_extra_audio.${ext}"
fi

audio_codec="${AUDIO_CODEC:-aac}"
audio_bitrate="${AUDIO_BITRATE:-192k}"

ffmpeg -hide_banner -nostdin -y \
  -i "$video_input" -i "$audio_input" \
  -map 0 -map 1:a:0 \
  -c:v copy -c:s copy -c:a "$audio_codec" -b:a "$audio_bitrate" \
  "$output"
