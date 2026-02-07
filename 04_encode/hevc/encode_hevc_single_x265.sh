#!/usr/bin/env bash
# Single-file re-encode to HEVC (libx265), copy audio/subs.
# Usage: ./encode_hevc_single_x265.sh <input> [output] [crf] [preset]
set -euo pipefail

script_name="$(basename "$0")"

in="${1:-}"
if [[ -z "$in" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [preset]"
  exit 1
fi

out="${2:-${in%.*}_hevc.mp4}"
crf="${3:-20}"
preset="${4:-medium}"

ffmpeg -hide_banner -nostdin -y -i "$in" -map 0 \
  -c:v libx265 -crf "$crf" -preset "$preset" \
  -tag:v hvc1 -c:a copy -c:s copy "$out"
