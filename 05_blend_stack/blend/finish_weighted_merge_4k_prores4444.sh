#!/usr/bin/env bash
# Finish a weighted merge: scale, unsharp, deband, noise, output 4K ProRes 4444.
# Usage: ./finish_weighted_merge_to_4k_prores4444.sh <input> <output> [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output> [width] [height]"
  exit 1
fi

width="${3:-3840}"
height="${4:-2160}"

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -filter_complex "
  [0:v]format=gbrp12le,
        zscale=w=${width}:h=${height}:filter=lanczos:param_a=4,
        unsharp=5:5:0.25:5:5:0.15,
        deband,
        noise=alls=1:allf=t[v]
" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -movflags +faststart \
  "$output"
