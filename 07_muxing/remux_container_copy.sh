#!/usr/bin/env bash
# Remux a file into a new container without re-encoding streams.
# Usage: ./remux_container_copy.sh <input> <output>
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"

if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output>"
  exit 1
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$input" \
  -map 0 -c copy \
  "$output"
