#!/usr/bin/env bash
# Build GIF comparisons (single, triptych, sweep) for 3 input videos across common analysis filters.
# Usage: ./gif_three_video_filter_suite.sh <video1> <video2> <video3> [out_dir]
# Env (optional): FPS, SEGMENT_SECONDS, SINGLE_WIDTH, TRIPTYCH_WIDTH, DITHER, PALETTE_STATS,
#                 FONTFILE, FONTNAME, FONTSIZE, BOX_OPACITY, BOX_BORDER
set -euo pipefail

script_name="$(basename "$0")"

video1="${1:-}"
video2="${2:-}"
video3="${3:-}"
out_dir="${4:-gifs_filters}"

if [[ -z "$video1" || -z "$video2" || -z "$video3" ]]; then
  echo "Usage: ${script_name} <video1> <video2> <video3> [out_dir]"
  exit 1
fi

mkdir -p "$out_dir"

fps="${FPS:-12}"
segment_seconds="${SEGMENT_SECONDS:-5}"
single_width="${SINGLE_WIDTH:-960}"
triptych_width="${TRIPTYCH_WIDTH:-1920}"
dither="${DITHER:-sierra2_4a}"
palette_stats="${PALETTE_STATS:-single}"
fontsize="${FONTSIZE:-34}"
box_opacity="${BOX_OPACITY:-0.55}"
box_border="${BOX_BORDER:-8}"

label1="$(basename "$video1")"; label1="${label1%.*}"
label2="$(basename "$video2")"; label2="${label2%.*}"
label3="$(basename "$video3")"; label3="${label3%.*}"

label_filter() {
  local text="$1"
  local size="$2"
  if [[ -n "${FONTFILE:-}" ]]; then
    printf ',drawtext=fontfile=%s:text=%q:x=20:y=40:fontsize=%s:fontcolor=white:box=1:boxcolor=black@%s:boxborderw=%s' "$FONTFILE" "$text" "$size" "$box_opacity" "$box_border"
  elif [[ -n "${FONTNAME:-}" ]]; then
    printf ',drawtext=font=%s:text=%q:x=20:y=40:fontsize=%s:fontcolor=white:box=1:boxcolor=black@%s:boxborderw=%s' "$FONTNAME" "$text" "$size" "$box_opacity" "$box_border"
  fi
}

