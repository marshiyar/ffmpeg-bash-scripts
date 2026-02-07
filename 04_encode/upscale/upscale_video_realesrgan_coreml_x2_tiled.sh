#!/usr/bin/env bash
# Upscale a video by 2x using RealESRGAN CoreML with explicit video-tile workflow.
# Usage: ./upscale_video_realesrgan_coreml_x2_tiled.sh <input> [output] [model_path] [work_dir] [overlap] [crf] [preset] [rows] [cols]
#
# Pipeline:
# 1) Split source into tile video pieces (.mkv) + manifest.
# 2) Extract tile frames and run CoreML upscale per tile.
# 3) Reassemble upscaled tile videos seam-free.
# Fast path:
# - If rows=1 and cols=1, skip split/reassemble and run direct tiled inference on full video.
#
# Defaults:
# - model_path: <repo_root>/models/RealESRGAN_x2.mlpackage
# - overlap: 32
# - final output: libx264 crf=18 preset=slow
# - rows/cols auto-selected from source dimensions and TARGET_TILE_SIZE (default: 256)
#
# Env:
# - TARGET_TILE_SIZE=256               (auto grid sizing target)
# - COMPUTE_UNITS=all                 (all|cpu_only|cpu_and_gpu|cpu_and_ne)
# - MODEL_COLOR_ORDER=rgb|bgr         (set bgr if model expects BGR channel order)
# - TARGET_UPSCALE=0                  (0=model-native, 2 forces 2x final output even on x4 model)
# - INTERMEDIATE_CODEC=ffv1           (tile-upscaled intermediates; ffv1 recommended)
# - INTERMEDIATE_CRF=0                (used by x264/x265 intermediate codecs)
# - INTERMEDIATE_PRESET=veryslow      (used by x264/x265 intermediate codecs)
# - INTERMEDIATE_BITRATE=12M          (used by *_videotoolbox intermediate codecs)
# - INTERMEDIATE_MAXRATE=12M
# - INTERMEDIATE_BUFSIZE=24M
# - INTERMEDIATE_REALTIME=false       (used by *_videotoolbox intermediate codecs)
# - INTERMEDIATE_PIX_FMT=gbrp
# - KEEP_TILE_FRAME_WORK=0            (set 1 to keep per-tile frame folders)
# - TILE_JOBS=1                       (number of tile videos to upscale in parallel)
# - FINAL_PIX_FMT=yuv420p
# - V_CODEC=libx264|h264_videotoolbox|hevc_videotoolbox|... (final reassembly codec)
# - V_BITRATE=16M                     (for *_videotoolbox final codec)
# - V_MAXRATE=16M
# - V_BUFSIZE=32M
# - V_REALTIME=false
# - V_ALLOW_SW=1                      (allow software fallback for *_videotoolbox final codec)
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"

input="${1:-}"
output="${2:-}"
model_path="${3:-${repo_root}/models/RealESRGAN_x2.mlpackage}"
work_dir="${4:-}"
overlap="${5:-32}"
crf="${6:-18}"
preset="${7:-slow}"
rows="${8:-}"
cols="${9:-}"

resolve_model_path() {
  local candidate="$1"
  if [[ -e "$candidate" ]]; then
    echo "$candidate"
    return 0
  fi
  if [[ -e "${repo_root}/models/${candidate}" ]]; then
    echo "${repo_root}/models/${candidate}"
    return 0
  fi
  if [[ "$candidate" != *.mlpackage ]] && [[ -e "${repo_root}/models/${candidate}.mlpackage" ]]; then
    echo "${repo_root}/models/${candidate}.mlpackage"
    return 0
  fi
  return 1
}

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [model_path] [work_dir] [overlap] [crf] [preset] [rows] [cols]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi
model_path="$(resolve_model_path "$model_path" || true)"
if [[ -z "$model_path" || ! -e "$model_path" ]]; then
  echo "Error: model not found: $model_path" >&2
  echo "Tip: pass a full path or a name from ./models, e.g. RealESRGAN_x4_int4_lut.mlpackage" >&2
  exit 1
fi
if ! [[ "$overlap" =~ ^[0-9]+$ ]]; then
  echo "Error: overlap must be a non-negative integer" >&2
  exit 1
fi
if (( overlap >= 256 )); then
  echo "Error: overlap must be less than 256" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${input%.*}_realesrgan_coreml_x2_tiled.mp4"
