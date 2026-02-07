#!/usr/bin/env bash
# Normalize one input: minterpolate to target FPS, scale, ProRes 4444.
# Usage: ./encode_prores4444_minterpolate.sh <input> <output> [fps] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output> [fps] [width] [height]"
  exit 1
fi

fps="${3:-30}"
width="${4:-}"
height="${5:-}"

if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -filter_complex "[0:v]minterpolate=fps=${fps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1,scale=${width}:${height}:flags=bicubic,format=yuv444p10le[v]" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -movflags +faststart \
  "$output"
