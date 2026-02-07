#!/usr/bin/env bash
# Weighted blend of three inputs -> ProRes 4444.
# Usage: ./blend_weighted_three_to_prores4444.sh <input_a> <input_b> <input_c> [output]
# Weights (env): W_A, W_B, W_M1, W_C
# - First blend: A*W_A + B*W_B
# - Second blend: M1*W_M1 + C*W_C
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
input_c="${3:-}"
if [[ -z "$input_a" || -z "$input_b" || -z "$input_c" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> <input_c> [output]"
  exit 1
fi

base_a="$(basename "$input_a")"
base_a="${base_a%.*}"
base_b="$(basename "$input_b")"
base_b="${base_b%.*}"
base_c="$(basename "$input_c")"
base_c="${base_c%.*}"

output="${4:-${base_a}_${base_b}_${base_c}_weighted_prores4444.mov}"

w_a="${W_A:-0.375}"
w_b="${W_B:-0.625}"
w_m1="${W_M1:-0.2}"
w_c="${W_C:-0.8}"

ffmpeg -hide_banner -nostdin -y \
  -i "$input_a" -i "$input_b" -i "$input_c" \
  -filter_complex "
  [0:v][1:v]blend=all_expr='A*${w_a}+B*${w_b}'[m1];
  [m1][2:v]blend=all_expr='A*${w_m1}+B*${w_c}'[v]
" \
  -map "[v]" -map 0:a? -c:a copy -shortest \
  -c:v prores_ks -profile:v 4 -pix_fmt yuv444p10le -vendor apl0 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -movflags +faststart \
  "$output"
