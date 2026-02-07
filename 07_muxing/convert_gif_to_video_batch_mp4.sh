#!/usr/bin/env bash
# Batch convert GIF files to MP4 video.
# Usage: ./convert_gif_to_video_batch_mp4.sh "<glob>" [out_dir] [fps] [crf] [preset]
# Example: ./convert_gif_to_video_batch_mp4.sh "*.gif" "gif_videos" 30 18 medium
set -euo pipefail

script_name="$(basename "$0")"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shopt -s nullglob

pattern="${1:-}"
out_dir="${2:-.}"
fps="${3:-30}"
crf="${4:-18}"
preset="${5:-medium}"

if [[ -z "$pattern" ]]; then
  echo "Usage: ${script_name} \"<glob>\" [out_dir] [fps] [crf] [preset]"
  exit 1
fi

files=( $pattern )
if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files matched: $pattern"
  exit 1
fi

mkdir -p "$out_dir"
single_script="${script_dir}/convert_gif_to_video_mp4.sh"
if [[ ! -x "$single_script" ]]; then
  echo "Error: missing executable script: $single_script" >&2
  exit 2
fi

converted=0
skipped=0

for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue

  ext="${f##*.}"
  ext="$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
  if [[ "$ext" != "gif" ]]; then
    echo "Skip (not GIF): $f"
    skipped=$((skipped + 1))
    continue
  fi

  base="$(basename "$f")"
  base="${base%.*}"
  out="${out_dir}/${base}_from_gif.mp4"

  if [[ -e "$out" ]]; then
    echo "Skip (exists): $out"
    skipped=$((skipped + 1))
    continue
  fi

  "$single_script" "$f" "$out" "$fps" "$crf" "$preset"
  converted=$((converted + 1))
done

echo "Batch conversion complete. Converted: ${converted}, Skipped: ${skipped}"
