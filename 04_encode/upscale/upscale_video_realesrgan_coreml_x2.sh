#!/usr/bin/env bash
# Upscale a video by 2x using RealESRGAN CoreML model (non-tiled path).
# Usage: ./upscale_video_realesrgan_coreml_x2.sh <input> [output] [model_path] [work_dir] [crf] [preset]
#
# Notes:
# - Model default: <repo_root>/models/RealESRGAN_x2.mlpackage
# - Non-tiled mode requires source frames to be 256x256 unless FORCE_RESIZE_TO_MODEL=1.
# - For arbitrary resolutions, use the tiled companion script.
# Env:
# - MODEL_COLOR_ORDER=rgb|bgr
# - TARGET_UPSCALE=0                  (0=model-native, 2 forces 2x final output even on x4 model)
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"

input="${1:-}"
output="${2:-}"
model_path="${3:-${repo_root}/models/RealESRGAN_x2.mlpackage}"
work_dir="${4:-}"
crf="${5:-18}"
preset="${6:-slow}"

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
  echo "Usage: ${script_name} <input> [output] [model_path] [work_dir] [crf] [preset]"
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

if [[ -z "$output" ]]; then
  output="${input%.*}_realesrgan_coreml_x2.mp4"
fi
if [[ -z "$work_dir" ]]; then
  base="$(basename "$input")"
  base="${base%.*}"
  work_dir="${base}_realesrgan_coreml_x2_work"
fi
coreml_tmp="${COREML_TMP_DIR:-${work_dir}/coreml_tmp}"
mkdir -p "$coreml_tmp"

for tool in ffmpeg ffprobe python3; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool missing from PATH: $tool" >&2
    exit 2
  fi
done

runner="${script_dir}/realesrgan_coreml_x2_runner.py"
if [[ ! -f "$runner" ]]; then
  echo "Error: runner not found: $runner" >&2
  exit 2
fi

compute_units="${COMPUTE_UNITS:-all}"
model_color_order="${MODEL_COLOR_ORDER:-rgb}"
target_upscale="${TARGET_UPSCALE:-0}"
pix_fmt="${PIX_FMT:-yuv420p}"

cmd=(
  python3 "$runner"
  --input "$input" \
  --output "$output" \
  --model "$model_path" \
  --work-dir "$work_dir" \
  --mode full \
  --target-upscale "$target_upscale" \
  --model-color-order "$model_color_order" \
  --compute-units "$compute_units" \
  --codec libx264 \
  --crf "$crf" \
  --preset "$preset" \
  --pix-fmt "$pix_fmt"
)

if [[ "${FORCE_RESIZE_TO_MODEL:-0}" == "1" ]]; then
  cmd+=(--force-resize)
fi

if [[ "${KEEP_WORK:-0}" == "1" ]]; then
  cmd+=(--keep-work)
fi

TMPDIR="$coreml_tmp" "${cmd[@]}"
