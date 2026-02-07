#!/usr/bin/env bash
# Parallel blend pipeline: Lanczos + Spline36 blended, then denoise, HEVC.
# Usage: ./pipeline_parallel_blend_hevc.sh <input> <output> [crf] [preset]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output> [crf] [preset]"
  exit 1
fi

crf="${3:-6}"
preset="${4:-slow}"

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -filter_complex "
  [0:v]format=yuv444p16le,zscale=transferin=bt709:transfer=linear,split=2[a][b];
  [a]zscale=w=ceil(iw*2/2)*2:h=ceil(ih*2/2)*2:filter=lanczos:param_a=4[aL];
  [b]zscale=w=ceil(iw*2/2)*2:h=ceil(ih*2/2)*2:filter=spline36[bs];
  [aL][bs]blend=all_mode=average:all_opacity=0.6[mix];
  [mix]hqdn3d=1.2:1.2:3:3,nlmeans=s=3:p=5:r=5,deband,gradfun=4:10,unsharp=7:7:1.2:7:7:0.8,
  zscale=transfer=bt709,limiter=min=16:max=235:planes=0+1+2,format=yuv420p10le[v]
" \
  -map "[v]" -map 0:a? -c:a copy \
  -c:v libx265 -preset "$preset" -crf "$crf" -pix_fmt yuv420p10le \
  -x265-params "aq-mode=3:aq-strength=0.9:rc-lookahead=40:bframes=8:b-adapt=2:psy-rd=2.2:psy-rdoq=1.0" \
  -tag:v hvc1 -movflags +faststart "$output"
