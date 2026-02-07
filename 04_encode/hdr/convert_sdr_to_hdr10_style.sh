#!/usr/bin/env bash
# Convert SDR video to an HDR10-style deliverable using an FFmpeg filter pipeline.
# Usage:
#   ./convert_sdr_to_hdr10_style.sh <input> [output] [profile] [codec] [quality] [preset]
# Defaults:
#   profile=natural, codec=libx265
#
# Profiles:
#   - natural  : very light touch, closest to source look
#   - gentle   : mild SDR->HDR look lift
#   - balanced : moderate enhancement
#   - punchy   : stronger contrast/saturation/sharpness
#
# Codec/quality rules:
#   - libx265: quality = CRF (default 18)
#   - hevc_videotoolbox: quality = bitrate (default 18M)
#
# Notes:
# - This is an HDR10-style up-conversion pipeline, not true HDR scene reconstruction.
# - It cannot recover clipped SDR highlights that are already lost in the source.
# - For a less dark look, keep HDR_TRANSFER=bt2020-10 (default).
#
# Env:
#   INPUT_ALL=bt709
#   PIX_FMT=yuv420p10le
#   HDR_TRANSFER=bt2020-10|smpte2084  (default: bt2020-10)
#   AUDIO_MODE=copy|aac         (default: copy)
#   AUDIO_BITRATE=192k          (used when AUDIO_MODE=aac)
#   ENABLE_TONEMAP=0            (set 1 to enable extra dynamic-range remap step)
#   PEAK_NITS=1000              (used when ENABLE_TONEMAP=1)
#   MASTER_DISPLAY=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)
#   MAX_CLL=1000,400
#   VT_MAXRATE=<bitrate>        (default: quality when codec is hevc_videotoolbox)
#   VT_BUFSIZE=36M
#   VT_REALTIME=false
#   VT_ALLOW_SW=1
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
profile="${3:-natural}"
codec="${4:-libx265}"
quality="${5:-}"
preset="${6:-slow}"

if [[ -z "$input" ]]; then
  echo "Usage: ${script_name} <input> [output] [profile] [codec] [quality] [preset]"
  exit 1
fi
if [[ ! -f "$input" ]]; then
  echo "Error: input not found: $input" >&2
  exit 1
fi

if [[ -z "$output" ]]; then
  output="${input%.*}_hdr10_style.mp4"
fi

if [[ -z "$quality" ]]; then
  if [[ "$codec" == "hevc_videotoolbox" ]]; then
    quality="18M"
  else
    quality="18"
  fi
fi

for tool in ffmpeg ffprobe; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool missing from PATH: $tool" >&2
    exit 2
  fi
done

available_filters="$(ffmpeg -hide_banner -filters 2>/dev/null || true)"
has_filter() {
  local filter_name="$1"
  echo "$available_filters" | grep -Eq "(^|[[:space:]])${filter_name}([[:space:]]|$)"
}

if ! has_filter "colorspace"; then
  echo "Error: ffmpeg build is missing required 'colorspace' filter." >&2
  exit 2
fi
if ! has_filter "eq"; then
  echo "Error: ffmpeg build is missing required 'eq' filter." >&2
  exit 2
fi
if ! has_filter "curves"; then
  echo "Error: ffmpeg build is missing required 'curves' filter." >&2
  exit 2
fi

denoise_expr=""
deband_expr=""
cas_expr=""
eq_expr=""
curves_points=""
tonemap_param=""
tonemap_desat=""

case "$profile" in
  natural)
    denoise_expr="hqdn3d=luma_spatial=0.8:chroma_spatial=0.6:luma_tmp=1.8:chroma_tmp=1.2"
    deband_expr="deband=1thr=0.008:2thr=0.008:3thr=0.008:range=8:blur=1:coupling=1"
    cas_expr="cas=strength=0.08"
    eq_expr="eq=contrast=1.01:saturation=1.01:gamma=1.00"
    curves_points="0/0 0.25/0.25 0.50/0.50 0.75/0.75 1/1"
    tonemap_param="0.15"
    tonemap_desat="0.0"
    ;;
  gentle)
    denoise_expr="hqdn3d=luma_spatial=1.0:chroma_spatial=0.8:luma_tmp=2.4:chroma_tmp=1.8"
    deband_expr="deband=1thr=0.009:2thr=0.009:3thr=0.009:range=10:blur=1:coupling=1"
    cas_expr="cas=strength=0.14"
    eq_expr="eq=contrast=1.02:saturation=1.03:gamma=1.00"
    curves_points="0/0 0.35/0.35 0.70/0.72 1/1"
    tonemap_param="0.20"
    tonemap_desat="0.0"
    ;;
  balanced)
    denoise_expr="hqdn3d=luma_spatial=1.3:chroma_spatial=1.0:luma_tmp=3.6:chroma_tmp=2.7"
    deband_expr="deband=1thr=0.011:2thr=0.011:3thr=0.011:range=12:blur=1:coupling=1"
    cas_expr="cas=strength=0.24"
    eq_expr="eq=contrast=1.04:saturation=1.06:gamma=0.99"
    curves_points="0/0 0.38/0.36 0.72/0.80 1/1"
    tonemap_param="0.24"
    tonemap_desat="0.0"
    ;;
  punchy)
    denoise_expr="hqdn3d=luma_spatial=0.9:chroma_spatial=0.7:luma_tmp=2.0:chroma_tmp=1.4"
    deband_expr="deband=1thr=0.009:2thr=0.009:3thr=0.009:range=10:blur=1:coupling=1"
    cas_expr="cas=strength=0.45"
    eq_expr="eq=contrast=1.10:saturation=1.14:gamma=0.94"
    curves_points="0/0 0.36/0.29 0.70/0.88 1/1"
    tonemap_param="0.28"
    tonemap_desat="0.0"
    ;;
  *)
    echo "Error: unsupported profile '${profile}'. Use: natural|gentle|balanced|punchy" >&2
    exit 1
    ;;
