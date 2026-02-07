#!/usr/bin/env bash
# Two-pass H.264 compression targeting a specific output size.
# Usage: ./compress_h264_two_pass_target_size.sh <input> <target_mb> [output] [preset] [audio_kbps]
# Defaults: output=<input>_h264_target.mp4, preset=slow, audio_kbps=128
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
target_mb="${2:-}"
if [[ -z "$input" || -z "$target_mb" ]]; then
  echo "Usage: ${script_name} <input> <target_mb> [output] [preset] [audio_kbps]"
  exit 1
fi

output="${3:-${input%.*}_h264_target.mp4}"
preset="${4:-slow}"
audio_kbps="${5:-128}"

duration="$(ffprobe -v error -show_entries format=duration -of default=nw=1:nk=1 "$input")"
if [[ -z "$duration" ]]; then
  echo "Error: could not read input duration." >&2
  exit 1
fi

video_kbps="$(awk -v mb="$target_mb" -v dur="$duration" -v a="$audio_kbps" 'BEGIN {
  total_kbits = mb * 8192;
  v = int((total_kbits / dur) - a);
  if (v < 250) v = 250;
  print v;
}')"

passlog="$(mktemp "${TMPDIR:-/tmp}/ffmpeg_2pass.XXXXXX")"
cleanup() {
  rm -f "${passlog}" "${passlog}"-0.log "${passlog}"-0.log.mbtree
}
trap cleanup EXIT

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -map 0:v:0 \
  -c:v libx264 -preset "$preset" -b:v "${video_kbps}k" \
  -pass 1 -passlogfile "$passlog" \
  -an -f mp4 /dev/null

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -map 0:v:0 -map 0:a? \
  -c:v libx264 -preset "$preset" -b:v "${video_kbps}k" \
  -pass 2 -passlogfile "$passlog" \
  -c:a aac -b:a "${audio_kbps}k" -ac 2 -ar 48000 \
  -movflags +faststart \
  "$output"
