#!/usr/bin/env bash
# Batch re-encode a glob of files to H.264 (libx264).
# Usage: ./encode_h264_batch_x264.sh "<glob>" [crf] [preset] [suffix]
# Example: ./encode_h264_batch_x264.sh "*.mp4" 20 medium _h264
set -euo pipefail

script_name="$(basename "$0")"
shopt -s nullglob

pattern="${1:-}"
crf="${2:-20}"
preset="${3:-medium}"
suffix="${4:-_h264}"

if [[ -z "$pattern" ]]; then
  echo "Usage: ${script_name} \"<glob>\" [crf] [preset] [suffix]"
  exit 1
fi

files=( $pattern )
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files matched: $pattern"
  exit 1
fi

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  base="${f%.*}"
  out="${base}${suffix}.mp4"
  [[ -e "$out" ]] && { echo "Skip (exists): $out"; continue; }
  ffmpeg -hide_banner -nostdin -y -i "$f" -map 0 \
    -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv420p -tag:v avc1 \
    -c:a copy -c:s copy "$out"
done
