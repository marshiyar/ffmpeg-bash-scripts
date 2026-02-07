#!/usr/bin/env bash
# Tag MOV video stream as avc1 and attach BT.709 color metadata.
# Usage: ./tag_mov_avc1_bt709.sh <input.mov> [output.mov]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input.mov> [output.mov]"
  exit 1
fi

output="${2:-${input%.*}_tagged.mov}"

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -map 0 -c copy -movflags +faststart+write_colr \
  -tag:v avc1 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  "$output"