fi
if [[ -z "$work_dir" ]]; then
  base="$(basename "$input")"
  base="${base%.*}"
  work_dir="${base}_realesrgan_coreml_x2_tiled_work"
fi

for tool in ffmpeg ffprobe python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool missing from PATH: $tool" >&2
    exit 2
  fi
done

runner="${script_dir}/realesrgan_coreml_x2_runner.py"
split_script="${repo_root}/scripts/09_tiling/split_video_into_tiles_high_quality.sh"
reassemble_script="${repo_root}/scripts/09_tiling/reassemble_video_from_tiles_blackout.sh"
if [[ ! -f "$runner" ]]; then
  echo "Error: runner not found: $runner" >&2
  exit 2
fi
if [[ ! -x "$split_script" ]]; then
  echo "Error: split script missing or not executable: $split_script" >&2
  exit 2
fi
if [[ ! -x "$reassemble_script" ]]; then
  echo "Error: reassemble script missing or not executable: $reassemble_script" >&2
  exit 2
fi

target_tile_size="${TARGET_TILE_SIZE:-256}"
if ! [[ "$target_tile_size" =~ ^[0-9]+$ ]] || (( target_tile_size < 1 )); then
  echo "Error: TARGET_TILE_SIZE must be a positive integer." >&2
  exit 1
fi

src_w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$input")"
src_h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$input")"
if [[ -z "$src_w" || -z "$src_h" ]]; then
  echo "Error: failed to read source dimensions." >&2
  exit 1
fi

if [[ -z "$rows" ]]; then
  rows=$(( (src_h + target_tile_size - 1) / target_tile_size ))
fi
if [[ -z "$cols" ]]; then
  cols=$(( (src_w + target_tile_size - 1) / target_tile_size ))
fi
if ! [[ "$rows" =~ ^[0-9]+$ ]] || ! [[ "$cols" =~ ^[0-9]+$ ]] || (( rows < 1 || cols < 1 )); then
  echo "Error: rows/cols must be positive integers." >&2
  exit 1
fi

compute_units="${COMPUTE_UNITS:-all}"
model_color_order="${MODEL_COLOR_ORDER:-rgb}"
target_upscale="${TARGET_UPSCALE:-0}"
intermediate_codec="${INTERMEDIATE_CODEC:-ffv1}"
intermediate_crf="${INTERMEDIATE_CRF:-0}"
intermediate_preset="${INTERMEDIATE_PRESET:-veryslow}"
intermediate_bitrate="${INTERMEDIATE_BITRATE:-}"
intermediate_maxrate="${INTERMEDIATE_MAXRATE:-}"
intermediate_bufsize="${INTERMEDIATE_BUFSIZE:-}"
intermediate_realtime="${INTERMEDIATE_REALTIME:-false}"
intermediate_pix_fmt="${INTERMEDIATE_PIX_FMT:-gbrp}"
final_pix_fmt="${FINAL_PIX_FMT:-${PIX_FMT:-yuv420p}}"
keep_tile_frame_work="${KEEP_TILE_FRAME_WORK:-0}"
tile_jobs="${TILE_JOBS:-1}"

if ! [[ "$tile_jobs" =~ ^[0-9]+$ ]] || (( tile_jobs < 1 )); then
  echo "Error: TILE_JOBS must be a positive integer." >&2
  exit 1
fi

if (( rows == 1 && cols == 1 )); then
  echo "[1/1] Single-tile direct path (skip split/reassemble) ..."
  coreml_tmp="${COREML_TMP_DIR:-${work_dir}/coreml_tmp}"
  mkdir -p "$coreml_tmp"

  final_codec="${V_CODEC:-libx264}"
  final_bitrate="${V_BITRATE:-12M}"
  final_maxrate="${V_MAXRATE:-}"
  final_bufsize="${V_BUFSIZE:-}"
  final_realtime="${V_REALTIME:-false}"

  direct_cmd=(
    python3 "$runner"
    --input "$input"
    --output "$output"
    --model "$model_path"
    --work-dir "$work_dir"
    --mode tiled
    --overlap "$overlap"
    --target-upscale "$target_upscale"
    --model-color-order "$model_color_order"
    --compute-units "$compute_units"
    --codec "$final_codec"
    --crf "$crf"
    --preset "$preset"
    --pix-fmt "$final_pix_fmt"
  )
  if [[ -n "$final_bitrate" ]]; then
    direct_cmd+=(--video-bitrate "$final_bitrate")
  fi
  if [[ -n "$final_maxrate" ]]; then
    direct_cmd+=(--video-maxrate "$final_maxrate")
  fi
  if [[ -n "$final_bufsize" ]]; then
    direct_cmd+=(--video-bufsize "$final_bufsize")
  fi
  direct_cmd+=(--videotoolbox-realtime "$final_realtime")
  if [[ "$keep_tile_frame_work" == "1" || "${KEEP_WORK:-0}" == "1" ]]; then
    direct_cmd+=(--keep-work)
  fi

  TMPDIR="$coreml_tmp" "${direct_cmd[@]}"
  echo "Done. Output: $output"
  echo "Work directory: $work_dir"
  exit 0
