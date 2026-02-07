#!/usr/bin/env bash
# Build multi-filter contact sheets for 3 videos and combined 3-wide composites per filter.
# Usage: ./contact_sheet_three_videos_multi_filters.sh <video1> <video2> <video3> [out_dir]
# Env: FPS, SCALE_WIDTH, TILE, FONTFILE, FONTNAME, FONTSIZE, BOX_OPACITY, BOX_BORDER
set -euo pipefail

script_name="$(basename "$0")"

video1="${1:-}"
video2="${2:-}"
video3="${3:-}"
out_dir="${4:-contacts}"

if [[ -z "$video1" || -z "$video2" || -z "$video3" ]]; then
  echo "Usage: ${script_name} <video1> <video2> <video3> [out_dir]"
  exit 1
fi

fps="${FPS:-2.5}"
scale_width="${SCALE_WIDTH:-960}"
tile="${TILE:-8x8}"
fontsize="${FONTSIZE:-38}"
box_opacity="${BOX_OPACITY:-0.55}"
box_border="${BOX_BORDER:-10}"

mkdir -p "$out_dir"

base1="$(basename "$video1")"; base1="${base1%.*}"
base2="$(basename "$video2")"; base2="${base2%.*}"
base3="$(basename "$video3")"; base3="${base3%.*}"

modes=(normal edges contrast false_color chroma_uv)
filters=(
  ""
  "edgedetect=mode=sobel"
  "eq=contrast=1.7:brightness=0.02:saturation=1.0"
  "format=gray,normalize,eq=contrast=1.8:brightness=0.1"
  "format=yuv444p,extractplanes=u+v"
)

sheet_filter() {
  local label="$1"
  local mode_filter="$2"
  local f="fps=${fps},scale=${scale_width}:-1,tile=${tile}"
  if [[ -n "$mode_filter" ]]; then
    f+=",${mode_filter}"
  fi
  if [[ -n "${FONTFILE:-}" ]]; then
    f+=",drawtext=fontfile=${FONTFILE}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
  elif [[ -n "${FONTNAME:-}" ]]; then
    f+=",drawtext=font=${FONTNAME}:text='${label}':x=20:y=40:fontsize=${fontsize}:fontcolor=white:box=1:boxcolor=black@${box_opacity}:boxborderw=${box_border}"
  fi
  printf '%s' "$f"
}

for i in "${!modes[@]}"; do
  mode="${modes[$i]}"
  mode_filter="${filters[$i]}"

  img1="${out_dir}/${mode}_${base1}.jpg"
  img2="${out_dir}/${mode}_${base2}.jpg"
  img3="${out_dir}/${mode}_${base3}.jpg"
  combined="${out_dir}/all_${mode}.jpg"

  ffmpeg -hide_banner -nostdin -y -i "$video1" -vf "$(sheet_filter "$base1" "$mode_filter")" -frames:v 1 "$img1"
  ffmpeg -hide_banner -nostdin -y -i "$video2" -vf "$(sheet_filter "$base2" "$mode_filter")" -frames:v 1 "$img2"
  ffmpeg -hide_banner -nostdin -y -i "$video3" -vf "$(sheet_filter "$base3" "$mode_filter")" -frames:v 1 "$img3"

  ffmpeg -hide_banner -nostdin -y \
    -i "$img1" -i "$img2" -i "$img3" \
    -filter_complex "[0][1][2]hstack=inputs=3" \
    "$combined"
done
