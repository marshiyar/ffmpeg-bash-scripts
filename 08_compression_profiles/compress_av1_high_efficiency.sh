#!/usr/bin/env bash
# High-efficiency AV1 compression profile with libsvtav1.
# Usage: ./compress_av1_high_efficiency.sh <input> [output] [crf] [preset]
# Defaults: output=<input>_av1_std.mkv, crf=32, preset=6
set -euo pipefail

script_name="$(basename "$0")"

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])libsvtav1([[:space:]]|$)'; then
  echo "Error: ffmpeg build does not include libsvtav1 encoder." >&2
  exit 2
fi

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

output="${2:-${input%.*}_av1_std.mkv}"
crf="${3:-32}"
preset="${4:-6}"

video_args=( -c:v libsvtav1 -crf "$crf" -preset "$preset" -pix_fmt yuv420p10le )
if [[ "$output" == *.mp4 ]]; then
  video_args+=( -tag:v av01 )
fi

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -map 0:v:0 -map 0:a? \
  "${video_args[@]}" \
  -c:a aac -b:a 160k -ac 2 -ar 48000 \
  "$output"