fi

orig_tiles_dir="${work_dir}/tiles_original"
up_tiles_dir="${work_dir}/tiles_upscaled"
orig_manifest="${orig_tiles_dir}/tiles_manifest.tsv"
up_manifest="${work_dir}/tiles_manifest_upscaled.tsv"
coreml_tmp_root="${COREML_TMP_DIR:-${work_dir}/coreml_tmp}"
tile_work_root="${work_dir}/coreml_tile_work"
up_parts_dir="${work_dir}/up_manifest_parts"
tile_logs_dir="${work_dir}/tile_logs"

mkdir -p "$orig_tiles_dir" "$up_tiles_dir" "$coreml_tmp_root" "$tile_work_root" "$up_parts_dir" "$tile_logs_dir"

echo "[1/4] Splitting source into tile videos (.mkv) ..."
echo "Grid: ${rows}x${cols} (source ${src_w}x${src_h}, target tile size ${target_tile_size})"
TILE_CODEC=ffv1 "$split_script" "$input" "$rows" "$cols" "$orig_tiles_dir"

if [[ ! -f "$orig_manifest" ]]; then
  echo "Error: expected manifest missing: $orig_manifest" >&2
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

echo "[2/4] Upscaling each tile video with CoreML ..."
echo "Tile jobs   : ${tile_jobs}"

run_one_tile() {
  local i="$1"
  local src_tile dst_file dst_tile tile_work tile_tmp log_file part_file tmp_part
  local actual_w actual_h scale_x scale_y out_x out_y out_w out_h

  if [[ -z "${tile_file[$i]:-}" ]]; then
    echo "Error: missing tile index $i in original manifest." >&2
    return 1
  fi

  src_tile="${orig_tiles_dir}/${tile_file[$i]}"
  if [[ ! -f "$src_tile" ]]; then
    echo "Error: source tile missing: $src_tile" >&2
    return 1
  fi

  dst_file="${tile_file[$i]}"
  dst_tile="${up_tiles_dir}/${dst_file}"
  tile_work="${tile_work_root}/tile_$(printf '%04d' "$i")"
  tile_tmp="${coreml_tmp_root}/tile_$(printf '%04d' "$i")"
  log_file="${tile_logs_dir}/tile_$(printf '%04d' "$i").log"
  part_file="${up_parts_dir}/tile_$(printf '%04d' "$i").line"
  tmp_part="${part_file}.tmp"
  mkdir -p "$tile_work" "$tile_tmp"

  cmd=(
    python3 "$runner"
    --input "$src_tile"
    --output "$dst_tile"
    --model "$model_path"
    --work-dir "$tile_work"
    --mode tiled
    --overlap "$overlap"
    --target-upscale "$target_upscale"
    --model-color-order "$model_color_order"
    --compute-units "$compute_units"
    --codec "$intermediate_codec"
    --crf "$intermediate_crf"
    --preset "$intermediate_preset"
    --pix-fmt "$intermediate_pix_fmt"
  )
  if [[ -n "$intermediate_bitrate" ]]; then
    cmd+=(--video-bitrate "$intermediate_bitrate")
  fi
  if [[ -n "$intermediate_maxrate" ]]; then
    cmd+=(--video-maxrate "$intermediate_maxrate")
  fi
  if [[ -n "$intermediate_bufsize" ]]; then
    cmd+=(--video-bufsize "$intermediate_bufsize")
  fi
  cmd+=(--videotoolbox-realtime "$intermediate_realtime")
  if [[ "$keep_tile_frame_work" == "1" ]]; then
    cmd+=(--keep-work)
  fi

  if ! TMPDIR="$tile_tmp" "${cmd[@]}" >"$log_file" 2>&1; then
    echo "Tile $i failed. See log: $log_file" >&2
    return 1
  fi

  actual_w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$dst_tile")"
  actual_h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$dst_tile")"
  if [[ -z "$actual_w" || -z "$actual_h" ]]; then
    echo "Error: failed to probe upscaled tile dimensions: $dst_tile" >&2
    return 1
  fi
  if (( tile_w[$i] <= 0 || tile_h[$i] <= 0 )); then
    echo "Error: invalid source tile dimensions at index $i." >&2
    return 1
  fi
  if (( actual_w % tile_w[$i] != 0 || actual_h % tile_h[$i] != 0 )); then
    echo "Error: non-integer tile scale at index $i (${tile_w[$i]}x${tile_h[$i]} -> ${actual_w}x${actual_h})." >&2
    return 1
  fi

  scale_x=$((actual_w / tile_w[$i]))
  scale_y=$((actual_h / tile_h[$i]))
  out_x=$((tile_x[$i] * scale_x))
  out_y=$((tile_y[$i] * scale_y))
  out_w="$actual_w"
  out_h="$actual_h"

  printf "tile\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$i" "${tile_row[$i]}" "${tile_col[$i]}" "$out_x" "$out_y" "$out_w" "$out_h" "$dst_file" > "$tmp_part"
  mv "$tmp_part" "$part_file"
  echo "  tile $i done"
}

