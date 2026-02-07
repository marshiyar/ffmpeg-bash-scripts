#!/usr/bin/env bash
# Single-file re-encode to AV1 with libsvtav1.
# Usage: ./encode_av1_single_svt.sh <input> [output] [crf] [preset]
# Defaults: output=<input>_av1_svt.mkv, crf=32, preset=8
# Env: PIX_FMT (default yuv420p10le)
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

output="${2:-${input%.*}_av1_svt.mkv}"
crf="${3:-32}"
preset="${4:-8}"
pix_fmt="${PIX_FMT:-yuv420p10le}"

video_args=( -c:v libsvtav1 -crf "$crf" -preset "$preset" -pix_fmt "$pix_fmt" )
if [[ "$output" == *.mp4 ]]; then
  video_args+=( -tag:v av01 )
fi

ffmpeg -hide_banner -nostdin -y -i "$input" -map 0 \
  "${video_args[@]}" \
  -c:a copy -c:s copy \
  "$output"
