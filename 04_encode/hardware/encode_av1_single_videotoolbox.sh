#!/usr/bin/env bash
# Single-file hardware encode to AV1 using av1_videotoolbox.
# Usage: ./encode_av1_single_videotoolbox.sh <input> [output] [bitrate] [realtime]
# Defaults: output=<input>_av1_vt.mp4, bitrate=5M, realtime=false
# Env: PIX_FMT (default yuv420p), MAXRATE (default bitrate), BUFSIZE (default 2x bitrate), ALLOW_SW=1|0
set -euo pipefail

script_name="$(basename "$0")"

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])av1_videotoolbox([[:space:]]|$)'; then
  echo "Error: ffmpeg build does not include av1_videotoolbox encoder." >&2
  exit 2
fi

input="${1:-}"
if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [bitrate] [realtime]"
  exit 1
fi

output="${2:-${input%.*}_av1_vt.mp4}"
bitrate="${3:-5M}"
realtime="${4:-false}"
pix_fmt="${PIX_FMT:-yuv420p}"
maxrate="${MAXRATE:-$bitrate}"
bufsize="${BUFSIZE:-10M}"
allow_sw="${ALLOW_SW:-1}"

video_args=(
  -c:v av1_videotoolbox
  -b:v "$bitrate"
  -maxrate "$maxrate"
  -bufsize "$bufsize"
  -pix_fmt "$pix_fmt"
  -allow_sw "$allow_sw"
  -realtime "$realtime"
)

if [[ "$output" == *.mp4 ]]; then
  video_args+=( -tag:v av01 )
fi

ffmpeg -hide_banner -nostdin -y -i "$input" -map 0 \
  "${video_args[@]}" \
  -c:a copy -c:s copy \
  "$output"
