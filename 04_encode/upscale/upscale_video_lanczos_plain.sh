#!/usr/bin/env bash
# Plain non-AI, non-tiling Lanczos upscale (no interpolation, no ProRes-specific path).
# Usage:
#   ./upscale_video_lanczos_plain.sh <input> [output] [scale_factor] [codec] [quality] [preset]
#
# Defaults:
#   output=<input>_lanczos_2x.mp4
#   scale_factor=2
#   codec=libx264
#   quality=18
#   preset=medium
#
# Codec rules:
# - libx264/libx265: quality = CRF
# - *_videotoolbox: quality = bitrate (e.g. 12M)
# - ffv1: quality/preset ignored
#
# Env:
#   PIX_FMT=yuv420p
#   V_MAXRATE=<bitrate>     (for *_videotoolbox; default=quality)
#   V_BUFSIZE=24M           (for *_videotoolbox)
#   V_REALTIME=false        (for *_videotoolbox)
#   V_ALLOW_SW=1            (for *_videotoolbox)
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
scale_factor="${3:-2}"
codec="${4:-libx264}"
quality="${5:-18}"
preset="${6:-medium}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [scale_factor] [codec] [quality] [preset]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

if ! [[ "$scale_factor" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Error: scale_factor must be a positive number (example: 2 or 1.5)." >&2
  exit 1
fi
if awk "BEGIN{exit !($scale_factor > 0)}"; then :; else
  echo "Error: scale_factor must be > 0." >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  scale_label="${scale_factor//./p}"
  output="${input%.*}_lanczos_${scale_label}x.mp4"
fi

pix_fmt="${PIX_FMT:-yuv420p}"
v_maxrate="${V_MAXRATE:-$quality}"
v_bufsize="${V_BUFSIZE:-24M}"
v_realtime="${V_REALTIME:-false}"
v_allow_sw="${V_ALLOW_SW:-1}"

vf_chain="scale=trunc(iw*${scale_factor}/2)*2:trunc(ih*${scale_factor}/2)*2:flags=lanczos,setsar=1"

cmd=(ffmpeg -hide_banner -nostdin -y -i "$input" -map 0 -vf "$vf_chain")

case "$codec" in
  libx264|libx265)
    cmd+=( -c:v "$codec" -crf "$quality" -preset "$preset" -pix_fmt "$pix_fmt" )
    if [[ "$codec" == "libx264" ]]; then
      cmd+=( -tag:v avc1 )
    elif [[ "$codec" == "libx265" ]]; then
      cmd+=( -tag:v hvc1 )
    fi
    ;;
  *_videotoolbox)
    cmd+=( -c:v "$codec" -b:v "$quality" -maxrate "$v_maxrate" -bufsize "$v_bufsize" -pix_fmt "$pix_fmt" -allow_sw "$v_allow_sw" -realtime "$v_realtime" )
    if [[ "$codec" == "h264_videotoolbox" ]]; then
      cmd+=( -tag:v avc1 )
    elif [[ "$codec" == "hevc_videotoolbox" ]]; then
      cmd+=( -tag:v hvc1 )
    elif [[ "$codec" == "av1_videotoolbox" ]]; then
      cmd+=( -tag:v av01 )
    fi
    ;;
  ffv1)
    cmd+=( -c:v ffv1 -level 3 -pix_fmt "${PIX_FMT:-yuv444p}" )
    ;;
  *)
    cmd+=( -c:v "$codec" -pix_fmt "$pix_fmt" )
    ;;
esac

cmd+=( -c:a copy -c:s copy )

if [[ "$output" == *.mp4 ]]; then
  cmd+=( -movflags +faststart )
fi
cmd+=( "$output" )

echo "Plain Lanczos upscale:"
echo "  Input  : $input"
echo "  Output : $output"
echo "  Scale  : ${scale_factor}x"
echo "  Codec  : $codec"
echo "  Filter : $vf_chain"

"${cmd[@]}"

echo "Done: $output"
