#!/usr/bin/env bash
# Single-file re-encode to H.264 (libx264), copy audio/subtitles.
# Usage: ./encode_h264_single_x264.sh <input> [output] [crf] [preset]
set -euo pipefail

script_name="$(basename "$0")"

in="${1:-}"
if [[ -z "$in" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

out="${2:-${in%.*}_h264.mp4}"
crf="${3:-20}"
preset="${4:-medium}"

ffmpeg -hide_banner -nostdin -y -i "$in" -map 0 \
  -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p \
  -tag:v avc1 -c:a copy -c:s copy "$out"
