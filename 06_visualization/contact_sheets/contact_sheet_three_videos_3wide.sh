#!/usr/bin/env bash
# Build one contact sheet per video (3 inputs) and a 3-wide combined comparison image.
# Usage: ./contact_sheet_three_videos_3wide.sh <video1> <video2> <video3> [out_dir]
# Env: FPS, SCALE_WIDTH, TILE, FONTFILE, FONTNAME, FONTSIZE, BOX_OPACITY, BOX_BORDER, COMBINED_LABEL
set -euo pipefail

script_name="$(basename "$0")"

video1="${1:-}"
video2="${2:-}"
video3="${3:-}"
out_dir="${4:-contact_sheets}"

if [[ -z "$video1" || -z "$video2" || -z "$video3" ]]; then
  echo "Usage: ${script_name} <video1> <video2> <video3> [out_dir]"
  exit 1
fi

fps="${FPS:-2.5}"
scale_width="${SCALE_WIDTH:-960}"
tile="${TILE:-8x8}"
fontsize="${FONTSIZE:-48}"
box_opacity="${BOX_OPACITY:-0.55}"
box_border="${BOX_BORDER:-12}"

mkdir -p "$out_dir"

base1="$(basename "$video1")"; base1="${base1%.*}"
base2="$(basename "$video2")"; base2="${base2%.*}"
base3="$(basename "$video3")"; base3="${base3%.*}"

sheet1="${out_dir}/${base1}_contact_8x8_${scale_width}.jpg"
sheet2="${out_dir}/${base2}_contact_8x8_${scale_width}.jpg"
sheet3="${out_dir}/${base3}_contact_8x8_${scale_width}.jpg"
combined="${out_dir}/combined_3wide_contact_8x8_${scale_width}.jpg"
combined_label="${COMBINED_LABEL:-Combined: ${base1} | ${base2} | ${base3}}"

sheet_filter() {
  local label="$1"
  local f="fps=${fps},scale=${scale_width}:-1,tile=${tile}"
  if [[ -n "${FONTFILE:-}" ]]; then
    f+=",drawtext=fontfile=${FONTFILE}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
  elif [[ -n "${FONTNAME:-}" ]]; then
    f+=",drawtext=font=${FONTNAME}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
  fi
  printf '%s' "$f"
}

ffmpeg -hide_banner -nostdin -y -i "$video1" -vf "$(sheet_filter "$base1")" -frames:v 1 "$sheet1"
ffmpeg -hide_banner -nostdin -y -i "$video2" -vf "$(sheet_filter "$base2")" -frames:v 1 "$sheet2"
ffmpeg -hide_banner -nostdin -y -i "$video3" -vf "$(sheet_filter "$base3")" -frames:v 1 "$sheet3"

combine_filter="[0][1][2]hstack=inputs=3"
if [[ -n "${FONTFILE:-}" ]]; then
  combine_filter+=",drawtext=fontfile=${FONTFILE}:text='${combined_label}':x=20:y=40:fontsize=54:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=14"
elif [[ -n "${FONTNAME:-}" ]]; then
  combine_filter+=",drawtext=font=${FONTNAME}:text='${combined_label}':x=20:y=40:fontsize=54:fontcolor=white:box=1:boxcolor=black@0.6:boxborderw=14"
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$sheet1" -i "$sheet2" -i "$sheet3" \
  -filter_complex "$combine_filter" \
  "$combined"