active_pids=()
failed_tiles=0

for ((i=0; i<manifest_tile_count; i++)); do
  run_one_tile "$i" &
  active_pids+=("$!")

  if (( ${#active_pids[@]} >= tile_jobs )); then
    oldest_pid="${active_pids[0]}"
    if ! wait "$oldest_pid"; then
      failed_tiles=1
    fi
    active_pids=("${active_pids[@]:1}")
  fi
done

for pid in "${active_pids[@]}"; do
  if ! wait "$pid"; then
    failed_tiles=1
  fi
done

if (( failed_tiles != 0 )); then
  echo "Error: one or more tile jobs failed. Check logs in: $tile_logs_dir" >&2
  exit 1
fi

scaled_width=0
scaled_height=0
for ((i=0; i<manifest_tile_count; i++)); do
  part_file="${up_parts_dir}/tile_$(printf '%04d' "$i").line"
  if [[ ! -f "$part_file" ]]; then
    echo "Error: missing upscaled tile manifest part: $part_file" >&2
    exit 1
  fi
  IFS=$'\t' read -r _tag _idx _row _col ox oy ow oh _file < "$part_file"
  right=$((ox + ow))
  bottom=$((oy + oh))
  if (( right > scaled_width )); then
    scaled_width="$right"
  fi
  if (( bottom > scaled_height )); then
    scaled_height="$bottom"
  fi
done

{
  echo "# spatial-tiles-manifest-v1"
  echo "input=${input}"
  echo "rows=${manifest_rows}"
  echo "cols=${manifest_cols}"
  echo "width=${scaled_width}"
  echo "height=${scaled_height}"
  echo "tile_count=${manifest_tile_count}"
  printf "tile\tidx\trow\tcol\tx\ty\tw\th\tfile\n"
} > "$up_manifest"

for ((i=0; i<manifest_tile_count; i++)); do
  cat "${up_parts_dir}/tile_$(printf '%04d' "$i").line" >> "$up_manifest"
done

echo "[3/4] Reassembling upscaled tiles ..."
CRF="$crf" PRESET="$preset" PIX_FMT="$final_pix_fmt" \
V_CODEC="${V_CODEC:-libx264}" V_BITRATE="${V_BITRATE:-12M}" V_MAXRATE="${V_MAXRATE:-}" V_BUFSIZE="${V_BUFSIZE:-}" V_REALTIME="${V_REALTIME:-false}" \
  "$reassemble_script" "$up_manifest" "$output" "" "$input" "$up_tiles_dir"

echo "[4/4] Done."
echo "Output: $output"
echo "Work directory: $work_dir"
echo "Original tile manifest: $orig_manifest"
echo "Upscaled tile manifest: $up_manifest"
