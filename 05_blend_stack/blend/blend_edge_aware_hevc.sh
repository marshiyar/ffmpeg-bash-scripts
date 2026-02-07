#!/usr/bin/env bash
# Edge-aware merge: unsharp + edgedetect mask + hqdn3d + maskedmerge, then HEVC.
# Usage: ./merge_edge_aware_to_hevc.sh <input_a> <input_b> [output] [crf] [preset]
set -euo pipefail

script_name="$(basename "$0")"

input_a="${1:-}"
input_b="${2:-}"
if [[ -z "$input_a" || -z "$input_b" ]]; then
  echo "Usage: ${script_name} <input_a> <input_b> [output] [crf] [preset]"
  exit 1
fi

base_a="$(basename "$input_a")"
base_a="${base_a%.*}"
base_b="$(basename "$input_b")"
base_b="${base_b%.*}"

output="${3:-${base_a}_${base_b}_edge_aware_hevc.mp4}"
crf="${4:-10}"
preset="${5:-fast}"
pix_fmt="${PIX_FMT:-yuv420p10le}"

ffmpeg -hide_banner -nostdin -y -i "$input_a" -i "$input_b" -filter_complex "
  [0:v]unsharp=5:5:0.4:5:5:0.3[a_sharp];
  [a_sharp]format=gray,edgedetect=low=0.08:high=0.16,normalize=blackpt=0:whitept=1,boxblur=2:1[mask];
  [1:v]hqdn3d=0.6:0.6:1.2:1.2[b_clean];
  [a_sharp][b_clean][mask]maskedmerge[v]
" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v libx265 -pix_fmt "$pix_fmt" -preset "$preset" -crf "$crf" \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 -tag:v hvc1 \
  -movflags +faststart "$output"
