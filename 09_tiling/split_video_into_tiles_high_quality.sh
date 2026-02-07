#!/usr/bin/env bash
# Split a video into spatial tiles (grid) and save a manifest for exact seam-free reassembly.
# Usage: ./split_video_into_tiles_high_quality.sh <input> <rows> <cols> <out_dir> [crf] [preset]
# Defaults: crf=10, preset=slow
# Env:
#   TILE_CODEC=ffv1|libx264 (default: ffv1)
# Notes:
#   - Default ffv1 mode is lossless and safer for odd tile dimensions.
#   - If TILE_CODEC=libx264, odd tile widths/heights can be adjusted by encoder behavior.
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
rows="${2:-}"
cols="${3:-}"
out_dir="${4:-}"
crf="${5:-10}"
preset="${6:-slow}"
tile_codec="${TILE_CODEC:-ffv1}"

if [[ -z "$input" || -z "$rows" || -z "$cols" || -z "$out_dir" ]]; then
  echo "Usage: ${script_name} <input> <rows> <cols> <out_dir> [crf] [preset]"
  exit 1
fi

if ! [[ "$rows" =~ ^[0-9]+$ ]] || ! [[ "$cols" =~ ^[0-9]+$ ]] || [[ "$rows" -lt 1 ]] || [[ "$cols" -lt 1 ]]; then
  echo "Error: rows/cols must be positive integers." >&2
  exit 1
fi

if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")"
height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")"
if [[ -z "$width" || -z "$height" ]]; then
  echo "Error: failed to probe input dimensions." >&2
  exit 1
fi

mkdir -p "$out_dir"
manifest="${out_dir}/tiles_manifest.tsv"

base_w=$((width / cols))
rem_w=$((width % cols))
base_h=$((height / rows))
rem_h=$((height % rows))

declare -a col_w
declare -a row_h

for ((c=0; c<cols; c++)); do
  w=$base_w
  if (( c < rem_w )); then
    w=$((w + 1))
  fi
  col_w[$c]="$w"
done

for ((r=0; r<rows; r++)); do
  h=$base_h
  if (( r < rem_h )); then
    h=$((h + 1))
  fi
  row_h[$r]="$h"
done

{
  echo "# spatial-tiles-manifest-v1"
  echo "input=${input}"
  echo "rows=${rows}"
  echo "cols=${cols}"
  echo "width=${width}"
  echo "height=${height}"
  echo "tile_count=$((rows * cols))"
  printf "tile\tidx\trow\tcol\tx\ty\tw\th\tfile\n"
} > "$manifest"

tile_idx=0
y=0
for ((r=0; r<rows; r++)); do
  h="${row_h[$r]}"
  x=0
  for ((c=0; c<cols; c++)); do
    w="${col_w[$c]}"
    if [[ "$tile_codec" == "ffv1" ]]; then
      tile_file="$(printf 'tile_r%03d_c%03d.mkv' "$r" "$c")"
    else
      tile_file="$(printf 'tile_r%03d_c%03d.mp4' "$r" "$c")"
    fi
    tile_path="${out_dir}/${tile_file}"

    if [[ "$tile_codec" == "ffv1" ]]; then
      ffmpeg -hide_banner -nostdin -y \
        -i "$input" \
        -map 0:v:0 -an -sn \
        -vf "format=yuv444p,crop=${w}:${h}:${x}:${y}" \
        -c:v ffv1 -level 3 \
        "$tile_path"
    elif [[ "$tile_codec" == "libx264" ]]; then
      ffmpeg -hide_banner -nostdin -y \
        -i "$input" \
        -map 0:v:0 -an -sn \
        -vf "format=yuv444p,crop=${w}:${h}:${x}:${y}" \
        -c:v libx264 -crf "$crf" -preset "$preset" -pix_fmt yuv444p \
        "$tile_path"
    else
      echo "Error: unsupported TILE_CODEC='$tile_codec'. Use ffv1 or libx264." >&2
      exit 1
    fi

    printf "tile\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$tile_idx" "$r" "$c" "$x" "$y" "$w" "$h" "$tile_file" >> "$manifest"

    x=$((x + w))
    tile_idx=$((tile_idx + 1))
  done
  y=$((y + h))
done

echo "Done. Tiles written to: $out_dir"
echo "Manifest: $manifest"
echo "Tile index map (${rows}x${cols}):"
idx=0
for ((r=0; r<rows; r++)); do
  line=""
  for ((c=0; c<cols; c++)); do
    label="$(printf '%03d' "$idx")"
    if [[ -n "$line" ]]; then
      line+=" "
    fi
    line+="$label"
    idx=$((idx + 1))
  done
  echo "$line"
done
