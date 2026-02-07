#!/usr/bin/env bash
# Four inputs -> 2x2 grid via hstack then vstack (top row = [0][1], bottom = [2][3]).
# Usage: ./stack_2x2_hstack_vstack.sh <input0> <input1> <input2> <input3> <output> [width] [height]
# Env: AUDIO_MAP=first|all|none (default: first)
set -euo pipefail

script_name="$(basename "$0")"

in0="${1:-}"
in1="${2:-}"
in2="${3:-}"
in3="${4:-}"
out="${5:-}"
if [[ -z "$in0" || -z "$in1" || -z "$in2" || -z "$in3" || -z "$out" ]]; then
  echo "Usage: ${script_name} <input0> <input1> <input2> <input3> <output> [width] [height]"
  exit 1
fi

width="${6:-}"
height="${7:-}"
if [[ -z "$width" || -z "$height" ]]; then
  if ! command -v ffprobe >/dev/null 2>&1; then
    echo "ffprobe is required to auto-detect width/height. Provide them explicitly." >&2
    exit 1
  fi
  width="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$in0")"
  height="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "$in0")"
fi

audio_map="${AUDIO_MAP:-first}"
audio_args=()
if [[ "$audio_map" == "all" ]]; then
  audio_args+=( -map 0:a? -map 1:a? -map 2:a? -map 3:a? )
elif [[ "$audio_map" == "first" ]]; then
  audio_args+=( -map 0:a? )
fi

ffmpeg -hide_banner -nostdin -y -i "$in0" -i "$in1" -i "$in2" -i "$in3" \
  -filter_complex "
  [0:v]setpts=PTS-STARTPTS,scale=${width}:${height},setsar=1[v0];
  [1:v]setpts=PTS-STARTPTS,scale=${width}:${height},setsar=1[v1];
  [2:v]setpts=PTS-STARTPTS,scale=${width}:${height},setsar=1[v2];
  [3:v]setpts=PTS-STARTPTS,scale=${width}:${height},setsar=1[v3];
  [v0][v1]hstack=inputs=2[top];
  [v2][v3]hstack=inputs=2[bottom];
  [top][bottom]vstack=inputs=2[grid]
" \
  -map "[grid]" "${audio_args[@]}" \
  -c:v libx264 -crf 18 -preset medium -ac 2 \
  "$out"
