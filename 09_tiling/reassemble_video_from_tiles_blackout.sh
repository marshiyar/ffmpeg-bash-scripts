#!/usr/bin/env bash
# Reassemble tiled video exactly from manifest, with optional blacked-out tile blocks.
# Usage: ./reassemble_video_from_tiles_blackout.sh <manifest> <output> [black_tiles_csv] [audio_source] [tiles_dir]
# black_tiles_csv tokens:
#   - tile index: "3,5,8"
#   - row:col (0-based): "0:1,1:2"
# Defaults: audio_source=manifest input (if available), tiles_dir=manifest directory
set -euo pipefail

script_name="$(basename "$0")"

manifest="${1:-}"
output="${2:-}"
black_tiles_csv="${3:-}"
audio_source_arg="${4:-}"
tiles_dir_arg="${5:-}"

if [[ -z "$manifest" || -z "$output" ]]; then
  echo "Usage: ${script_name} <manifest> <output> [black_tiles_csv] [audio_source] [tiles_dir]"
  exit 1
fi

if [[ ! -f "$manifest" ]]; then
  echo "Error: manifest not found: $manifest" >&2
  exit 1
fi

manifest_dir="$(cd "$(dirname "$manifest")" && pwd)"
tiles_dir="${tiles_dir_arg:-$manifest_dir}"
if [[ ! -d "$tiles_dir" ]]; then
  echo "Error: tiles_dir not found: $tiles_dir" >&2
  exit 1
fi

rows=""
cols=""
tile_count=""
manifest_input=""

