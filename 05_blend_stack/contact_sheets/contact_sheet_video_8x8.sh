#!/usr/bin/env bash
# Generate an 8x8 contact sheet from a video.
# Usage: ./contact_sheet_video_8x8.sh <input> <output> [fps] [scale_width] [tile]
# Env: FONTFILE or FONTNAME to enable labels; LABEL overrides default title.
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output> [fps] [scale_width] [tile]"
  exit 1
fi

fps="${3:-2.5}"
scale_w="${4:-960}"
tile="${5:-8x8}"

base="$(basename "$input")"
base="${base%.*}"
label="${LABEL:-$base}"
fontsize="${FONTSIZE:-48}"
box_opacity="${BOX_OPACITY:-0.55}"
box_border="${BOX_BORDER:-12}"

filter="fps=${fps},scale=${scale_w}:-1,tile=${tile}"

if [[ -n "${FONTFILE:-}" ]]; then
  filter+=",drawtext=fontfile=${FONTFILE}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
elif [[ -n "${FONTNAME:-}" ]]; then
  filter+=",drawtext=font=${FONTNAME}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -vf "${filter}" \
  -frames:v 1 "$output"
