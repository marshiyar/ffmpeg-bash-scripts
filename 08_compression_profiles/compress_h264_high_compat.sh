#!/usr/bin/env bash
# High-compatibility H.264 compression profile for broad playback support.
# Usage: ./compress_h264_high_compat.sh <input> [output] [crf] [preset]
# Defaults: output=<input>_h264_std.mp4, crf=21, preset=slow
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

output="${2:-${input%.*}_h264_std.mp4}"
crf="${3:-21}"
preset="${4:-slow}"

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -map 0:v:0 -map 0:a? \
  -c:v libx264 -preset "$preset" -crf "$crf" -pix_fmt yuv420p -profile:v high -level 4.1 \
  -c:a aac -b:a 160k -ac 2 -ar 48000 \
  -movflags +faststart \
  "$output"
