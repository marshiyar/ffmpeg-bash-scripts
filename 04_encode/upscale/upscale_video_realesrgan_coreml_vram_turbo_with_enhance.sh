#!/usr/bin/env bash
# Chain runner:
# 1) Existing VRAM turbo upscale pipeline
# 2) Secondary FFmpeg enhancement flow (CAS + denoise/deband/detail polish)
#
# Usage:
#   ./upscale_video_realesrgan_coreml_vram_turbo_with_enhance.sh <input> [output] [model_path] [enhance_profile] [work_dir] [rows] [cols]
#
# Defaults:
#   model_path=RealESRGAN_x4.mlpackage
#   enhance_profile=balanced
#   output=<input>_turbo_enhanced.mp4
#
# Env:
#   ENHANCE_CODEC=libx264
#   ENHANCE_QUALITY=16
#   ENHANCE_PRESET=slow
#   KEEP_STAGE1=0
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

input="${1:-}"
output="${2:-}"
model_path="${3:-RealESRGAN_x4.mlpackage}"
enhance_profile="${4:-balanced}"
work_dir="${5:-}"
rows="${6:-}"
cols="${7:-}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [model_path] [enhance_profile] [work_dir] [rows] [cols]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${input%.*}_turbo_enhanced.mp4"
fi

base_name="$(basename "${input%.*}")"
if [[ -z "$work_dir" ]]; then
  work_dir="${base_name}_turbo_enhance_work"
fi
mkdir -p "$work_dir"

stage1_output="${work_dir}/stage1_turbo_upscaled.mp4"

turbo_script="${script_dir}/upscale_video_realesrgan_coreml_vram_turbo.sh"
enhance_script="${script_dir}/enhance_video_look_secondary_flow.sh"

if [[ ! -x "$turbo_script" ]]; then
  echo "Error: missing executable script: $turbo_script" >&2
  exit 2
fi
if [[ ! -x "$enhance_script" ]]; then
  echo "Error: missing executable script: $enhance_script" >&2
  exit 2
fi

enhance_codec="${ENHANCE_CODEC:-libx264}"
enhance_quality="${ENHANCE_QUALITY:-16}"
enhance_preset="${ENHANCE_PRESET:-slow}"
keep_stage1="${KEEP_STAGE1:-0}"

echo "[1/2] Running turbo upscale stage ..."
"$turbo_script" "$input" "$stage1_output" "$model_path" "$work_dir" "$rows" "$cols"

echo "[2/2] Running enhancement stage (${enhance_profile}) ..."
"$enhance_script" "$stage1_output" "$output" "$enhance_profile" "$enhance_codec" "$enhance_quality" "$enhance_preset"

if [[ "$keep_stage1" != "1" ]]; then
  rm -f "$stage1_output"
fi

echo "Done. Final output: $output"
if [[ "$keep_stage1" == "1" ]]; then
  echo "Stage 1 output kept: $stage1_output"
fi
