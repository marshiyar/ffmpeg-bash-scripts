#!/usr/bin/env bash
set -euo pipefail

script_name="$(basename "$0")"

if [[ $# -lt 1 ]]; then
  echo "Usage: ${script_name} <input_video> [output_dir]"
  exit 1
fi

in="$1"
outdir="${2:-$(dirname "$in")}"

if [[ ! -f "$in" ]]; then
  echo "Error: input file not found: $in"
  exit 1
fi

mkdir -p "$outdir"
base="$(basename "$in")"
base="${base%.*}"
ts="$(date +%Y%m%d-%H%M%S)"
out="${outdir}/${base}_up2x60p_ProRes422_${ts}.mov"

echo "Input : $in"
echo "Output: $out"
echo "Running…"

ffmpeg -hide_banner -stats -y \
  -i "$in" \
  -vf 'scale=iw*2:ih*2:flags=lanczos,
hqdn3d=0.6:0.6:1.2:1.2,
minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir,
unsharp=5:5:0.5,
eq=contrast=1.05:brightness=0.01:saturation=1.1,
limiter=min=16:max=235:planes=0+1+2,
setsar=1,
format=yuv422p10le' \
  -c:v prores_ks -profile:v 2 -pix_fmt yuv422p10le -vendor apl0 \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -c:a pcm_s16le -ar 48000 -movflags +faststart \
  "$out"

echo "Done → $out"
