#!/usr/bin/env bash
# Normalize two inputs to same FPS/size, output two ProRes 422 HQ MOVs.
# Usage: ./normalize_two_to_prores422.sh <input_a> <input_b> [out_dir] [fps] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
if [[ -z "$input_a" || -z "$input_b" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> [out_dir] [fps] [width] [height]"
  exit 1
fi

out_dir="${3:-.}"
fps="${4:-30}"
width="${5:-}"
height="${6:-}"

if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input_a")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input_a")"
fi

mkdir -p "$out_dir"
base_a="$(basename "$input_a")"
base_a="${base_a%.*}"
base_b="$(basename "$input_b")"
base_b="${base_b%.*}"

out_a="${out_dir}/${base_a}_norm.mov"
out_b="${out_dir}/${base_b}_norm.mov"

ffmpeg -hide_banner -nostdin -y -i "$input_a" -i "$input_b" -filter_complex "
  [0:v]fps=${fps},scale=${width}:${height}:flags=bicubic,format=yuv444p10le[a];
  [1:v]fps=${fps},scale=${width}:${height}:flags=bicubic,format=yuv444p10le[b]
" \
  -map "[a]" -map 0:a? -c:a copy -c:v prores_ks -profile:v 3 -vendor apl0 -pix_fmt yuv422p10le "$out_a" \
  -map "[b]" -map 1:a? -c:a copy -c:v prores_ks -profile:v 3 -vendor apl0 -pix_fmt yuv422p10le "$out_b"
