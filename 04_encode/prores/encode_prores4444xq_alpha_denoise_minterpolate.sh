#!/usr/bin/env bash
# ProRes 4444 XQ with alpha: denoise, decimate, minterpolate, nlmeans, deband.
# Usage: ./encode_prores4444xq_alpha_denoise_minterpolate.sh <input> <output> [fps]
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
if [[ -z "$input" || -z "$output" ]]; then
  echo "Usage: ${script_name} <input> <output> [fps]"
  exit 1
fi

fps="${3:-60}"

ffmpeg -hide_banner -nostdin -y -i "$input" \
  -vf "format=yuva444p16le, \
    hqdn3d=0.6:0.6:1.2:1.2, \
    mpdecimate=hi=64*12,setpts=N/FRAME_RATE/TB, \
    minterpolate=fps=${fps}:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1, \
    nlmeans=s=1:p=3:r=3, \
    deband, \
    unsharp=5:5:0.5:5:5:0.4, \
    noise=alls=1:allf=u+t, \
    limiter=min=16:max=235:planes=0+1+2,setsar=1, \
    format=yuva444p10le" \
  -c:v prores_ks -profile:v 5 -pix_fmt yuva444p10le \
  -vendor apl0 -bits_per_mb 10000 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -c:a copy -movflags +faststart \
  "$output"
