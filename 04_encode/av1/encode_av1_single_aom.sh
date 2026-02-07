#!/usr/bin/env bash
# Single-file re-encode to AV1 with libaom-av1 (quality-focused, slower).
# Usage: ./encode_av1_single_aom.sh <input> [output] [crf] [cpu_used]
# Defaults: output=<input>_av1_aom.mkv, crf=30, cpu_used=6
# Env: PIX_FMT (default yuv420p10le)
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [crf] [cpu_used]"
  exit 1
fi

output="${2:-${input%.*}_av1_aom.mkv}"
crf="${3:-30}"
cpu_used="${4:-6}"
pix_fmt="${PIX_FMT:-yuv420p10le}"

video_args=( -c:v libaom-av1 -crf "$crf" -b:v 0 -cpu-used "$cpu_used" -row-mt 1 -pix_fmt "$pix_fmt" )
if [[ "$output" == *.mp4 ]]; then
  video_args+=( -tag:v av01 )
fi

ffmpeg -hide_banner -nostdin -y -i "$input" -map 0 \
  "${video_args[@]}" \
  -c:a copy -c:s copy \
  "$output"