declare -a tile_x
declare -a tile_y
declare -a tile_w
declare -a tile_h
declare -a tile_file

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  [[ "$line" == \#* ]] && continue

  if [[ "$line" == *=* ]]; then
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      rows) rows="$value" ;;
      cols) cols="$value" ;;
      tile_count) tile_count="$value" ;;
      input) manifest_input="$value" ;;
    esac
    continue
  fi

  if [[ "$line" == tile$'\t'* ]]; then
    IFS=$'\t' read -r tag idx row col x y w h file <<< "$line"
    # Skip header-like or malformed lines safely.
    if [[ "$idx" == "idx" ]]; then
      continue
    fi
    if ! [[ "$idx" =~ ^[0-9]+$ && "$x" =~ ^[0-9]+$ && "$y" =~ ^[0-9]+$ && "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ && -n "$file" ]]; then
      echo "Warning: skipping malformed manifest line: $line" >&2
      continue
    fi
    tile_x[$idx]="$x"
    tile_y[$idx]="$y"
    tile_w[$idx]="$w"
    tile_h[$idx]="$h"
    tile_file[$idx]="$file"
  fi
done < "$manifest"

if [[ -z "$rows" || -z "$cols" || -z "$tile_count" ]]; then
  echo "Error: manifest missing rows/cols/tile_count." >&2
  exit 1
fi

expected=$((rows * cols))
if [[ "$tile_count" -ne "$expected" ]]; then
  echo "Error: manifest tile_count=${tile_count} does not match rows*cols=${expected}." >&2
  exit 1
fi

for ((i=0; i<tile_count; i++)); do
  if [[ -z "${tile_file[$i]:-}" ]]; then
    echo "Error: missing tile entry for index $i in manifest." >&2
    exit 1
  fi
  if [[ ! -f "${tiles_dir}/${tile_file[$i]}" ]]; then
    echo "Error: missing tile file: ${tiles_dir}/${tile_file[$i]}" >&2
    exit 1
  fi
  actual_w="$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "${tiles_dir}/${tile_file[$i]}")"
  actual_h="$(ffprobe -v error -select_streams v:0 -show_entries stream=height -of csv=p=0 "${tiles_dir}/${tile_file[$i]}")"
  if [[ -z "$actual_w" || -z "$actual_h" ]]; then
    echo "Error: failed to read dimensions for tile file: ${tiles_dir}/${tile_file[$i]}" >&2
    exit 1
  fi
  if [[ "$actual_w" -ne "${tile_w[$i]}" || "$actual_h" -ne "${tile_h[$i]}" ]]; then
    echo "Error: tile dimension mismatch at index $i (${tiles_dir}/${tile_file[$i]})." >&2
    echo "Manifest expects ${tile_w[$i]}x${tile_h[$i]}, actual is ${actual_w}x${actual_h}." >&2
    echo "Re-split tiles with default lossless mode (TILE_CODEC=ffv1) to guarantee seam-safe rebuild." >&2
    exit 1
  fi
done

normalize_token_to_index() {
  local token="$1"
  token="$(echo "$token" | tr -d '[:space:]')"
  if [[ -z "$token" ]]; then
    return 1
  fi

  if [[ "$token" == *:* ]]; then
    local rpart="${token%%:*}"
    local cpart="${token##*:}"
    if ! [[ "$rpart" =~ ^[0-9]+$ ]] || ! [[ "$cpart" =~ ^[0-9]+$ ]]; then
      return 1
    fi
    if (( rpart < 0 || rpart >= rows || cpart < 0 || cpart >= cols )); then
      return 1
    fi
    echo $((rpart * cols + cpart))
    return 0
  fi

  if [[ "$token" =~ ^[0-9]+$ ]]; then
    if (( token < 0 || token >= tile_count )); then
      return 1
    fi
    echo "$token"
    return 0
  fi

  return 1
}

declare -a black_indices
if [[ -n "$black_tiles_csv" ]]; then
  old_ifs="$IFS"
  IFS=','
  for token in $black_tiles_csv; do
    idx="$(normalize_token_to_index "$token" || true)"
    if [[ -z "$idx" ]]; then
      echo "Error: invalid black tile token '$token'. Use index or row:col (0-based)." >&2
      exit 1
    fi
    black_indices+=("$idx")
  done
  IFS="$old_ifs"
fi

is_black_index() {
  local idx="$1"
  local b
  for b in "${black_indices[@]:-}"; do
    if [[ "$b" == "$idx" ]]; then
      return 0
    fi
  done
  return 1
}

audio_source="$audio_source_arg"
if [[ -z "$audio_source" && -n "$manifest_input" && -f "$manifest_input" ]]; then
  audio_source="$manifest_input"
fi

if (( tile_count == 1 )) && [[ -z "$black_tiles_csv" ]]; then
  single_tile_path="${tiles_dir}/${tile_file[0]}"
  copy_cmd=(ffmpeg -hide_banner -nostdin -y -i "$single_tile_path")
  if [[ -n "$audio_source" && -f "$audio_source" ]]; then
    copy_cmd+=( -i "$audio_source" -map 0:v:0 -map 1:a? -c:v copy -c:a copy -shortest )
  else
    copy_cmd+=( -map 0:v:0 -c:v copy )
  fi
  if [[ "$output" == *.mp4 ]]; then
    copy_cmd+=( -movflags +faststart )
  fi
  copy_cmd+=( "$output" )

  if "${copy_cmd[@]}"; then
    echo "Done. Reassembled output: $output"
    echo "Single-tile fast path used (stream copy)."
    exit 0
  fi

  echo "Warning: single-tile stream copy failed, falling back to filtered re-encode." >&2
fi

cmd=(ffmpeg -hide_banner -nostdin -y)
for ((i=0; i<tile_count; i++)); do
  cmd+=( -i "${tiles_dir}/${tile_file[$i]}" )
done

have_audio=0
audio_input_idx=-1
if [[ -n "$audio_source" ]]; then
  if [[ -f "$audio_source" ]]; then
    cmd+=( -i "$audio_source" )
    have_audio=1
    audio_input_idx=$tile_count
  else
    echo "Warning: audio source not found, continuing without audio: $audio_source" >&2
  fi
fi

filter_chains=""
stack_inputs=""
layout=""

for ((i=0; i<tile_count; i++)); do
  if [[ -n "$filter_chains" ]]; then
    filter_chains+=";"
  fi

  if is_black_index "$i"; then
    filter_chains+="[${i}:v]setpts=PTS-STARTPTS,drawbox=x=0:y=0:w=iw:h=ih:color=black:t=fill[v${i}]"
  else
    filter_chains+="[${i}:v]setpts=PTS-STARTPTS[v${i}]"
  fi

  stack_inputs+="[v${i}]"

  if [[ -n "$layout" ]]; then
    layout+="|"
  fi
  layout+="${tile_x[$i]}_${tile_y[$i]}"
done

if (( tile_count == 1 )); then
  filter_complex="${filter_chains};[v0]null[vout]"
else
  filter_complex="${filter_chains};${stack_inputs}xstack=inputs=${tile_count}:layout=${layout}[vout]"
fi

cmd+=( -filter_complex "$filter_complex" -map "[vout]" )
if [[ $have_audio -eq 1 ]]; then
  cmd+=( -map "${audio_input_idx}:a?" -c:a copy -shortest )
fi

v_codec="${V_CODEC:-libx264}"
v_pix_fmt="${PIX_FMT:-yuv444p}"
v_crf="${CRF:-10}"
v_preset="${PRESET:-slow}"
v_bitrate="${V_BITRATE:-12M}"
v_maxrate="${V_MAXRATE:-$v_bitrate}"
v_bufsize="${V_BUFSIZE:-}"
v_realtime="${V_REALTIME:-false}"
v_allow_sw="${V_ALLOW_SW:-1}"

if [[ "$v_codec" == "libx264" || "$v_codec" == "libx265" ]]; then
  cmd+=( -c:v "$v_codec" -crf "$v_crf" -preset "$v_preset" -pix_fmt "$v_pix_fmt" )
elif [[ "$v_codec" == *_videotoolbox ]]; then
  cmd+=( -c:v "$v_codec" -b:v "$v_bitrate" -maxrate "$v_maxrate" -pix_fmt "$v_pix_fmt" -realtime "$v_realtime" -allow_sw "$v_allow_sw" )
  if [[ -n "$v_bufsize" ]]; then
    cmd+=( -bufsize "$v_bufsize" )
  fi
  if [[ "$v_codec" == "h264_videotoolbox" ]]; then
    cmd+=( -tag:v avc1 )
  elif [[ "$v_codec" == "hevc_videotoolbox" ]]; then
    cmd+=( -tag:v hvc1 )
  elif [[ "$v_codec" == "av1_videotoolbox" ]]; then
    cmd+=( -tag:v av01 )
  fi
elif [[ "$v_codec" == "ffv1" ]]; then
  cmd+=( -c:v ffv1 -level 3 -pix_fmt "$v_pix_fmt" )
else
  cmd+=( -c:v "$v_codec" -pix_fmt "$v_pix_fmt" )
fi

if [[ "$output" == *.mp4 ]]; then
  cmd+=( -movflags +faststart )
fi
cmd+=( "$output" )

"${cmd[@]}"

echo "Done. Reassembled output: $output"
if [[ -n "$black_tiles_csv" ]]; then
  echo "Black tiles applied: $black_tiles_csv"
fi
