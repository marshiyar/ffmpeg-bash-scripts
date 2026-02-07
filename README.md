# Script Catalog

Each script below has a single clear purpose. Run any script without required arguments to see its usage message.

## 01 Download

- `scripts/01_download/download_hls_stream.sh`
Purpose: Download an HLS URL (`.m3u8`) to a local file using stream copy.
Usage: `./scripts/01_download/download_hls_stream.sh <hls_url> <output_file>`

## 02 Tagging

- `scripts/02_tagging/tag_mov_prores_apcn.sh`
Purpose: Tag MOV video stream as ProRes `apcn` while copying all tracks.
Usage: `./scripts/02_tagging/tag_mov_prores_apcn.sh <input.mov> [output.mov]`

- `scripts/02_tagging/tag_mov_avc1_bt709.sh`
Purpose: Tag MOV video as `avc1` and attach BT.709 color metadata.
Usage: `./scripts/02_tagging/tag_mov_avc1_bt709.sh <input.mov> [output.mov]`

- `scripts/02_tagging/tag_mp4_hvc1_bt709.sh`
Purpose: Tag MP4 video as `hvc1` and attach BT.709 color metadata.
Usage: `./scripts/02_tagging/tag_mp4_hvc1_bt709.sh <input.mp4> [output.mp4]`

## 03 Metrics

- `scripts/03_metrics/metrics_compare_ssim_psnr.sh`
Purpose: Compute SSIM and PSNR between reference and test videos.
Usage: `./scripts/03_metrics/metrics_compare_ssim_psnr.sh <reference> <test> [width] [height]`

- `scripts/03_metrics/metrics_compare_ssim_psnr_log.sh`
Purpose: Compute SSIM/PSNR and write SSIM stats to a log file.
Usage: `./scripts/03_metrics/metrics_compare_ssim_psnr_log.sh <reference> <test> [stats_file] [width] [height]`

- `scripts/03_metrics/metrics_compare_vmaf.sh`
Purpose: Compute VMAF between reference and test videos.
Usage: `./scripts/03_metrics/metrics_compare_vmaf.sh <reference> <test> [model] [width] [height]`

## 04 Encode

- `scripts/04_encode/hevc/encode_hevc_single_x265.sh`
Purpose: Re-encode one input to HEVC (`libx265`) and copy audio/subtitles.
Usage: `./scripts/04_encode/hevc/encode_hevc_single_x265.sh <input> [output] [crf] [preset]`

- `scripts/04_encode/hevc/encode_hevc_batch_x265.sh`
Purpose: Batch re-encode files matching a glob to HEVC (`libx265`).
Usage: `./scripts/04_encode/hevc/encode_hevc_batch_x265.sh "<glob>" [crf] [preset] [suffix]`

- `scripts/04_encode/h264/encode_h264_single_x264.sh`
Purpose: Re-encode one input to H.264 (`libx264`) and copy audio/subtitles.
Usage: `./scripts/04_encode/h264/encode_h264_single_x264.sh <input> [output] [crf] [preset]`

- `scripts/04_encode/h264/encode_h264_batch_x264.sh`
Purpose: Batch re-encode files matching a glob to H.264 (`libx264`).
Usage: `./scripts/04_encode/h264/encode_h264_batch_x264.sh "<glob>" [crf] [preset] [suffix]`

- `scripts/04_encode/av1/encode_av1_single_svt.sh`
Purpose: Re-encode one input to AV1 with `libsvtav1` (popular practical AV1 workflow).
Usage: `./scripts/04_encode/av1/encode_av1_single_svt.sh <input> [output] [crf] [preset]`

- `scripts/04_encode/av1/encode_av1_batch_svt.sh`
Purpose: Batch re-encode files matching a glob to AV1 with `libsvtav1`.
Usage: `./scripts/04_encode/av1/encode_av1_batch_svt.sh "<glob>" [crf] [preset] [suffix] [container]`

