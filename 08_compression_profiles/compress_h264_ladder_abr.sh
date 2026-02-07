#!/usr/bin/env bash
# Build a practical 3-rung H.264 ABR ladder (1080p/720p/480p).
# Usage: ./compress_h264_ladder_abr.sh <input> [output_dir]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
out_dir="${2:-abr_ladder}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output_dir]"
  exit 1
fi

mkdir -p "$out_dir"
base="$(basename "$input")"
base="${base%.*}"

encode_rung() {
  local height="$1"
  local vbitrate="$2"
  local maxrate="$3"
  local bufsize="$4"
  local out_file="$5"

  ffmpeg -hide_banner -nostdin -y -i "$input" \
    -map 0:v:0 -map 0:a? \
    -vf "scale=-2:${height}:flags=lanczos" \
    -c:v libx264 -preset slow -profile:v high -level 4.1 -pix_fmt yuv420p \
    -b:v "$vbitrate" -maxrate "$maxrate" -bufsize "$bufsize" \
    -c:a aac -b:a 128k -ac 2 -ar 48000 \
    -movflags +faststart \
    "$out_file"
}

encode_rung 1080 5000k 5500k 10000k "${out_dir}/${base}_1080p.mp4"
encode_rung 720  2800k 3200k 5600k  "${out_dir}/${base}_720p.mp4"
encode_rung 480  1200k 1500k 2400k  "${out_dir}/${base}_480p.mp4"
