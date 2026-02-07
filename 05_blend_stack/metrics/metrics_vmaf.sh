#!/usr/bin/env bash
# VMAF between reference and test.
# Usage: ./metrics_vmaf.sh <ref> <test> [model] [width] [height]
set -euo pipefail

script_name="$(basename "$0")"

ref="${1:-}"
test="${2:-}"
if [[ -z "$ref" || -z "$test" ]]; then
  echo "Usage: ${script_name} <ref> <test> [model] [width] [height]"
  exit 1
fi

model="${3:-vmaf_v0.6.1}"
width="${4:-}"
height="${5:-}"

if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$ref")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$ref")"
fi

ffmpeg -hide_banner -nostdin -i "$ref" -i "$test" -lavfi "
  [0:v]scale=${width}:${height}:flags=bicubic[ref];
  [1:v]scale=${width}:${height}:flags=bicubic[test];
  [test][ref]libvmaf=model=version=${model}
" -f null -