- `scripts/04_encode/av1/encode_av1_single_aom.sh`
Purpose: Re-encode one input to AV1 with `libaom-av1` (quality-focused, slower).
Usage: `./scripts/04_encode/av1/encode_av1_single_aom.sh <input> [output] [crf] [cpu_used]`

- `scripts/04_encode/hardware/encode_hevc_single_videotoolbox.sh`
Purpose: Hardware HEVC encode using `hevc_videotoolbox` (macOS).
Usage: `./scripts/04_encode/hardware/encode_hevc_single_videotoolbox.sh <input> [output] [bitrate] [realtime]`

- `scripts/04_encode/hardware/encode_hevc_batch_videotoolbox.sh`
Purpose: Batch hardware HEVC encode using `hevc_videotoolbox`.
Usage: `./scripts/04_encode/hardware/encode_hevc_batch_videotoolbox.sh "<glob>" [bitrate] [suffix] [container] [realtime]`

- `scripts/04_encode/hardware/encode_av1_single_videotoolbox.sh`
Purpose: Hardware AV1 encode using `av1_videotoolbox` when available.
Usage: `./scripts/04_encode/hardware/encode_av1_single_videotoolbox.sh <input> [output] [bitrate] [realtime]`

- `scripts/04_encode/hardware/encode_av1_batch_videotoolbox.sh`
Purpose: Batch hardware AV1 encode using `av1_videotoolbox` when available.
Usage: `./scripts/04_encode/hardware/encode_av1_batch_videotoolbox.sh "<glob>" [bitrate] [suffix] [container] [realtime]`

- `scripts/04_encode/hdr/convert_sdr_to_hdr10_style.sh`
Purpose: Convert SDR video to an HDR10-style deliverable using a filter pipeline (gamut remap + tone shaping + detail polish).
Usage: `./scripts/04_encode/hdr/convert_sdr_to_hdr10_style.sh <input> [output] [profile] [codec] [quality] [preset]`
Notes: Profiles are `natural`, `gentle`, `balanced`, and `punchy` (`natural` is default). Use `HDR_TRANSFER=bt2020-10` for a safer non-dark result, or `HDR_TRANSFER=smpte2084` for stronger HDR signaling.

- `scripts/04_encode/prores/encode_prores4444_minterpolate.sh`
Purpose: Normalize one source to target FPS/size and encode ProRes 4444.
Usage: `./scripts/04_encode/prores/encode_prores4444_minterpolate.sh <input> <output> [fps] [width] [height]`

- `scripts/04_encode/prores/encode_prores4444xq_alpha_denoise_minterpolate.sh`
Purpose: Denoise and motion-interpolate to ProRes 4444 XQ with alpha.
Usage: `./scripts/04_encode/prores/encode_prores4444xq_alpha_denoise_minterpolate.sh <input> <output> [fps]`

- `scripts/04_encode/prores/encode_prores4444xq_no_alpha_denoise_minterpolate.sh`
Purpose: Denoise and motion-interpolate to ProRes 4444 XQ without alpha.
Usage: `./scripts/04_encode/prores/encode_prores4444xq_no_alpha_denoise_minterpolate.sh <input> <output> [fps]`

- `scripts/04_encode/upscale/upscale_2x_60fps_prores422.sh`
Purpose: Upscale 2x, interpolate to 60 fps, and output ProRes 422.
Usage: `./scripts/04_encode/upscale/upscale_2x_60fps_prores422.sh <input_video> [output_dir]`

- `scripts/04_encode/upscale/upscale_video_lanczos_plain.sh`
Purpose: Plain non-AI, non-tiling Lanczos upscale only (no interpolation, no ProRes-specific output path).
Usage: `./scripts/04_encode/upscale/upscale_video_lanczos_plain.sh <input> [output] [scale_factor] [codec] [quality] [preset]`
Notes: Default output uses `libx264`. Set `codec` to `libx265` or `*_videotoolbox` if desired.

