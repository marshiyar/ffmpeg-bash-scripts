#!/usr/bin/env bash
# Combine three contact sheets into a single 3-wide image.
# Usage: ./contact_sheet_combine_three.sh <img1> <img2> <img3> <output> [title]
# Env: FONTFILE or FONTNAME to enable title label.
set -euo pipefail

script_name="$(basename "$0")"

img1="${1:-}"
img2="${2:-}"
img3="${3:-}"
output="${4:-}"
if [[ -z "$img1" || -z "$img2" || -z "$img3" || -z "$output" ]]; then
  echo "Usage: ${script_name} <img1> <img2> <img3> <output> [title]"
  exit 1
fi

base1="$(basename "$img1")"; base1="${base1%.*}"
base2="$(basename "$img2")"; base2="${base2%.*}"
base3="$(basename "$img3")"; base3="${base3%.*}"

title="${5:-${base1} | ${base2} | ${base3}}"
fontsize="${FONTSIZE:-54}"
box_opacity="${BOX_OPACITY:-0.6}"
box_border="${BOX_BORDER:-14}"

filter="[0][1][2]hstack=inputs=3"

if [[ -n "${FONTFILE:-}" ]]; then
  filter+=",drawtext=fontfile=${FONTFILE}:text='${title}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
elif [[ -n "${FONTNAME:-}" ]]; then
  filter+=",drawtext=font=${FONTNAME}:text='${title}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$img1" -i "$img2" -i "$img3" \
  -filter_complex "$filter" \
  "$output"