make_single_gif() {
  local in_file="$1" out_file="$2" text_label="$3" fx="$4"
  local text_fx
  text_fx="$(label_filter "$text_label" "$fontsize")"

  ffmpeg -hide_banner -nostdin -y -i "$in_file" -filter_complex "
    [0:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1${fx:+,${fx}}${text_fx},format=rgba,split[v0][v1];
    [v0]palettegen=stats_mode=${palette_stats}[p];
    [v1][p]paletteuse=new=1:dither=${dither}
  " -loop 0 "$out_file"
}

make_single_gif_chroma() {
  local in_file="$1" out_file="$2" text_label="$3"
  local text_fx
  text_fx="$(label_filter "${text_label} (U | V)" "$fontsize")"

  ffmpeg -hide_banner -nostdin -y -i "$in_file" -filter_complex "
    [0:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=u[u0];
    [0:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=v[v0];
    [u0]format=gray,normalize[u1];
    [v0]format=gray,normalize[v1];
    [u1][v1]hstack=inputs=2,format=rgba${text_fx},split[x0][x1];
    [x0]palettegen=stats_mode=${palette_stats}[p];
    [x1][p]paletteuse=new=1:dither=${dither}
  " -loop 0 "$out_file"
}

make_triptych_gif() {
  local out_file="$1" fx="$2"
  local t1 t2 t3
  t1="$(label_filter "$label1" 30)"
  t2="$(label_filter "$label2" 30)"
  t3="$(label_filter "$label3" 30)"

  ffmpeg -hide_banner -nostdin -y -i "$video1" -i "$video2" -i "$video3" -filter_complex "
    [0:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1${fx:+,${fx}}${t1}[v1];
    [1:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1${fx:+,${fx}}${t2}[v2];
    [2:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1${fx:+,${fx}}${t3}[v3];
    [v1][v2][v3]hstack=inputs=3,scale=${triptych_width}:-1:flags=lanczos,format=rgba,split[m0][m1];
    [m0]palettegen=stats_mode=${palette_stats}[p];
    [m1][p]paletteuse=new=1:dither=${dither}
  " -loop 0 "$out_file"
}

make_triptych_gif_chroma() {
  local out_file="$1"
  local t1 t2 t3
  t1="$(label_filter "${label1} (U|V)" 28)"
  t2="$(label_filter "${label2} (U|V)" 28)"
  t3="$(label_filter "${label3} (U|V)" 28)"

  ffmpeg -hide_banner -nostdin -y -i "$video1" -i "$video2" -i "$video3" -filter_complex "
    [0:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=u[u1];
    [0:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=v[v1];
    [u1]format=gray,normalize[ug1]; [v1]format=gray,normalize[vg1];
    [ug1][vg1]hstack=inputs=2${t1}[a];

    [1:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=u[u2];
    [1:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=v[v2];
    [u2]format=gray,normalize[ug2]; [v2]format=gray,normalize[vg2];
    [ug2][vg2]hstack=inputs=2${t2}[b];

    [2:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=u[u3];
    [2:v]fps=${fps},scale=640:-1:flags=lanczos,setsar=1,format=yuv444p,extractplanes=v[v3];
    [u3]format=gray,normalize[ug3]; [v3]format=gray,normalize[vg3];
    [ug3][vg3]hstack=inputs=2${t3}[c];

    [a][b][c]hstack=inputs=3,scale=${triptych_width}:-1:flags=lanczos,format=rgba,split[m0][m1];
    [m0]palettegen=stats_mode=${palette_stats}[p];
    [m1][p]paletteuse=new=1:dither=${dither}
  " -loop 0 "$out_file"
}

make_sweep_gif() {
  local out_file="$1" fx="$2"
  ffmpeg -hide_banner -nostdin -y -i "$video1" -i "$video2" -i "$video3" -filter_complex "
    [0:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1${fx:+,${fx}},trim=0:${segment_seconds},setpts=PTS-STARTPTS[a0];
    [1:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1${fx:+,${fx}},trim=0:${segment_seconds},setpts=PTS-STARTPTS[a1];
    [2:v]fps=${fps},scale=${single_width}:-1:flags=lanczos,setsar=1${fx:+,${fx}},trim=0:${segment_seconds},setpts=PTS-STARTPTS[a2];
    [a0][a1][a2]concat=n=3:v=1:a=0,format=rgba,split[c0][c1];
    [c0]palettegen=stats_mode=${palette_stats}[p];
    [c1][p]paletteuse=new=1:dither=${dither}
  " -loop 0 "$out_file"
}

make_single_gif "$video1" "$out_dir/${label1}_normal.gif" "${label1} normal" ""
make_single_gif "$video2" "$out_dir/${label2}_normal.gif" "${label2} normal" ""
make_single_gif "$video3" "$out_dir/${label3}_normal.gif" "${label3} normal" ""
make_triptych_gif "$out_dir/compare_normal.gif" ""
make_sweep_gif "$out_dir/sweep_normal.gif" ""

make_single_gif "$video1" "$out_dir/${label1}_edges.gif" "${label1} edges" "edgedetect=low=0.05:high=0.15"
make_single_gif "$video2" "$out_dir/${label2}_edges.gif" "${label2} edges" "edgedetect=low=0.05:high=0.15"
make_single_gif "$video3" "$out_dir/${label3}_edges.gif" "${label3} edges" "edgedetect=low=0.05:high=0.15"
make_triptych_gif "$out_dir/compare_edges.gif" "edgedetect=low=0.05:high=0.15"
make_sweep_gif "$out_dir/sweep_edges.gif" "edgedetect=low=0.05:high=0.15"

make_single_gif "$video1" "$out_dir/${label1}_contrast.gif" "${label1} contrast" "eq=contrast=1.7:brightness=0.02:saturation=1.0"
make_single_gif "$video2" "$out_dir/${label2}_contrast.gif" "${label2} contrast" "eq=contrast=1.7:brightness=0.02:saturation=1.0"
make_single_gif "$video3" "$out_dir/${label3}_contrast.gif" "${label3} contrast" "eq=contrast=1.7:brightness=0.02:saturation=1.0"
make_triptych_gif "$out_dir/compare_contrast.gif" "eq=contrast=1.7:brightness=0.02:saturation=1.0"
make_sweep_gif "$out_dir/sweep_contrast.gif" "eq=contrast=1.7:brightness=0.02:saturation=1.0"

make_single_gif "$video1" "$out_dir/${label1}_gray.gif" "${label1} gray" "hue=s=0"
make_single_gif "$video2" "$out_dir/${label2}_gray.gif" "${label2} gray" "hue=s=0"
make_single_gif "$video3" "$out_dir/${label3}_gray.gif" "${label3} gray" "hue=s=0"
make_triptych_gif "$out_dir/compare_gray.gif" "hue=s=0"
make_sweep_gif "$out_dir/sweep_gray.gif" "hue=s=0"

make_single_gif "$video1" "$out_dir/${label1}_sat.gif" "${label1} sat+" "hue=s=1.6"
make_single_gif "$video2" "$out_dir/${label2}_sat.gif" "${label2} sat+" "hue=s=1.6"
make_single_gif "$video3" "$out_dir/${label3}_sat.gif" "${label3} sat+" "hue=s=1.6"
make_triptych_gif "$out_dir/compare_sat.gif" "hue=s=1.6"
make_sweep_gif "$out_dir/sweep_sat.gif" "hue=s=1.6"

make_single_gif_chroma "$video1" "$out_dir/${label1}_chroma_uv.gif" "$label1"
make_single_gif_chroma "$video2" "$out_dir/${label2}_chroma_uv.gif" "$label2"
make_single_gif_chroma "$video3" "$out_dir/${label3}_chroma_uv.gif" "$label3"
make_triptych_gif_chroma "$out_dir/compare_chroma_uv.gif"
