#!/usr/bin/env bash
# Batch hardware encode to HEVC using hevc_videotoolbox.
# Usage: ./encode_hevc_batch_videotoolbox.sh "<glob>" [bitrate] [suffix] [container] [realtime]
# Defaults: bitrate=6M, suffix=_hevc_vt, container=mp4, realtime=false
# Env: PIX_FMT (default yuv420p), MAXRATE (default bitrate), BUFSIZE (default 2x bitrate), ALLOW_SW=1|0
set -euo pipefail

script_name="$(basename "$0")"
shopt -s nullglob

if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])hevc_videotoolbox([[:space:]]|$)'; then
  echo "Error: ffmpeg build does not include hevc_videotoolbox encoder." >&2
  exit 2
fi

pattern="${1:-}"
bitrate="${2:-6M}"
suffix="${3:-_hevc_vt}"
container="${4:-mp4}"
realtime="${5:-false}"
pix_fmt="${PIX_FMT:-yuv420p}"
maxrate="${MAXRATE:-$bitrate}"
bufsize="${BUFSIZE:-12M}"
allow_sw="${ALLOW_SW:-1}"

if [[ -z "$pattern" ]]; then
  echo "Usage: ${script_name} \"<glob>\" [bitrate] [suffix] [container] [realtime]"
  exit 1
fi

files=( $pattern )
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files matched: $pattern"
  exit 1
fi

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  base="${f%.*}"
  out="${base}${suffix}.${container}"
  [[ -e "$out" ]] && { echo "Skip (exists): $out"; continue; }

  video_args=(
    -c:v hevc_videotoolbox
    -b:v "$bitrate"
    -maxrate "$maxrate"
    -bufsize "$bufsize"
    -pix_fmt "$pix_fmt"
    -allow_sw "$allow_sw"
    -realtime "$realtime"
  )
  if [[ "$container" == "mp4" ]]; then
    video_args+=( -tag:v hvc1 )
  fi

  ffmpeg -hide_banner -nostdin -y -i "$f" -map 0 \
    "${video_args[@]}" \
    -c:a copy -c:s copy \
    "$out"
done
