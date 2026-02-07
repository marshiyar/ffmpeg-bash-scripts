#!/usr/bin/env bash
# Add an SRT subtitle track to MP4 as mov_text.
# Usage: ./mux_add_srt_subtitle_to_mp4.sh <video_input> <subtitle.srt> [output.mp4]
set -euo pipefail

script_name="$(basename "$0")"

video_input="${1:-}"
subtitle_input="${2:-}"
output="${3:-}"

if [[ -z "$video_input" || -z "$subtitle_input" ]]; then
  echo "Usage: ${script_name} <video_input> <subtitle.srt> [output.mp4]"
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${video_input%.*}_with_subs.mp4"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$video_input" -i "$subtitle_input" \
  -map 0 -map 1:0 \
  -c:v copy -c:a copy -c:s mov_text \
  "$output"
