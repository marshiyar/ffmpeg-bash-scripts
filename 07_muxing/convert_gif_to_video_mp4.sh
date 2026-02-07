#!/usr/bin/env bash
# Convert a GIF into an MP4 video with broad playback compatibility.
# Usage: ./convert_gif_to_video_mp4.sh <input.gif> [output.mp4] [fps] [crf] [preset]
# Defaults: output=<input>_from_gif.mp4, fps=30, crf=18, preset=medium
# Notes:
# - GIF transparency is flattened by conversion to yuv420p for compatibility.
# - Output dimensions are rounded to even numbers to avoid encoder/player issues.
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
fps="${3:-30}"
crf="${4:-18}"
preset="${5:-medium}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input.gif> [output.mp4] [fps] [crf] [preset]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

ext="${input##*.}"
ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
if [[ "$ext" != "gif" ]]; then
  echo "Error: input must be a .gif file" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${input%.*}_from_gif.mp4"
fi

if ! [[ "$fps" =~ ^[0-9]+$ ]] || (( fps < 1 )); then
  echo "Error: fps must be a positive integer." >&2
  exit 1
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -map 0:v:0 -an \
  -vf "fps=${fps},scale=trunc(iw/2)*2:trunc(ih/2)*2:flags=lanczos,format=yuv420p" \
  -c:v libx264 -crf "$crf" -preset "$preset" -tag:v avc1 \
  -movflags +faststart \
  "$output"