- `scripts/04_encode/upscale/upscale_video_realesrgan_coreml_x2.sh`
Purpose: CoreML upscale in non-tiled mode for supported models (RealESRGAN x2/x4, SwinIR x2), model-native path.
Usage: `./scripts/04_encode/upscale/upscale_video_realesrgan_coreml_x2.sh <input> [output] [model_path] [work_dir] [crf] [preset]`
Notes: Set `MODEL_COLOR_ORDER=bgr` if a model expects BGR channel order. Set `TARGET_UPSCALE=2` to force 2x output from an x4 model.

- `scripts/04_encode/upscale/upscale_video_realesrgan_coreml_x2_tiled.sh`
Purpose: Split source into `.mkv` tile videos, upscale each tile via supported CoreML model (RealESRGAN x2/x4, SwinIR x2), then reassemble seam-free.
Usage: `./scripts/04_encode/upscale/upscale_video_realesrgan_coreml_x2_tiled.sh <input> [output] [model_path] [work_dir] [overlap] [crf] [preset] [rows] [cols]`
Notes: Default intermediates are lossless `ffv1` with `gbrp` to reduce color shifts. Set `MODEL_COLOR_ORDER=bgr` for BGR models. Set `TARGET_UPSCALE=2` to force 2x output from an x4 model. Set `TILE_JOBS` to run multiple tile videos in parallel. If grid resolves to `1x1`, the script now skips split/reassemble and runs direct tiled inference for speed.

- `scripts/04_encode/upscale/upscale_video_realesrgan_coreml_vram_turbo.sh`
Purpose: macOS turbo wrapper with auto-tuned parallelism, GPU-focused CoreML compute, and fast hardware final encode.
Usage: `./scripts/04_encode/upscale/upscale_video_realesrgan_coreml_vram_turbo.sh <input> [output] [model_path] [work_dir] [rows] [cols]`
Notes: Defaults now target quality-safe speed (`ffv1` lossless intermediate, large auto tile size for direct path on smaller sources). Set `ALLOW_LOSSY_INTERMEDIATE=1` to use hardware intermediate encode for extra speed. Set `V_ALLOW_SW=1` (default) to allow VideoToolbox software fallback when hardware sessions are busy.

- `scripts/04_encode/upscale/enhance_video_look_secondary_flow.sh`
Purpose: Secondary post-upscale visual polish flow using FFmpeg enhancement filters (`cas`, denoise, deband, detail shaping) with profile presets.
Usage: `./scripts/04_encode/upscale/enhance_video_look_secondary_flow.sh <input> [output] [profile] [codec] [quality] [preset]`
Notes: Profile presets are `subtle`, `balanced`, `crisp`, and `smooth`. This script is standalone and does not modify the core upscale pipeline.

- `scripts/04_encode/upscale/upscale_video_realesrgan_coreml_vram_turbo_with_enhance.sh`
Purpose: One-command chain that runs turbo CoreML upscale first, then runs the secondary FFmpeg enhancement flow.
Usage: `./scripts/04_encode/upscale/upscale_video_realesrgan_coreml_vram_turbo_with_enhance.sh <input> [output] [model_path] [enhance_profile] [work_dir] [rows] [cols]`
Notes: Enhancement profile presets are `subtle`, `balanced`, `crisp`, and `smooth`. Uses env `ENHANCE_CODEC`, `ENHANCE_QUALITY`, `ENHANCE_PRESET` for stage-2 encode tuning.

## 05 Blend and Stack

- `scripts/05_blend_stack/normalize/normalize_two_to_prores422.sh`
Purpose: Normalize two inputs to matching fps/size and output ProRes 422 files.
Usage: `./scripts/05_blend_stack/normalize/normalize_two_to_prores422.sh <input_a> <input_b> [out_dir] [fps] [width] [height]`

- `scripts/05_blend_stack/normalize/normalize_three_to_prores4444.sh`
Purpose: Normalize three inputs to matching fps/size and output ProRes 4444 files.
Usage: `./scripts/05_blend_stack/normalize/normalize_three_to_prores4444.sh <input_a> <input_b> <input_c> [out_dir] [fps] [width] [height]`

