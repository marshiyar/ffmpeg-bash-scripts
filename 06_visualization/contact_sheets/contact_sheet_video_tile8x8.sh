#!/usr/bin/env bash
# Generate a tiled contact sheet from one video.
# Usage: ./contact_sheet_video_tile8x8.sh <input_video> <output_image> [fps] [scale_width] [tile]
# Env: LABEL, FONTFILE, FONTNAME, FONTSIZE, BOX_OPACITY, BOX_BORDER
set -euo pipefail

script_name="$(basename "$0")"

input_video="${1:-}"
output_image="${2:-}"
if [[ -z "$input_video" || -z "$output_image" ]]; then
  echo "Usage: ${script_name} <input_video> <output_image> [fps] [scale_width] [tile]"
  exit 1
fi

fps="${3:-2.5}"
scale_width="${4:-960}"
tile="${5:-8x8}"

base="$(basename "$input_video")"
base="${base%.*}"
label="${LABEL:-$base}"
fontsize="${FONTSIZE:-48}"
box_opacity="${BOX_OPACITY:-0.55}"
box_border="${BOX_BORDER:-12}"

filter="fps=${fps},scale=${scale_width}:-1,tile=${tile}"
if [[ -n "${FONTFILE:-}" ]]; then
  filter+=",drawtext=fontfile=${FONTFILE}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
elif [[ -n "${FONTNAME:-}" ]]; then
  filter+=",drawtext=font=${FONTNAME}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$input_video" \
  -vf "$filter" \
  -frames:v 1 "$output_image"
