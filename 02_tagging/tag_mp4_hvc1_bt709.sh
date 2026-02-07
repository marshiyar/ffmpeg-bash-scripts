#!/usr/bin/env bash
# Tag MP4 video stream as hvc1 and attach BT.709 color metadata.
# Usage: ./tag_mp4_hvc1_bt709.sh <input.mp4> [output.mp4]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input.mp4> [output.mp4]"
  exit 1
fi

output="${2:-${input%.*}_tagged.mp4}"

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -map 0 -c copy -movflags +faststart \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -tag:v hvc1 \
  "$output"