- `scripts/05_blend_stack/blend/blend_average_two_hevc.sh`
Purpose: Average-blend two videos and encode result to HEVC.
Usage: `./scripts/05_blend_stack/blend/blend_average_two_hevc.sh <input_a> <input_b> [output] [crf] [preset]`

- `scripts/05_blend_stack/blend/blend_difference_two.sh`
Purpose: Difference-blend two videos for alignment/debug comparisons.
Usage: `./scripts/05_blend_stack/blend/blend_difference_two.sh <input_a> <input_b> [output]`

- `scripts/05_blend_stack/blend/blend_weighted_three_prores4444.sh`
Purpose: Weighted 3-way blend to ProRes 4444.
Usage: `./scripts/05_blend_stack/blend/blend_weighted_three_prores4444.sh <input_a> <input_b> <input_c> [output]`

- `scripts/05_blend_stack/blend/finish_weighted_merge_4k_prores4444.sh`
Purpose: Finalize merged input to 4K ProRes 4444 with finishing filters.
Usage: `./scripts/05_blend_stack/blend/finish_weighted_merge_4k_prores4444.sh <input> <output> [width] [height]`

- `scripts/05_blend_stack/blend/blend_edge_aware_hevc.sh`
Purpose: Edge-aware 2-source merge and HEVC encode.
Usage: `./scripts/05_blend_stack/blend/blend_edge_aware_hevc.sh <input_a> <input_b> [output] [crf] [preset]`

- `scripts/05_blend_stack/stack/stack_2x2_hstack_vstack.sh`
Purpose: Stack four inputs into a 2x2 layout using `hstack` + `vstack`.
Usage: `./scripts/05_blend_stack/stack/stack_2x2_hstack_vstack.sh <input0> <input1> <input2> <input3> <output> [width] [height]`

- `scripts/05_blend_stack/stack/stack_2x2_xstack.sh`
Purpose: Stack four inputs into a 2x2 layout using `xstack`.
Usage: `./scripts/05_blend_stack/stack/stack_2x2_xstack.sh <input0> <input1> <input2> <input3> <output> [width] [height]`

- `scripts/05_blend_stack/pipelines/pipeline_parallel_blend_hevc.sh`
Purpose: Parallel upscale/blend/denoise pipeline to HEVC.
Usage: `./scripts/05_blend_stack/pipelines/pipeline_parallel_blend_hevc.sh <input> <output> [crf] [preset]`

- `scripts/05_blend_stack/pipelines/pipeline_serial_hybrid_hevc.sh`
Purpose: Serial interpolation/upscale/denoise pipeline to HEVC.
Usage: `./scripts/05_blend_stack/pipelines/pipeline_serial_hybrid_hevc.sh <input> <output> [crf] [preset] [fps]`

- `scripts/05_blend_stack/metrics/metrics_ssim_psnr.sh`
Purpose: Workflow-local SSIM/PSNR comparison script.
Usage: `./scripts/05_blend_stack/metrics/metrics_ssim_psnr.sh <ref> <test> [width] [height]`

- `scripts/05_blend_stack/metrics/metrics_ssim_psnr_stats.sh`
Purpose: Workflow-local SSIM/PSNR with stats file output.
Usage: `./scripts/05_blend_stack/metrics/metrics_ssim_psnr_stats.sh <ref> <test> [stats_file] [width] [height]`

- `scripts/05_blend_stack/metrics/metrics_vmaf.sh`
Purpose: Workflow-local VMAF comparison script.
Usage: `./scripts/05_blend_stack/metrics/metrics_vmaf.sh <ref> <test> [model] [width] [height]`

- `scripts/05_blend_stack/contact_sheets/contact_sheet_video_8x8.sh`
Purpose: Build an 8x8 contact sheet image from one video.
Usage: `./scripts/05_blend_stack/contact_sheets/contact_sheet_video_8x8.sh <input> <output> [fps] [scale_width] [tile]`

