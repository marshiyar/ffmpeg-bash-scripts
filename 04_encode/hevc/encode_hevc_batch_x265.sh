#!/usr/bin/env bash
# Batch re-encode a glob of files to HEVC (libx265).
# Usage: ./encode_hevc_batch_x265.sh "<glob>" [crf] [preset] [suffix]
# Example: ./encode_hevc_batch_x265.sh "*.mp4" 20 medium _hevc
set -euo pipefail

script_name="$(basename "$0")"
shopt -s nullglob

pattern="${1:-}"
crf="${2:-20}"
preset="${3:-medium}"
suffix="${4:-_hevc}"

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
    -c:v libx265 -crf "$crf" -preset "$preset" -tag:v hvc1 \
    -c:a copy -c:s copy "$out"
done
