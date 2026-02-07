#!/usr/bin/env bash
# Split video into spatial tiles, upscale each tile, then reassemble seam-free.
# Usage: ./upscale_video_by_tiles_and_reassemble.sh <input> <rows> <cols> <scale_int> <output> [work_dir] [crf] [preset]
# Example: ./upscale_video_by_tiles_and_reassemble.sh input.mp4 3 3 2 output_2x.mp4
#
# Notes:
# - scale_int must be a positive integer (2 = 2x, 3 = 3x, etc).
# - Uses lossless FFV1 for tile intermediates by default.
# - Final output encoding uses libx264 with CRF/PRESET you pass.
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input="${1:-}"
rows="${2:-}"
cols="${3:-}"
scale_int="${4:-}"
output="${5:-}"
work_dir="${6:-}"
crf="${7:-10}"
preset="${8:-slow}"

if [[ -z "$input" || -z "$rows" || -z "$cols" || -z "$scale_int" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <rows> <cols> <scale_int> <output> [work_dir] [crf] [preset]"
  exit 1
fi

if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

if ! [[ "$rows" =~ ^[0-9]+$ ]] || ! [[ "$cols" =~ ^[0-9]+$ ]] || ! [[ "$scale_int" =~ ^[0-9]+$ ]]; then
  echo "Error: rows, cols, and scale_int must be positive integers." >&2
  exit 1
fi

if (( rows < 1 || cols < 1 || scale_int < 1 )); then
  echo "Error: rows, cols, and scale_int must be >= 1." >&2
  exit 1
fi

if [[ -z "$work_dir" ]]; then
  base="$(basename "$input")"
  base="${base%.*}"
  work_dir="${base}_tile_upscale_${rows}x${cols}_${scale_int}x"
fi

split_script="${script_dir}/split_video_into_tiles_high_quality.sh"
reassemble_script="${script_dir}/reassemble_video_from_tiles_blackout.sh"

if [[ ! -x "$split_script" ]]; then
  echo "Error: missing executable split script: $split_script" >&2
  exit 1
fi
if [[ ! -x "$reassemble_script" ]]; then
  echo "Error: missing executable reassemble script: $reassemble_script" >&2
  exit 1
fi

orig_tiles_dir="${work_dir}/tiles_original"
up_tiles_dir="${work_dir}/tiles_upscaled"
orig_manifest="${orig_tiles_dir}/tiles_manifest.tsv"
up_manifest="${work_dir}/tiles_manifest_upscaled.tsv"

mkdir -p "$orig_tiles_dir" "$up_tiles_dir"

echo "[1/4] Splitting source into tiles..."
TILE_CODEC="ffv1" "$split_script" "$input" "$rows" "$cols" "$orig_tiles_dir"

if [[ ! -f "$orig_manifest" ]]; then
  echo "Error: original manifest not found: $orig_manifest" >&2
  exit 1
fi

declare -a tile_row
declare -a tile_col
declare -a tile_x
declare -a tile_y
declare -a tile_w
declare -a tile_h
declare -a tile_file

manifest_rows=""
manifest_cols=""
manifest_width=""
manifest_height=""
manifest_tile_count=""

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  if [[ "$line" == *=* ]]; then
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      rows) manifest_rows="$value" ;;
      cols) manifest_cols="$value" ;;
      width) manifest_width="$value" ;;
      height) manifest_height="$value" ;;
      tile_count) manifest_tile_count="$value" ;;
    esac
    continue
  fi

  if [[ "$line" == tile$'\t'* ]]; then
    IFS=$'\t' read -r tag idx row col x y w h file <<< "$line"
    if [[ "$idx" == "idx" ]]; then
      continue
    fi
    if ! [[ "$idx" =~ ^[0-9]+$ && "$row" =~ ^[0-9]+$ && "$col" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ && "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]]; then
      continue
    fi
    tile_row[$idx]="$row"
    tile_col[$idx]="$col"
    tile_x[$idx]="$x"
    tile_y[$idx]="$y"
    tile_w[$idx]="$w"
    tile_h[$idx]="$h"
    tile_file[$idx]="$file"
  fi
done < "$orig_manifest"

if [[ -z "$manifest_rows" || -z "$manifest_cols" || -z "$manifest_width" || -z "$manifest_height" || -z "$manifest_tile_count" ]]; then
  echo "Error: missing core fields in manifest: $orig_manifest" >&2
  exit 1
fi

scaled_width=$((manifest_width * scale_int))
scaled_height=$((manifest_height * scale_int))
scaled_tile_count="$manifest_tile_count"

{
  echo "# spatial-tiles-manifest-v1"
  echo "input=${input}"
  echo "rows=${manifest_rows}"
  echo "cols=${manifest_cols}"
  echo "width=${scaled_width}"
  echo "height=${scaled_height}"
  echo "tile_count=${scaled_tile_count}"
  printf "tile\tidx\trow\tcol\tx\ty\tw\th\tfile\n"
} > "$up_manifest"

echo "[2/4] Upscaling each tile by ${scale_int}x..."
for ((i=0; i<scaled_tile_count; i++)); do
  if [[ -z "${tile_file[$i]:-}" ]]; then
    echo "Error: missing tile index $i in original manifest." >&2
    exit 1
  fi

  src_tile="${orig_tiles_dir}/${tile_file[$i]}"
  dst_tile="${up_tiles_dir}/${tile_file[$i]}"

  if [[ ! -f "$src_tile" ]]; then
    echo "Error: source tile missing: $src_tile" >&2
    exit 1
  fi

  out_w=$((tile_w[$i] * scale_int))
  out_h=$((tile_h[$i] * scale_int))
  out_x=$((tile_x[$i] * scale_int))
  out_y=$((tile_y[$i] * scale_int))

  ffmpeg -hide_banner -nostdin -y \
    -i "$src_tile" \
    -map 0:v:0 -an -sn \
    -vf "scale=${out_w}:${out_h}:flags=lanczos" \
    -c:v ffv1 -level 3 \
    "$dst_tile"

  printf "tile\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$i" "${tile_row[$i]}" "${tile_col[$i]}" "$out_x" "$out_y" "$out_w" "$out_h" "${tile_file[$i]}" >> "$up_manifest"
done

echo "[3/4] Reassembling upscaled tiles..."
CRF="$crf" PRESET="$preset" PIX_FMT="${PIX_FMT:-yuv444p}" \
  "$reassemble_script" "$up_manifest" "$output" "" "$input" "$up_tiles_dir"

echo "[4/4] Done."
echo "Output video: $output"
echo "Work directory: $work_dir"
echo "Upscaled manifest: $up_manifest"