- `scripts/05_blend_stack/contact_sheets/contact_sheet_combine_three.sh`
Purpose: Combine three contact-sheet images into one horizontal comparison image.
Usage: `./scripts/05_blend_stack/contact_sheets/contact_sheet_combine_three.sh <img1> <img2> <img3> <output> [title]`

- `scripts/05_blend_stack/tagging/tag_mov_avc1_bt709.sh`
Purpose: Apply avc1 + BT.709 metadata tags to a MOV.
Usage: `./scripts/05_blend_stack/tagging/tag_mov_avc1_bt709.sh <input> [output]`

## 06 Visualization

- `scripts/06_visualization/contact_sheets/contact_sheet_video_tile8x8.sh`
Purpose: Build a labeled or unlabeled 8x8 tiled contact sheet from one video.
Usage: `./scripts/06_visualization/contact_sheets/contact_sheet_video_tile8x8.sh <input_video> <output_image> [fps] [scale_width] [tile]`

- `scripts/06_visualization/contact_sheets/contact_sheet_three_videos_3wide.sh`
Purpose: Build one contact sheet per input video, then a 3-wide combined image.
Usage: `./scripts/06_visualization/contact_sheets/contact_sheet_three_videos_3wide.sh <video1> <video2> <video3> [out_dir]`

- `scripts/06_visualization/contact_sheets/contact_sheet_three_videos_multi_filters.sh`
Purpose: Build contact sheets for multiple analysis filters and combined 3-wide outputs.
Usage: `./scripts/06_visualization/contact_sheets/contact_sheet_three_videos_multi_filters.sh <video1> <video2> <video3> [out_dir]`

- `scripts/06_visualization/contact_sheets/contact_sheet_three_videos_multi_filters_compat.sh`
Purpose: Compatibility wrapper that forwards to the maintained multi-filter script.
Usage: `./scripts/06_visualization/contact_sheets/contact_sheet_three_videos_multi_filters_compat.sh <video1> <video2> <video3> [out_dir]`

- `scripts/06_visualization/gifs/gif_three_video_filter_suite.sh`
Purpose: Generate single, triptych, and sweep GIF comparisons across common filter looks.
Usage: `./scripts/06_visualization/gifs/gif_three_video_filter_suite.sh <video1> <video2> <video3> [out_dir]`

## 07 Muxing

- `scripts/07_muxing/remux_container_copy.sh`
Purpose: Remux media into a new container without re-encoding streams.
Usage: `./scripts/07_muxing/remux_container_copy.sh <input> <output>`

- `scripts/07_muxing/convert_gif_to_video_mp4.sh`
Purpose: Convert a GIF animation into MP4 video using compatibility-safe H.264 settings.
Usage: `./scripts/07_muxing/convert_gif_to_video_mp4.sh <input.gif> [output.mp4] [fps] [crf] [preset]`

- `scripts/07_muxing/convert_gif_to_video_batch_mp4.sh`
Purpose: Batch convert multiple GIF files to MP4 using a glob pattern.
Usage: `./scripts/07_muxing/convert_gif_to_video_batch_mp4.sh "<glob>" [out_dir] [fps] [crf] [preset]`

- `scripts/07_muxing/mux_replace_audio_from_second_input.sh`
Purpose: Keep video from input #1 and replace its audio with input #2 audio.
Usage: `./scripts/07_muxing/mux_replace_audio_from_second_input.sh <video_input> <audio_input> [output]`

- `scripts/07_muxing/mux_add_external_audio_track.sh`
Purpose: Add an external audio track while keeping existing streams.
Usage: `./scripts/07_muxing/mux_add_external_audio_track.sh <video_input> <audio_input> [output]`

