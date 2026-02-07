#!/usr/bin/env bash
# Secondary FFmpeg visual enhancement flow intended to run after upscale.
# Usage:
#   ./enhance_video_look_secondary_flow.sh <input> [output] [profile] [codec] [quality] [preset]
# Profiles:
#   - subtle   : light cleanup + mild sharpness
#   - balanced : cleanup + CAS + gentle detail boost (default)
#   - crisp    : stronger edge/detail pop
#   - smooth   : stronger smoothing with controlled sharpness
# Codec/quality rules:
#   - libx264/libx265: quality=CRF (lower = higher quality, default 16)
#   - *_videotoolbox: quality=bitrate (default 20M)
# Env:
#   PIX_FMT=yuv420p
#   AUDIO_MODE=copy|aac        (default: copy)
#   AUDIO_BITRATE=192k         (used when AUDIO_MODE=aac)
#   V_MAXRATE=20M              (for *_videotoolbox; default=quality)
#   V_BUFSIZE=40M              (optional for *_videotoolbox)
#   V_REALTIME=false           (for *_videotoolbox)
#   V_ALLOW_SW=1               (for *_videotoolbox)
#   EXTRA_VF="..."             (append custom filters at end)
set -euo pipefail

script_name="$(basename "$0")"

input="${1:-}"
output="${2:-}"
profile="${3:-balanced}"
codec="${4:-libx264}"
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
  ext="${input##*.}"
  output="${input%.*}_enhanced_${profile}.${ext}"
fi

if [[ -z "$quality" ]]; then
  if [[ "$codec" == *_videotoolbox ]]; then
    quality="20M"
  else
    quality="16"
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

declare -a vf_parts
declare -a used_filters
declare -a missing_filters

add_if_available() {
  local filter_name="$1"
  local expr="$2"
  if has_filter "$filter_name"; then
    vf_parts+=("$expr")
    used_filters+=("$filter_name")
  else
    missing_filters+=("$filter_name")
  fi
}

case "$profile" in
  subtle)
    add_if_available "hqdn3d" "hqdn3d=luma_spatial=1.1:chroma_spatial=0.8:luma_tmp=3.0:chroma_tmp=2.2"
    add_if_available "deband" "deband=1thr=0.010:2thr=0.010:3thr=0.010:range=10:blur=1:coupling=1"
    add_if_available "cas" "cas=strength=0.20"
    add_if_available "eq" "eq=contrast=1.01:saturation=1.015"
    ;;
  balanced)
    add_if_available "hqdn3d" "hqdn3d=luma_spatial=1.6:chroma_spatial=1.2:luma_tmp=4.5:chroma_tmp=3.2"
    add_if_available "deband" "deband=1thr=0.012:2thr=0.012:3thr=0.012:range=14:blur=1:coupling=1"
    add_if_available "cas" "cas=strength=0.35"
    add_if_available "unsharp" "unsharp=lx=5:ly=5:la=0.40:cx=3:cy=3:ca=0.00"
    add_if_available "eq" "eq=contrast=1.03:saturation=1.03:gamma=0.99"
    ;;
  crisp)
    add_if_available "hqdn3d" "hqdn3d=luma_spatial=0.8:chroma_spatial=0.6:luma_tmp=2.0:chroma_tmp=1.4"
    add_if_available "deband" "deband=1thr=0.009:2thr=0.009:3thr=0.009:range=10:blur=1:coupling=1"
    add_if_available "cas" "cas=strength=0.55"
    add_if_available "unsharp" "unsharp=lx=5:ly=5:la=0.80:cx=3:cy=3:ca=0.00"
    add_if_available "eq" "eq=contrast=1.04:saturation=1.04"
    ;;
  smooth)
    add_if_available "atadenoise" "atadenoise=0a=0.03:0b=0.06:1a=0.03:1b=0.06:2a=0.03:2b=0.06:s=9:a=p"
    add_if_available "hqdn3d" "hqdn3d=luma_spatial=2.2:chroma_spatial=1.8:luma_tmp=6.0:chroma_tmp=4.5"
    add_if_available "deband" "deband=1thr=0.015:2thr=0.015:3thr=0.015:range=16:blur=1:coupling=1"
    add_if_available "cas" "cas=strength=0.18"
    add_if_available "unsharp" "unsharp=lx=5:ly=5:la=0.22:cx=3:cy=3:ca=0.00"
    add_if_available "eq" "eq=contrast=1.01:saturation=1.02"
    ;;
  *)
    echo "Error: unsupported profile '${profile}'. Use: subtle|balanced|crisp|smooth" >&2
    exit 1
    ;;
esac

if [[ -n "${EXTRA_VF:-}" ]]; then
  vf_parts+=("${EXTRA_VF}")
fi

if [[ ${#vf_parts[@]} -eq 0 ]]; then
  echo "Error: no enhancement filters available on this FFmpeg build." >&2
  exit 2
fi

vf_chain="$(IFS=,; echo "${vf_parts[*]}")"

pix_fmt="${PIX_FMT:-yuv420p}"
audio_mode="${AUDIO_MODE:-copy}"
audio_bitrate="${AUDIO_BITRATE:-192k}"
v_maxrate="${V_MAXRATE:-$quality}"
v_bufsize="${V_BUFSIZE:-}"
v_realtime="${V_REALTIME:-false}"
v_allow_sw="${V_ALLOW_SW:-1}"

cmd=(ffmpeg -hide_banner -nostdin -y -i "$input" -map 0:v:0 -vf "$vf_chain")

case "$codec" in
  libx264|libx265)
    cmd+=( -c:v "$codec" -crf "$quality" -preset "$preset" -pix_fmt "$pix_fmt" )
    ;;
  *_videotoolbox)
    cmd+=( -c:v "$codec" -b:v "$quality" -maxrate "$v_maxrate" -pix_fmt "$pix_fmt" -realtime "$v_realtime" -allow_sw "$v_allow_sw" )
    if [[ -n "$v_bufsize" ]]; then
      cmd+=( -bufsize "$v_bufsize" )
    fi
    if [[ "$codec" == "h264_videotoolbox" ]]; then
      cmd+=( -tag:v avc1 )
    elif [[ "$codec" == "hevc_videotoolbox" ]]; then
      cmd+=( -tag:v hvc1 )
    elif [[ "$codec" == "av1_videotoolbox" ]]; then
      cmd+=( -tag:v av01 )
    fi
    ;;
  ffv1)
    cmd+=( -c:v ffv1 -level 3 -pix_fmt "${pix_fmt:-yuv444p}" )
    ;;
  *)
    cmd+=( -c:v "$codec" -pix_fmt "$pix_fmt" )
    ;;
esac

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

echo "Secondary enhancement flow:"
echo "  Input   : $input"
echo "  Output  : $output"
echo "  Profile : $profile"
echo "  Codec   : $codec"
echo "  Quality : $quality"
echo "  Preset  : $preset"
echo "  Filters : $vf_chain"
if [[ ${#missing_filters[@]} -gt 0 ]]; then
  uniq_missing="$(printf '%s\n' "${missing_filters[@]}" | sort -u | tr '\n' ',' | sed 's/,$//')"
  echo "  Note    : skipped unavailable filters -> ${uniq_missing}"
fi

"${cmd[@]}"

echo "Done: $output"
