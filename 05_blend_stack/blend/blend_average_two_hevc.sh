#!/usr/bin/env bash
# Average blend of two inputs, encode to HEVC.
# Usage: ./blend_average_two_to_hevc.sh <input_a> <input_b> [output] [crf] [preset]
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
if [[ -z "$input_a" || -z "$input_b" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> [output] [crf] [preset]"
  exit 1
fi

base_a="$(basename "$input_a")"
base_a="${base_a%.*}"
base_b="$(basename "$input_b")"
base_b="${base_b%.*}"

output="${3:-${base_a}_${base_b}_avg_hevc.mp4}"
crf="${4:-10}"
preset="${5:-fast}"
pix_fmt="${PIX_FMT:-yuv420p10le}"

ffmpeg -hide_banner -nostdin -y -i "$input_a" -i "$input_b" -filter_complex \
  "[0:v][1:v]blend=all_mode=average[v]" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v libx265 -pix_fmt "$pix_fmt" -preset "$preset" -crf "$crf" \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -tag:v hvc1 \
  -movflags +faststart "$output"
