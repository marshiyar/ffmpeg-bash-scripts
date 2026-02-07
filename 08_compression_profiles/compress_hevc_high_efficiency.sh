#!/usr/bin/env bash
# High-efficiency HEVC compression profile (10-bit).
# Usage: ./compress_hevc_high_efficiency.sh <input> [output] [crf] [preset]
# Defaults: output=<input>_hevc_std.mp4, crf=24, preset=slow
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

output="${2:-${input%.*}_hevc_std.mp4}"
crf="${3:-24}"
preset="${4:-slow}"

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -map 0:v:0 -map 0:a? \
  -c:v libx265 -preset "$preset" -crf "$crf" -pix_fmt yuv420p10le -tag:v hvc1 \
  -x265-params "aq-mode=3:aq-strength=0.9:deblock=-1,-1" \
  -c:a aac -b:a 160k -ac 2 -ar 48000 \
  -movflags +faststart \
  "$output"
