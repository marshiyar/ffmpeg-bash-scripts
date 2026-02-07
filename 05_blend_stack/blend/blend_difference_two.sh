#!/usr/bin/env bash
# Blend two inputs with difference mode (for checking alignment).
# Usage: ./blend_difference_two.sh <input_a> <input_b> [output]
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
if [[ -z "$input_a" || -z "$input_b" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> [output]"
  exit 1
fi

base_a="$(basename "$input_a")"
base_a="${base_a%.*}"
base_b="$(basename "$input_b")"
base_b="${base_b%.*}"

output="${3:-${base_a}_vs_${base_b}_diff.mp4}"

ffmpeg -hide_banner -nostdin -y -i "$input_a" -i "$input_b" \
  -filter_complex "blend=all_mode=difference" \
  -an "$output"
