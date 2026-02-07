#!/usr/bin/env bash
# Normalize three inputs to same FPS/size, output three ProRes 4444 MOVs.
# Usage: ./normalize_three_to_prores4444.sh <input_a> <input_b> <input_c> [out_dir] [fps] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
input_c="${3:-}"
if [[ -z "$input_a" || -z "$input_b" || -z "$input_c" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> <input_c> [out_dir] [fps] [width] [height]"
  exit 1
fi

out_dir="${4:-.}"
fps="${5:-30}"
width="${6:-}"
height="${7:-}"

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
base_c="$(basename "$input_c")"
base_c="${base_c%.*}"

out_a="${out_dir}/${base_a}_norm.mov"
out_b="${out_dir}/${base_b}_norm.mov"
out_c="${out_dir}/${base_c}_norm.mov"

ffmpeg -hide_banner -nostdin -y -i "$input_a" -i "$input_b" -i "$input_c" -filter_complex "
  [0:v]fps=${fps},scale=${width}:${height}:flags=bicubic,format=yuv444p10le[a];
  [1:v]fps=${fps},scale=${width}:${height}:flags=bicubic,format=yuv444p10le[b];
  [2:v]fps=${fps},scale=${width}:${height}:flags=bicubic,format=yuv444p10le[c]
" \
  -map "[a]" -map 0:a? -c:a copy -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 "$out_a" \
  -map "[b]" -map 1:a? -c:a copy -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 "$out_b" \
  -map "[c]" -map 2:a? -c:a copy -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 "$out_c" \
  -shortest
