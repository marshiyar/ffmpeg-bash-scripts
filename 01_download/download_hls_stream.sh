#!/usr/bin/env bash
# Download an HLS stream URL to a local media file without re-encoding.
# Usage: ./download_hls_stream.sh <hls_url> <output_file>
set -euo pipefail

script_name="$(basename "$0")"

hls_url="${1:-}"
output_file="${2:-}"

if [[ -z "$hls_url" || -z "$output_file" ]]; then
  echo "Usage: ${script_name} <hls_url> <output_file>"
  exit 1
fi

ffmpeg -hide_banner -nostdin -y \
  -i "$hls_url" \
  -c copy \
  "$output_file"
