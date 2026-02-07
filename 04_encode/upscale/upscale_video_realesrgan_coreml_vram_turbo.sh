#!/usr/bin/env bash
# Mac VRAM/GPU-focused turbo wrapper for tiled CoreML upscale.
# Usage: ./upscale_video_realesrgan_coreml_vram_turbo.sh <input> [output] [model_path] [work_dir] [rows] [cols]
#
# Defaults prioritize speed:
# - CoreML compute units: cpu_and_gpu
# - Intermediate tile encode: ffv1 (lossless) by default
# - Final reassembly encode: h264_videotoolbox
# - Low overlap and auto-tuned TILE_JOBS/FRAME_WORKERS/FRAME_MAX_INFLIGHT values
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input="${1:-}"
output="${2:-}"
model_path="${3:-RealESRGAN_x4.mlpackage}"
work_dir="${4:-}"
rows="${5:-}"
cols="${6:-}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [model_path] [work_dir] [rows] [cols]"
  exit 1
fi

tiled_script="${script_dir}/upscale_video_realesrgan_coreml_x2_tiled.sh"
if [[ ! -x "$tiled_script" ]]; then
  echo "Error: required script missing/executable: $tiled_script" >&2
  exit 2
fi

for tool in ffmpeg ffprobe python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool missing from PATH: $tool" >&2
    exit 2
  fi
done

if ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])h264_videotoolbox([[:space:]]|$)'; then
  if [[ "${ALLOW_LOSSY_INTERMEDIATE:-0}" == "1" ]]; then
    inter_codec="${INTERMEDIATE_CODEC:-h264_videotoolbox}"
  else
    inter_codec="${INTERMEDIATE_CODEC:-ffv1}"
  fi
  final_codec="${V_CODEC:-h264_videotoolbox}"
else
  inter_codec="${INTERMEDIATE_CODEC:-libx264}"
  final_codec="${V_CODEC:-libx264}"
fi

logical_cpu="$(sysctl -n hw.logicalcpu 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 8)"
if ! [[ "$logical_cpu" =~ ^[0-9]+$ ]]; then
  logical_cpu=8
fi

compute_units="${COMPUTE_UNITS:-cpu_and_gpu}"
model_color_order="${MODEL_COLOR_ORDER:-rgb}"
target_upscale="${TARGET_UPSCALE:-2}"
overlap="${OVERLAP:-8}"
if [[ -n "${TILE_JOBS:-}" ]]; then
  tile_jobs="$TILE_JOBS"
else
  if (( logical_cpu >= 16 )); then
    tile_jobs=3
  elif (( logical_cpu >= 8 )); then
    tile_jobs=2
  else
    tile_jobs=1
  fi
fi
if [[ -n "${FRAME_WORKERS:-}" ]]; then
  frame_workers="$FRAME_WORKERS"
else
  if (( tile_jobs >= 3 )); then
    frame_workers=2
  elif (( tile_jobs == 2 )); then
    frame_workers=3
  else
    frame_workers=4
  fi
fi
frame_inflight="${FRAME_MAX_INFLIGHT:-$((frame_workers * 4))}"
target_tile_size="${TARGET_TILE_SIZE:-4096}"

if [[ -n "${INTERMEDIATE_PIX_FMT:-}" ]]; then
  inter_pix_fmt="$INTERMEDIATE_PIX_FMT"
elif [[ "$inter_codec" == "ffv1" ]]; then
  inter_pix_fmt="gbrp"
else
  inter_pix_fmt="yuv420p"
fi
inter_bitrate="${INTERMEDIATE_BITRATE:-24M}"
inter_maxrate="${INTERMEDIATE_MAXRATE:-24M}"
inter_bufsize="${INTERMEDIATE_BUFSIZE:-48M}"
inter_realtime="${INTERMEDIATE_REALTIME:-true}"

final_pix_fmt="${FINAL_PIX_FMT:-yuv420p}"
final_bitrate="${V_BITRATE:-24M}"
final_maxrate="${V_MAXRATE:-24M}"
final_bufsize="${V_BUFSIZE:-48M}"
final_realtime="${V_REALTIME:-true}"
final_allow_sw="${V_ALLOW_SW:-1}"

# Keep low-latency x264 fallback settings reasonable if videotoolbox is unavailable.
crf="${CRF:-20}"
preset="${PRESET:-veryfast}"

echo "Turbo profile:"
echo "  logical_cpu: ${logical_cpu}"
echo "  compute    : ${compute_units}"
echo "  target_up  : ${target_upscale}x"
echo "  tile_jobs  : ${tile_jobs}"
echo "  workers    : ${frame_workers}"
echo "  inflight   : ${frame_inflight}"
echo "  tile_size  : ${target_tile_size}"
echo "  inter_codec: ${inter_codec}"
echo "  final_codec: ${final_codec}"

COMPUTE_UNITS="$compute_units" \
MODEL_COLOR_ORDER="$model_color_order" \
TARGET_UPSCALE="$target_upscale" \
OVERLAP="$overlap" \
TILE_JOBS="$tile_jobs" \
FRAME_WORKERS="$frame_workers" \
FRAME_MAX_INFLIGHT="$frame_inflight" \
TARGET_TILE_SIZE="$target_tile_size" \
INTERMEDIATE_CODEC="$inter_codec" \
INTERMEDIATE_PIX_FMT="$inter_pix_fmt" \
INTERMEDIATE_BITRATE="$inter_bitrate" \
INTERMEDIATE_MAXRATE="$inter_maxrate" \
INTERMEDIATE_BUFSIZE="$inter_bufsize" \
INTERMEDIATE_REALTIME="$inter_realtime" \
FINAL_PIX_FMT="$final_pix_fmt" \
V_CODEC="$final_codec" \
V_BITRATE="$final_bitrate" \
V_MAXRATE="$final_maxrate" \
V_BUFSIZE="$final_bufsize" \
V_REALTIME="$final_realtime" \
V_ALLOW_SW="$final_allow_sw" \
"$tiled_script" "$input" "$output" "$model_path" "$work_dir" "$overlap" "$crf" "$preset" "$rows" "$cols"
