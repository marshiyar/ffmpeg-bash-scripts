#!/usr/bin/env bash
# Batch re-encode files matching a glob to AV1 with libsvtav1.
# Usage: ./encode_av1_batch_svt.sh "<glob>" [crf] [preset] [suffix] [container]
# Example: ./encode_av1_batch_svt.sh "*.mp4" 32 8 _av1_svt mkv
# Env: PIX_FMT (default yuv420p10le)
set -euo pipefail

script_name="$(basename "$0")"
shopt -s nullglob

pattern="${1:-}"
crf="${2:-32}"
preset="${3:-8}"
suffix="${4:-_av1_svt}"
container="${5:-mkv}"
pix_fmt="${PIX_FMT:-yuv420p10le}"

if [[ -z "$pattern" ]]; then
  echo "Usage: ${script_name} \"<glob>\" [crf] [preset] [suffix] [container]"
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

  video_args=( -c:v libsvtav1 -crf "$crf" -preset "$preset" -pix_fmt "$pix_fmt" )
  if [[ "$container" == "mp4" ]]; then
    video_args+=( -tag:v av01 )
  fi

  ffmpeg -hide_banner -nostdin -y -i "$f" -map 0 \
    "${video_args[@]}" \
    -c:a copy -c:s copy \
    "$out"
done
