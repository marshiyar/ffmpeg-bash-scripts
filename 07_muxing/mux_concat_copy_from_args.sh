#!/usr/bin/env bash
# Concatenate files (same stream parameters) using concat demuxer + stream copy.
# Usage: ./mux_concat_copy_from_args.sh <output> <input1> <input2> [inputN...]
set -euo pipefail

script_name="$(basename "$0")"

output="${1:-}"
if [[ -z "$output" || "$#" -lt 3 ]]; then
  echo "Usage: ${script_name} <output> <input1> <input2> [inputN...]"
  exit 1
fi

shift
inputs=("$@")

list_file="$(mktemp "${TMPDIR:-/tmp}/ffmpeg_concat_list.XXXXXX")"
cleanup() {
  rm -f "$list_file"
}
trap cleanup EXIT

for input_file in "${inputs[@]}"; do
  escaped="${input_file//\'/\'\\\'\'}"
  printf "file '%s'\n" "$escaped" >> "$list_file"
done

ffmpeg -hide_banner -nostdin -y \
  -f concat -safe 0 -i "$list_file" \
  -c copy \
  "$output"