esac

input_all="${INPUT_ALL:-bt709}"
pix_fmt="${PIX_FMT:-yuv420p10le}"
hdr_transfer="${HDR_TRANSFER:-bt2020-10}"
if [[ "$hdr_transfer" != "bt2020-10" && "$hdr_transfer" != "smpte2084" ]]; then
  echo "Error: HDR_TRANSFER must be bt2020-10 or smpte2084." >&2
  exit 1
fi
audio_mode="${AUDIO_MODE:-copy}"
audio_bitrate="${AUDIO_BITRATE:-192k}"

enable_tonemap="${ENABLE_TONEMAP:-0}"
peak_nits="${PEAK_NITS:-1000}"

master_display="${MASTER_DISPLAY:-G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)L(10000000,1)}"
max_cll="${MAX_CLL:-1000,400}"

declare -a vf_parts
declare -a notes

vf_parts+=( "format=yuv444p16le" )
vf_parts+=( "colorspace=iall=${input_all}:space=bt2020nc:primaries=bt2020:trc=bt2020-10:range=tv:dither=fsb" )

if [[ "$enable_tonemap" == "1" ]]; then
  if has_filter "tonemap"; then
    vf_parts+=( "format=gbrpf32le" )
    vf_parts+=( "tonemap=tonemap=mobius:param=${tonemap_param}:desat=${tonemap_desat}:peak=${peak_nits}" )
    vf_parts+=( "format=yuv444p16le" )
    notes+=( "tonemap=enabled" )
  else
    notes+=( "tonemap requested but filter unavailable; skipped" )
  fi
fi

if has_filter "hqdn3d"; then
  vf_parts+=( "$denoise_expr" )
else
  notes+=( "hqdn3d unavailable; skipped denoise" )
fi

if has_filter "deband"; then
  vf_parts+=( "$deband_expr" )
else
  notes+=( "deband unavailable; skipped deband" )
fi

vf_parts+=( "curves=master='${curves_points}'" )
vf_parts+=( "$eq_expr" )

if has_filter "cas"; then
  vf_parts+=( "$cas_expr" )
else
  notes+=( "cas unavailable; skipped CAS sharpening" )
fi

vf_parts+=( "format=${pix_fmt}" )

vf_chain="$(IFS=,; echo "${vf_parts[*]}")"

cmd=(ffmpeg -hide_banner -nostdin -y -i "$input" -map 0:v:0 -vf "$vf_chain")

case "$codec" in
  libx265)
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])libx265([[:space:]]|$)'; then
      echo "Error: ffmpeg build does not include libx265 encoder." >&2
      exit 2
    fi
    x265_params=(
      "repeat-headers=1"
      "colorprim=bt2020"
      "transfer=${hdr_transfer}"
      "colormatrix=bt2020nc"
    )
    if [[ "$hdr_transfer" == "smpte2084" ]]; then
      x265_params+=( "hdr10=1" "hdr10-opt=1" "master-display=${master_display}" "max-cll=${max_cll}" )
    fi
    x265_params_str="$(IFS=:; echo "${x265_params[*]}")"

    cmd+=( -c:v libx265 -preset "$preset" -crf "$quality" -pix_fmt "$pix_fmt" -x265-params "$x265_params_str" )
    ;;
  hevc_videotoolbox)
    if ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -Eq '(^|[[:space:]])hevc_videotoolbox([[:space:]]|$)'; then
      echo "Error: ffmpeg build does not include hevc_videotoolbox encoder." >&2
      exit 2
    fi
    vt_maxrate="${VT_MAXRATE:-$quality}"
    vt_bufsize="${VT_BUFSIZE:-36M}"
    vt_realtime="${VT_REALTIME:-false}"
    vt_allow_sw="${VT_ALLOW_SW:-1}"

    cmd+=( -c:v hevc_videotoolbox -b:v "$quality" -maxrate "$vt_maxrate" -bufsize "$vt_bufsize" -pix_fmt "$pix_fmt" -allow_sw "$vt_allow_sw" -realtime "$vt_realtime" -tag:v hvc1 )
    ;;
  *)
    echo "Error: unsupported codec '${codec}'. Use libx265 or hevc_videotoolbox." >&2
    exit 1
    ;;
esac

cmd+=( -color_primaries bt2020 -color_trc "$hdr_transfer" -colorspace bt2020nc )

case "$audio_mode" in
  copy)
    cmd+=( -map 0:a? -c:a copy )
    ;;
  aac)
    cmd+=( -map 0:a? -c:a aac -b:a "$audio_bitrate" -ac 2 -ar 48000 )
    ;;
  *)
    echo "Error: AUDIO_MODE must be 'copy' or 'aac'." >&2
    exit 1
    ;;
esac

if [[ "$output" == *.mp4 ]]; then
  cmd+=( -movflags +faststart )
fi
cmd+=( "$output" )

echo "SDR->HDR10-style pipeline:"
echo "  Input    : $input"
echo "  Output   : $output"
echo "  Profile  : $profile"
echo "  Codec    : $codec"
echo "  Quality  : $quality"
echo "  Preset   : $preset"
echo "  VF chain : $vf_chain"
if [[ ${#notes[@]} -gt 0 ]]; then
  echo "  Notes    : $(IFS='; '; echo "${notes[*]}")"
fi

"${cmd[@]}"

echo "Done: $output"
