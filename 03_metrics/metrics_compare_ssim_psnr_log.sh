#!/usr/bin/env bash
# Compare two videos with SSIM+PSNR and write SSIM stats file.
# Usage: ./metrics_compare_ssim_psnr_log.sh <reference> <test> [stats_file] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

reference="${1:-}"
test="${2:-}"
if [[ -z "$reference" || -z "$test" ]]; then
  echo "Usage: ${script_name} <reference> <test> [stats_file] [width] [height]"
  exit 1
fi

base_ref="$(basename "$reference")"; base_ref="${base_ref%.*}"
base_test="$(basename "$test")"; base_test="${base_test%.*}"

stats_file="${3:-ssim_${base_ref}_vs_${base_test}.log}"
width="${4:-}"
height="${5:-}"

if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$reference")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$reference")"
fi

ffmpeg -hide_banner -nostdin \
  -i "$reference" -i "$test" \
  -lavfi "[0:v]scale=${width}:${height}:flags=bicubic,format=yuv420p10le[ref];[1:v]scale=${width}:${height}:flags=bicubic,format=yuv420p10le[test];[test][ref]ssim=stats_file=${stats_file};[test][ref]psnr" \
  -f null -