- `scripts/07_muxing/mux_add_srt_subtitle_to_mp4.sh`
Purpose: Add an SRT subtitle track to MP4 (subtitle codec `mov_text`).
Usage: `./scripts/07_muxing/mux_add_srt_subtitle_to_mp4.sh <video_input> <subtitle.srt> [output.mp4]`

- `scripts/07_muxing/mux_concat_copy_from_args.sh`
Purpose: Concatenate multiple matching files using concat demuxer and stream copy.
Usage: `./scripts/07_muxing/mux_concat_copy_from_args.sh <output> <input1> <input2> [inputN...]`

- `scripts/07_muxing/mux_video_audio_subtitle_mp4.sh`
Purpose: Mux video + external audio + SRT subtitle into one MP4.
Usage: `./scripts/07_muxing/mux_video_audio_subtitle_mp4.sh <video_input> <audio_input> <subtitle.srt> [output.mp4]`

## 08 Compression Profiles

- `scripts/08_compression_profiles/compress_h264_high_compat.sh`
Purpose: Standard high-compatibility H.264 compression profile for broad playback.
Usage: `./scripts/08_compression_profiles/compress_h264_high_compat.sh <input> [output] [crf] [preset]`

- `scripts/08_compression_profiles/compress_hevc_high_efficiency.sh`
Purpose: Standard HEVC high-efficiency profile (10-bit) for smaller files at similar quality.
Usage: `./scripts/08_compression_profiles/compress_hevc_high_efficiency.sh <input> [output] [crf] [preset]`

- `scripts/08_compression_profiles/compress_av1_high_efficiency.sh`
Purpose: Standard AV1 high-efficiency profile with `libsvtav1`.
Usage: `./scripts/08_compression_profiles/compress_av1_high_efficiency.sh <input> [output] [crf] [preset]`

- `scripts/08_compression_profiles/compress_h264_two_pass_target_size.sh`
Purpose: Two-pass H.264 encode targeting a specific output size.
Usage: `./scripts/08_compression_profiles/compress_h264_two_pass_target_size.sh <input> <target_mb> [output] [preset] [audio_kbps]`

- `scripts/08_compression_profiles/compress_h264_ladder_abr.sh`
Purpose: Build a 3-rung ABR ladder (1080p/720p/480p) for streaming-ready renditions.
Usage: `./scripts/08_compression_profiles/compress_h264_ladder_abr.sh <input> [output_dir]`

## 09 Tiling

- `scripts/09_tiling/split_video_into_tiles_high_quality.sh`
Purpose: Split a video frame into an N×M grid of spatial tiles with a manifest for exact reconstruction.
Usage: `./scripts/09_tiling/split_video_into_tiles_high_quality.sh <input> <rows> <cols> <out_dir> [crf] [preset]`

- `scripts/09_tiling/reassemble_video_from_tiles_blackout.sh`
Purpose: Reassemble tiled pieces seam-free from manifest, with optional blacked-out spatial blocks.
Usage: `./scripts/09_tiling/reassemble_video_from_tiles_blackout.sh <manifest> <output> [black_tiles_csv] [audio_source] [tiles_dir]`
Notes: For `tile_count=1` and no blackout list, the script uses a stream-copy fast path.

- `scripts/09_tiling/upscale_video_by_tiles_and_reassemble.sh`
Purpose: Split into spatial tiles, upscale each tile, then reassemble the upscaled tiles seam-free.
Usage: `./scripts/09_tiling/upscale_video_by_tiles_and_reassemble.sh <input> <rows> <cols> <scale_int> <output> [work_dir] [crf] [preset]`

## 10 Audio

- `scripts/10_audio/enhance_audio_track_ffmpeg.sh`
Purpose: Enhance audio in audio/video files with denoise, tone shaping, dynamics control, and optional loudness normalization.
Usage: `./scripts/10_audio/enhance_audio_track_ffmpeg.sh <input> [output] [profile] [audio_codec] [audio_quality]`
Notes: Profiles are `subtle`, `balanced`, `voice`, and `strong`. Video streams are copied while audio is replaced with the enhanced track.
