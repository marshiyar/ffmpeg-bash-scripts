#!/usr/bin/env python3
"""
CoreML video upscaler runner with streaming parallel frame pipeline.

Supported model interfaces:
- MultiArray input [1, 12, H, W] -> output [1, 3, 2H, 2W] (pixel-unshuffle-x2 style, e.g. RealESRGAN x2)
- MultiArray input [1, 3, H, W] -> output [1, 3, sH, sW] (direct RGB, e.g. RealESRGAN x4)
- Image input (HxW RGB) -> output [1, 3, sH, sW] or image output (e.g. SwinIR x2 variants)
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

try:
    import coremltools as ct
except Exception as exc:  # pragma: no cover - runtime dependency guard
    print(f"Error: failed to import coremltools: {exc}", file=sys.stderr)
    sys.exit(2)


@dataclass(frozen=True)
class ModelProfile:
    adapter: str
    input_name: str
    output_name: str
    lr_h: int
    lr_w: int
    sr_h: int
    sr_w: int
    scale_y: int
    scale_x: int
    input_kind: str
    output_kind: str


def run_cmd(cmd: list[str]) -> None:
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if proc.returncode != 0:
        print("Command failed:", " ".join(cmd), file=sys.stderr)
        print(proc.stdout, file=sys.stderr)
        raise RuntimeError("subprocess failure")


def probe_video(input_path: Path) -> tuple[int, int, str]:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "v:0",
        "-show_entries",
        "stream=width,height,avg_frame_rate",
        "-of",
        "default=noprint_wrappers=1:nokey=1",
        str(input_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"ffprobe failed: {proc.stderr.strip()}")
    lines = [line.strip() for line in proc.stdout.splitlines() if line.strip()]
    if len(lines) < 3:
        raise RuntimeError("ffprobe did not return width/height/fps")
    width = int(lines[0])
    height = int(lines[1])
    fps = lines[2]
    return width, height, fps


def read_exact(stream, size: int) -> bytes | None:
    """Read exactly `size` bytes from stream, or None on clean EOF."""
    chunks = []
    remaining = size
    while remaining > 0:
        chunk = stream.read(remaining)
        if not chunk:
            if remaining == size:
                return None
            raise RuntimeError("Unexpected EOF while reading frame bytes")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def drain_pipe_async(pipe) -> tuple[list[bytes], threading.Thread]:
    chunks: list[bytes] = []

    def _drain() -> None:
        if pipe is None:
            return
        try:
            with pipe:
                while True:
                    data = pipe.read(8192)
                    if not data:
                        break
                    chunks.append(data)
        except Exception:
            pass

    t = threading.Thread(target=_drain, daemon=True)
    t.start()
    return chunks, t


def pixel_unshuffle_2x(img_hwc: np.ndarray) -> np.ndarray:
    h, w, c = img_hwc.shape
    if c != 3:
        raise ValueError("pixel_unshuffle_2x expects 3 channels")
    if h % 2 != 0 or w % 2 != 0:
        raise ValueError("pixel_unshuffle_2x expects even H and W")
    chw = img_hwc.transpose(2, 0, 1)
    out = (
        chw.reshape(3, h // 2, 2, w // 2, 2)
        .transpose(0, 2, 4, 1, 3)
        .reshape(12, h // 2, w // 2)
    )
    return out


def hwc_float_to_uint8(frame_hwc: np.ndarray) -> np.ndarray:
    return np.clip(np.round(frame_hwc * 255.0), 0, 255).astype(np.uint8)


def chw_to_hwc_uint8(chw: np.ndarray) -> np.ndarray:
    arr = np.clip(chw, 0.0, 1.0).transpose(1, 2, 0)
    return np.clip(np.round(arr * 255.0), 0, 255).astype(np.uint8)


def positions_for_length(length: int, tile: int, step: int) -> list[int]:
    if length <= tile:
        return [0]
    out = [0]
    while True:
        nxt = out[-1] + step
        if nxt + tile >= length:
            edge = length - tile
            if edge != out[-1]:
                out.append(edge)
            break
        out.append(nxt)
    return out


def make_weight_mask(
    tile_out_h: int,
    tile_out_w: int,
    fade_h: int,
    fade_w: int,
    top: bool,
    bottom: bool,
    left: bool,
    right: bool,
) -> np.ndarray:
    mask = np.ones((tile_out_h, tile_out_w), dtype=np.float32)

    if fade_h > 0:
        for i in range(min(fade_h, tile_out_h)):
            v = (i + 1) / float(fade_h + 1)
            if top:
                mask[i, :] *= v
            if bottom:
                mask[tile_out_h - 1 - i, :] *= v

    if fade_w > 0:
        for j in range(min(fade_w, tile_out_w)):
            v = (j + 1) / float(fade_w + 1)
            if left:
                mask[:, j] *= v
            if right:
                mask[:, tile_out_w - 1 - j] *= v

    return mask


def _multiarray_shape(desc) -> tuple[int, ...]:
    return tuple(int(v) for v in desc.type.multiArrayType.shape)


def _normalize_output_hwc(arr: np.ndarray) -> np.ndarray:
    arr = np.asarray(arr, dtype=np.float32)
    if arr.size == 0:
        raise RuntimeError("Model produced empty output")
    # Some models output 0..255; normalize to 0..1 when needed.
    if np.nanmax(arr) > 1.5:
        arr = arr / 255.0
    return np.clip(arr, 0.0, 1.0)


def read_model_profile(model_path: Path) -> ModelProfile:
    spec = ct.utils.load_spec(str(model_path))

    if len(spec.description.input) != 1 or len(spec.description.output) != 1:
        raise RuntimeError("Expected exactly one model input and one model output")

    in_desc = spec.description.input[0]
    out_desc = spec.description.output[0]
    in_kind = in_desc.type.WhichOneof("Type")
    out_kind = out_desc.type.WhichOneof("Type")

    input_name = in_desc.name
    output_name = out_desc.name

    lr_h = lr_w = sr_h = sr_w = 0
    adapter = ""

    if out_kind == "multiArrayType":
        out_shape = _multiarray_shape(out_desc)
        if len(out_shape) != 4 or out_shape[0] != 1 or out_shape[1] < 3:
            raise RuntimeError(f"Unsupported output multiarray shape: {out_shape}")
        sr_h, sr_w = int(out_shape[2]), int(out_shape[3])
    elif out_kind == "imageType":
        sr_h = int(out_desc.type.imageType.height)
        sr_w = int(out_desc.type.imageType.width)
        if sr_h <= 0 or sr_w <= 0:
            raise RuntimeError("Output imageType must have fixed width/height")
    else:
        raise RuntimeError(f"Unsupported output type: {out_kind}")

    if in_kind == "multiArrayType":
        in_shape = _multiarray_shape(in_desc)
        if len(in_shape) != 4 or in_shape[0] != 1:
            raise RuntimeError(f"Unsupported input multiarray shape: {in_shape}")
        c_in, lr_h, lr_w = int(in_shape[1]), int(in_shape[2]), int(in_shape[3])

        if c_in == 12 and sr_h == lr_h * 2 and sr_w == lr_w * 2:
            adapter = "multiarray_12ch_pixelunshuffle2"
        elif c_in == 3 and sr_h % lr_h == 0 and sr_w % lr_w == 0:
            adapter = "multiarray_3ch_direct"
        else:
            raise RuntimeError(
                f"Unsupported multiarray model IO combo: input {in_shape}, output {('image' if out_kind=='imageType' else out_shape)}"
            )

    elif in_kind == "imageType":
        lr_h = int(in_desc.type.imageType.height)
        lr_w = int(in_desc.type.imageType.width)
        if lr_h <= 0 or lr_w <= 0:
            raise RuntimeError("Input imageType must have fixed width/height")
        if sr_h % lr_h != 0 or sr_w % lr_w != 0:
            raise RuntimeError(
                f"Unsupported image input scale: input {lr_w}x{lr_h}, output {sr_w}x{sr_h}"
            )
        adapter = "image_direct"
    else:
        raise RuntimeError(f"Unsupported input type: {in_kind}")

    scale_y = sr_h // lr_h
    scale_x = sr_w // lr_w
    if scale_y < 1 or scale_x < 1:
        raise RuntimeError("Invalid model scale factor")

    return ModelProfile(
        adapter=adapter,
        input_name=input_name,
        output_name=output_name,
        lr_h=lr_h,
        lr_w=lr_w,
        sr_h=sr_h,
        sr_w=sr_w,
        scale_y=scale_y,
        scale_x=scale_x,
        input_kind=in_kind,
        output_kind=out_kind,
    )


class CoreMLUpscaler:
    def __init__(
        self,
        model_path: Path,
        compute_units: str,
        profile: ModelProfile,
        model_color_order: str = "rgb",
    ) -> None:
        cu_map = {
            "all": ct.ComputeUnit.ALL,
            "cpu_only": ct.ComputeUnit.CPU_ONLY,
            "cpu_and_gpu": ct.ComputeUnit.CPU_AND_GPU,
            "cpu_and_ne": ct.ComputeUnit.CPU_AND_NE,
        }
        if compute_units not in cu_map:
            raise ValueError(f"Unsupported compute unit: {compute_units}")
        if model_color_order not in ("rgb", "bgr"):
            raise ValueError("model_color_order must be 'rgb' or 'bgr'")

        self.profile = profile
        self.model_color_order = model_color_order
        self.model = ct.models.MLModel(str(model_path), compute_units=cu_map[compute_units])

    def _predict(self, model_input):
        try:
            return self.model.predict({self.profile.input_name: model_input})
        except Exception as exc:
            raise RuntimeError(
                "CoreML predict() failed. On macOS, try running outside restrictive sandbox "
                "and ensure CoreML runtime can create temp files."
            ) from exc

    def infer_tile(self, lr_hwc: np.ndarray) -> np.ndarray:
        p = self.profile

        if lr_hwc.shape != (p.lr_h, p.lr_w, 3):
            raise ValueError(
                f"Expected LR tile shape {p.lr_h}x{p.lr_w}x3, got {lr_hwc.shape}"
            )
        model_in_hwc = lr_hwc if self.model_color_order == "rgb" else lr_hwc[:, :, ::-1]

        if p.adapter == "multiarray_12ch_pixelunshuffle2":
            up_bicubic = np.array(
                Image.fromarray(hwc_float_to_uint8(model_in_hwc), mode="RGB").resize(
                    (p.sr_w, p.sr_h), Image.Resampling.BICUBIC
                ),
                dtype=np.float32,
            ) / 255.0
            model_in = pixel_unshuffle_2x(up_bicubic)[None, :, :, :].astype(np.float32)
            pred = self._predict(model_in)

        elif p.adapter == "multiarray_3ch_direct":
            model_in = model_in_hwc.transpose(2, 0, 1)[None, :, :, :].astype(np.float32)
            pred = self._predict(model_in)

        elif p.adapter == "image_direct":
            model_in = Image.fromarray(hwc_float_to_uint8(model_in_hwc), mode="RGB")
            pred = self._predict(model_in)

        else:
            raise RuntimeError(f"Unsupported adapter: {p.adapter}")

        out_obj = pred[p.output_name]

        if p.output_kind == "imageType":
            if isinstance(out_obj, Image.Image):
                arr = np.asarray(out_obj.convert("RGB"), dtype=np.float32)
            else:
                arr = np.asarray(out_obj, dtype=np.float32)
                if arr.ndim == 3 and arr.shape[2] >= 3:
                    arr = arr[:, :, :3]
                elif arr.ndim == 3 and arr.shape[0] >= 3:
                    arr = arr[:3, :, :].transpose(1, 2, 0)
                else:
                    raise RuntimeError(f"Unsupported image output array shape: {arr.shape}")
            arr = _normalize_output_hwc(arr)
            if arr.shape[:2] != (p.sr_h, p.sr_w):
                raise RuntimeError(
                    f"Unexpected output image size: {arr.shape[1]}x{arr.shape[0]}, expected {p.sr_w}x{p.sr_h}"
                )
            return arr

        out = np.asarray(out_obj, dtype=np.float32)
        if out.ndim == 4:
            out = out[0]

        if out.ndim != 3:
            raise RuntimeError(f"Unexpected output tensor shape {out.shape}")

        if out.shape[0] >= 3 and out.shape[1] == p.sr_h and out.shape[2] == p.sr_w:
            out_hwc = out[:3].transpose(1, 2, 0)
        elif out.shape[2] >= 3 and out.shape[0] == p.sr_h and out.shape[1] == p.sr_w:
            out_hwc = out[:, :, :3]
        else:
            raise RuntimeError(
                f"Unexpected output tensor layout/shape {out.shape}; expected CHW or HWC for {p.sr_h}x{p.sr_w}"
            )

        out_hwc = _normalize_output_hwc(out_hwc)
        if self.model_color_order == "bgr":
            out_hwc = out_hwc[:, :, ::-1]
        return out_hwc


def process_frame_full(upscaler: CoreMLUpscaler, frame: np.ndarray, force_resize: bool) -> np.ndarray:
    p = upscaler.profile
    h, w, _ = frame.shape

    if h == p.lr_h and w == p.lr_w:
        return upscaler.infer_tile(frame)

    if not force_resize:
        raise RuntimeError(
            f"Full mode requires {p.lr_w}x{p.lr_h} input frames for this model, got {w}x{h}. "
            "Use tiled mode for arbitrary resolutions."
        )

    resized = np.array(
        Image.fromarray(hwc_float_to_uint8(frame), mode="RGB").resize(
            (p.lr_w, p.lr_h), Image.Resampling.BICUBIC
        ),
        dtype=np.float32,
    ) / 255.0

    out_native = upscaler.infer_tile(resized)
    target_size = (w * p.scale_x, h * p.scale_y)
    out_resized = np.array(
        Image.fromarray(hwc_float_to_uint8(out_native), mode="RGB").resize(
            target_size, Image.Resampling.BICUBIC
        ),
        dtype=np.float32,
    ) / 255.0
    return out_resized


def process_frame_tiled(upscaler: CoreMLUpscaler, frame: np.ndarray, overlap: int) -> np.ndarray:
    p = upscaler.profile
    h, w, _ = frame.shape

    tile_h = p.lr_h
    tile_w = p.lr_w

    if overlap < 0:
        raise ValueError("overlap must be >= 0")
    if overlap >= tile_h or overlap >= tile_w:
        raise ValueError(f"overlap must be < tile size ({tile_w}x{tile_h})")

    pad_h = max(0, tile_h - h)
    pad_w = max(0, tile_w - w)
    if pad_h > 0 or pad_w > 0:
        frame = np.pad(frame, ((0, pad_h), (0, pad_w), (0, 0)), mode="edge")

    hp, wp, _ = frame.shape
    step_h = tile_h - overlap if overlap > 0 else tile_h
    step_w = tile_w - overlap if overlap > 0 else tile_w

    ys = positions_for_length(hp, tile_h, step_h)
    xs = positions_for_length(wp, tile_w, step_w)

    out_hp = hp * p.scale_y
    out_wp = wp * p.scale_x

    accum = np.zeros((out_hp, out_wp, 3), dtype=np.float32)
    weight = np.zeros((out_hp, out_wp, 1), dtype=np.float32)

    fade_h = overlap * p.scale_y
    fade_w = overlap * p.scale_x

    for y in ys:
        for x in xs:
            lr_tile = frame[y : y + tile_h, x : x + tile_w, :]
            sr_tile = upscaler.infer_tile(lr_tile)

            y2 = y * p.scale_y
            x2 = x * p.scale_x

            mask = make_weight_mask(
                p.sr_h,
                p.sr_w,
                fade_h,
                fade_w,
                top=y > 0,
                bottom=(y + tile_h) < hp,
                left=x > 0,
                right=(x + tile_w) < wp,
            )[:, :, None]

            accum[y2 : y2 + p.sr_h, x2 : x2 + p.sr_w, :] += sr_tile * mask
            weight[y2 : y2 + p.sr_h, x2 : x2 + p.sr_w, :] += mask

    out = accum / np.maximum(weight, 1e-8)
    out = out[: h * p.scale_y, : w * p.scale_x, :]
    return out


def has_audio_stream(input_path: Path) -> bool:
    cmd = [
        "ffprobe",
        "-v",
        "error",
        "-select_streams",
        "a",
        "-show_entries",
        "stream=index",
        "-of",
        "csv=p=0",
        str(input_path),
    ]
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if proc.returncode != 0:
        return False
    return bool(proc.stdout.strip())


def parse_args() -> argparse.Namespace:
    default_workers = max(1, min(8, os.cpu_count() or 4))
    ap = argparse.ArgumentParser(description="Upscale video using CoreML model")
    ap.add_argument("--input", required=True, help="Input video path")
    ap.add_argument("--output", required=True, help="Output video path")
    ap.add_argument("--model", required=True, help="Path to .mlpackage model")
    ap.add_argument("--work-dir", required=True, help="Working directory")
    ap.add_argument("--mode", choices=["full", "tiled"], required=True, help="Inference mode")
    ap.add_argument("--overlap", type=int, default=32, help="Tile overlap in LR pixels for tiled mode")
    ap.add_argument(
        "--compute-units",
        default="all",
        choices=["all", "cpu_only", "cpu_and_gpu", "cpu_and_ne"],
        help="CoreML compute units",
    )
    ap.add_argument("--codec", default="libx264", help="Output video codec (default: libx264)")
    ap.add_argument("--crf", default="18", help="CRF for libx264/libx265 style encoders")
    ap.add_argument("--preset", default="slow", help="Encoder preset")
    ap.add_argument("--pix-fmt", default="yuv420p", help="Output pixel format")
    ap.add_argument("--video-bitrate", default=os.environ.get("VIDEO_BITRATE", ""), help="Video bitrate (e.g. 12M), useful for hardware codecs")
    ap.add_argument("--video-maxrate", default=os.environ.get("VIDEO_MAXRATE", ""), help="Video maxrate override")
    ap.add_argument("--video-bufsize", default=os.environ.get("VIDEO_BUFSIZE", ""), help="Video bufsize override")
    ap.add_argument(
        "--videotoolbox-realtime",
        default=os.environ.get("VIDEOTOOLBOX_REALTIME", "false"),
        choices=["true", "false"],
        help="Set -realtime for *_videotoolbox encoders",
    )
    ap.add_argument(
        "--videotoolbox-allow-sw",
        default=os.environ.get("VIDEOTOOLBOX_ALLOW_SW", "1"),
        choices=["0", "1"],
        help="Allow software fallback for *_videotoolbox encoders (ffmpeg -allow_sw)",
    )
    ap.add_argument(
        "--force-resize",
        action="store_true",
        help="In full mode, resize non-native frames to model size then back to upscaled source size",
    )
    ap.add_argument(
        "--target-upscale",
        type=float,
        default=float(os.environ.get("TARGET_UPSCALE", "0")),
        help="Final upscale factor. 0 uses model-native scale; e.g. set 2 for x2 output from an x4 model.",
    )
    ap.add_argument(
        "--model-color-order",
        default=os.environ.get("MODEL_COLOR_ORDER", "rgb"),
        choices=["rgb", "bgr"],
        help="Channel order expected by the model input/output path",
    )
    ap.add_argument(
        "--workers",
        type=int,
        default=int(os.environ.get("FRAME_WORKERS", default_workers)),
        help="Frame worker threads for model inference (default: min(8, cpu_count))",
    )
    ap.add_argument(
        "--max-inflight",
        type=int,
        default=int(os.environ.get("FRAME_MAX_INFLIGHT", 0)),
        help="Maximum in-flight frames; 0 means auto (workers*3)",
    )
    ap.add_argument(
        "--progress-every",
        type=int,
        default=20,
        help="Print progress every N encoded frames",
    )
    ap.add_argument("--keep-work", action="store_true", help="Keep intermediate encoded video in work-dir")
    return ap.parse_args()


def main() -> int:
    args = parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()
    model_path = Path(args.model).expanduser().resolve()
    work_dir = Path(args.work_dir).expanduser().resolve()

    if not input_path.is_file():
        print(f"Error: input file not found: {input_path}", file=sys.stderr)
        return 1
    if not model_path.exists():
        print(f"Error: model not found: {model_path}", file=sys.stderr)
        return 1

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            print(f"Error: required tool not found in PATH: {tool}", file=sys.stderr)
            return 2

    output_path.parent.mkdir(parents=True, exist_ok=True)
    work_dir.mkdir(parents=True, exist_ok=True)

    tmp_video = work_dir / "video_no_audio.mp4"

    decode_proc = None
    encode_proc = None
    decode_err_buf: list[bytes] = []
    encode_err_buf: list[bytes] = []
    decode_err_thread = None
    encode_err_thread = None

    try:
        width, height, fps = probe_video(input_path)
        profile = read_model_profile(model_path)

        model_native_scale = float(min(profile.scale_x, profile.scale_y))
        if args.target_upscale <= 0:
            target_upscale = model_native_scale
        else:
            target_upscale = float(args.target_upscale)
        if target_upscale < 1.0:
            raise RuntimeError("--target-upscale must be >= 1")
        if target_upscale > model_native_scale:
            raise RuntimeError(
                f"--target-upscale ({target_upscale}) cannot exceed model-native scale ({model_native_scale})"
            )

        if args.workers < 1:
            raise RuntimeError("--workers must be >= 1")
        max_inflight = args.max_inflight if args.max_inflight > 0 else max(args.workers * 3, 4)
        if max_inflight < 1:
            raise RuntimeError("--max-inflight must be >= 1")

        print(f"Input video: {input_path}")
        print(f"Source size: {width}x{height}")
        print(f"Source fps : {fps}")
        print(f"Mode       : {args.mode}")
        print(f"Model      : {model_path}")
        print(f"Work dir   : {work_dir}")
        print(f"Workers    : {args.workers}")
        print(f"In-flight  : {max_inflight}")
        print(f"Adapter    : {profile.adapter}")
        print(f"Model tile : {profile.lr_w}x{profile.lr_h} -> {profile.sr_w}x{profile.sr_h}")
        print(f"Scale      : x{profile.scale_x} (w), x{profile.scale_y} (h)")
        print(f"Color order: {args.model_color_order}")
        print(f"Target upsc: x{target_upscale:g}")

        if args.mode == "full" and not args.force_resize and (width != profile.lr_w or height != profile.lr_h):
            raise RuntimeError(
                f"Full mode requires {profile.lr_w}x{profile.lr_h} source for this model, got {width}x{height}. "
                "Use tiled mode or --force-resize."
            )

        out_w = int(round(width * target_upscale))
        out_h = int(round(height * target_upscale))
        in_frame_bytes = width * height * 3

        decode_cmd = [
            "ffmpeg",
            "-hide_banner",
            "-nostdin",
            "-i",
            str(input_path),
            "-map",
            "0:v:0",
            "-vsync",
            "0",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-",
        ]
        codec_lower = args.codec.lower()
        codec_args: list[str]
        if codec_lower in ("libx264", "libx265"):
            codec_args = [
                "-c:v",
                args.codec,
                "-crf",
                str(args.crf),
                "-preset",
                args.preset,
                "-pix_fmt",
                args.pix_fmt,
            ]
        elif codec_lower == "ffv1":
            codec_args = [
                "-c:v",
                "ffv1",
                "-level",
                "3",
                "-pix_fmt",
                args.pix_fmt,
            ]
        elif codec_lower.endswith("_videotoolbox"):
            bitrate = args.video_bitrate or "12M"
            maxrate = args.video_maxrate or bitrate
            codec_args = [
                "-c:v",
                args.codec,
                "-b:v",
                bitrate,
                "-maxrate",
                maxrate,
                "-pix_fmt",
                args.pix_fmt,
                "-realtime",
                args.videotoolbox_realtime,
                "-allow_sw",
                args.videotoolbox_allow_sw,
            ]
            if args.video_bufsize:
                codec_args.extend(["-bufsize", args.video_bufsize])
            if codec_lower == "h264_videotoolbox":
                codec_args.extend(["-tag:v", "avc1"])
            elif codec_lower == "hevc_videotoolbox":
                codec_args.extend(["-tag:v", "hvc1"])
            elif codec_lower == "av1_videotoolbox":
                codec_args.extend(["-tag:v", "av01"])
        else:
            codec_args = [
                "-c:v",
                args.codec,
                "-pix_fmt",
                args.pix_fmt,
            ]

        encode_cmd = [
            "ffmpeg",
            "-hide_banner",
            "-nostdin",
            "-y",
            "-f",
            "rawvideo",
            "-pix_fmt",
            "rgb24",
            "-s:v",
            f"{out_w}x{out_h}",
            "-r",
            fps,
            "-i",
            "-",
            "-an",
            *codec_args,
            str(tmp_video),
        ]

        decode_proc = subprocess.Popen(
            decode_cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )
        encode_proc = subprocess.Popen(
            encode_cmd,
            stdin=subprocess.PIPE,
            stderr=subprocess.PIPE,
            bufsize=0,
        )

        if decode_proc.stdout is None or encode_proc.stdin is None:
            raise RuntimeError("Failed to create ffmpeg IO pipes")

        decode_err_buf, decode_err_thread = drain_pipe_async(decode_proc.stderr)
        encode_err_buf, encode_err_thread = drain_pipe_async(encode_proc.stderr)

        thread_local = threading.local()

        def get_upscaler() -> CoreMLUpscaler:
            up = getattr(thread_local, "upscaler", None)
            if up is None:
                up = CoreMLUpscaler(
                    model_path=model_path,
                    compute_units=args.compute_units,
                    profile=profile,
                    model_color_order=args.model_color_order,
                )
                thread_local.upscaler = up
            return up

        def process_frame_bytes(frame_bytes: bytes) -> bytes:
            frame = (
                np.frombuffer(frame_bytes, dtype=np.uint8)
                .reshape((height, width, 3))
                .astype(np.float32)
                / 255.0
            )

            upscaler = get_upscaler()
            if args.mode == "full":
                out = process_frame_full(upscaler, frame, force_resize=args.force_resize)
            else:
                out = process_frame_tiled(upscaler, frame, overlap=args.overlap)

            if target_upscale != model_native_scale:
                target_size = (int(round(width * target_upscale)), int(round(height * target_upscale)))
                out = (
                    np.array(
                        Image.fromarray(hwc_float_to_uint8(out), mode="RGB").resize(
                            target_size, Image.Resampling.LANCZOS
                        ),
                        dtype=np.float32,
                    )
                    / 255.0
                )

            return hwc_float_to_uint8(out).tobytes()

        inflight = threading.Semaphore(max_inflight)
        cond = threading.Condition()
        results: dict[int, bytes] = {}
        err_holder: list[Exception] = []
        submitted = 0
        reader_done = False
        written = 0

        def set_error(exc: Exception) -> None:
            with cond:
                if not err_holder:
                    err_holder.append(exc)
                cond.notify_all()

        def on_done(idx: int, fut) -> None:
            try:
                data = fut.result()
            except Exception as exc:  # pragma: no cover - worker failure path
                set_error(exc)
            else:
                with cond:
                    results[idx] = data
                    cond.notify_all()
            finally:
                inflight.release()

        def writer_loop() -> None:
            nonlocal written
            next_idx = 1
            assert encode_proc is not None and encode_proc.stdin is not None
            while True:
                with cond:
                    while True:
                        if err_holder:
                            return
                        if next_idx in results:
                            data = results.pop(next_idx)
                            next_idx += 1
                            break
                        if reader_done and next_idx > submitted:
                            return
                        cond.wait(timeout=0.2)
                try:
                    encode_proc.stdin.write(data)
                except Exception as exc:
                    set_error(RuntimeError(f"Failed to write frame to encoder: {exc}"))
                    return

                written += 1
                if args.progress_every > 0 and (written % args.progress_every == 0):
                    print(f"Encoded {written} frame(s) ...")

        writer = threading.Thread(target=writer_loop, daemon=True)
        writer.start()

        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            while True:
                with cond:
                    if err_holder:
                        break

                frame_bytes = read_exact(decode_proc.stdout, in_frame_bytes)
                if frame_bytes is None:
                    break

                inflight.acquire()
                submitted += 1
                fut = executor.submit(process_frame_bytes, frame_bytes)
                fut.add_done_callback(lambda f, idx=submitted: on_done(idx, f))

            with cond:
                reader_done = True
                cond.notify_all()

            writer.join()

            if encode_proc.stdin:
                try:
                    encode_proc.stdin.close()
                except Exception:
                    pass

            if err_holder:
                raise err_holder[0]

        decode_rc = decode_proc.wait()
        if decode_rc != 0:
            stderr_text = b"".join(decode_err_buf).decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"ffmpeg decode failed (exit {decode_rc}). {stderr_text}")

        encode_rc = encode_proc.wait()
        if encode_rc != 0:
            stderr_text = b"".join(encode_err_buf).decode("utf-8", errors="replace").strip()
            raise RuntimeError(f"ffmpeg encode failed (exit {encode_rc}). {stderr_text}")

        print(f"Pipeline complete. Frames submitted: {submitted}, frames encoded: {written}")

        if has_audio_stream(input_path):
            run_cmd(
                [
                    "ffmpeg",
                    "-hide_banner",
                    "-nostdin",
                    "-y",
                    "-i",
                    str(tmp_video),
                    "-i",
                    str(input_path),
                    "-map",
                    "0:v:0",
                    "-map",
                    "1:a?",
                    "-c:v",
                    "copy",
                    "-c:a",
                    "copy",
                    "-shortest",
                    str(output_path),
                ]
            )
        else:
            shutil.copy2(tmp_video, output_path)

        print(f"Done: {output_path}")
        return 0

    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 3

    finally:
        if decode_proc is not None and decode_proc.poll() is None:
            decode_proc.kill()
        if encode_proc is not None and encode_proc.poll() is None:
            encode_proc.kill()
        if decode_err_thread is not None:
            decode_err_thread.join(timeout=1.0)
        if encode_err_thread is not None:
            encode_err_thread.join(timeout=1.0)

        if not args.keep_work and tmp_video.exists():
            tmp_video.unlink(missing_ok=True)


if __name__ == "__main__":
    sys.exit(main())
