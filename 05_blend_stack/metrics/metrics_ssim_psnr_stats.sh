#!/usr/bin/env bash
# SSIM (with stats file) + PSNR between reference and test.
# Usage: ./metrics_ssim_psnr_stats.sh <ref> <test> [stats_file] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

ref="${1:-}"
test="${2:-}"
if [[ -z "$ref" || -z "$test" ]]; then
  echo "Usage: ${script_name} <ref> <test> [stats_file] [width] [height]"
  exit 1
fi

base_ref="$(basename "$ref")"
base_ref="${base_ref%.*}"
base_test="$(basename "$test")"
base_test="${base_test%.*}"

stats_file="${3:-ssim_${base_ref}_vs_${base_test}.log}"
width="${4:-}"
height="${5:-}"

if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$ref")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$ref")"
fi

ffmpeg -hide_banner -nostdin -i "$ref" -i "$test" -lavfi \
  "[0:v]scale=${width}:${height}:flags=bicubic,format=yuv420p10le[ref];\
   [1:v]scale=${width}:${height}:flags=bicubic,format=yuv420p10le[test];\
   [test][ref]ssim=stats_file=${stats_file};[test][ref]psnr" \
  -f null -
