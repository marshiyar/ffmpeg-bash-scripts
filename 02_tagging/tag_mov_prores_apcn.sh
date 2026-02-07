#!/usr/bin/env bash
# Tag MOV video stream as ProRes apcn while stream-copying all tracks.
# Usage: ./tag_mov_prores_apcn.sh <input.mov> [output.mov]
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
  -map 0 -c copy -movflags +faststart \
  -tag:v apcn \
  "$output"
