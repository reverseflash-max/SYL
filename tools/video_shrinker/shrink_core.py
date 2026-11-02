"""Video Shrinker core: everything that talks to ffmpeg, with no GUI.

The GUI (video_shrinker.py) and the tests both use this module.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

VIDEO_EXTENSIONS = {
    ".mp4", ".mkv", ".mov", ".avi", ".wmv", ".m4v", ".webm", ".flv",
    ".mpg", ".mpeg", ".ts", ".m2ts", ".mts", ".3gp",
}

# Hide the black console window that would flash up for every ffmpeg run on Windows.
_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


# --------------------------------------------------------------------------- #
# Finding ffmpeg
# --------------------------------------------------------------------------- #

def _app_dir() -> Path:
    """Folder the program lives in (works for a PyInstaller .exe too)."""
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def find_tool(name: str) -> Optional[str]:
    """Find ffmpeg / ffprobe: next to the app first, then on PATH."""
    exe = name + (".exe" if os.name == "nt" else "")
    for folder in (_app_dir(), _app_dir() / "ffmpeg", _app_dir() / "ffmpeg" / "bin"):
        candidate = folder / exe
        if candidate.is_file():
            return str(candidate)
    return shutil.which(name)


# --------------------------------------------------------------------------- #
# Inspecting a file
# --------------------------------------------------------------------------- #

@dataclass
class VideoInfo:
    path: Path
    width: int
    height: int
    duration: float          # seconds
    size_bytes: int
    video_codec: str = ""
    video_kbps: Optional[int] = None
    audio_codec: str = ""
    audio_kbps: Optional[int] = None
    audio_channels: Optional[int] = None
    rotation: int = 0        # phone videos are often stored sideways + a rotate flag

    @property
    def display_width(self) -> int:
        return self.height if self.rotation in (90, 270) else self.width

    @property
    def display_height(self) -> int:
        return self.width if self.rotation in (90, 270) else self.height

    @property
    def short_side(self) -> int:
        """'1080p' means the short side is 1080 (also for portrait phone videos)."""
        return min(self.display_width, self.display_height)

    def describe(self) -> str:
        parts = [f"{self.display_width}x{self.display_height}"]
        if self.video_codec:
            parts.append(self.video_codec)
        if self.audio_codec:
            a = self.audio_codec
            if self.audio_kbps:
                a += f" {self.audio_kbps} kbps"
            parts.append(a)
        parts.append(format_duration(self.duration))
        parts.append(format_size(self.size_bytes))
        return ", ".join(parts)


def _int(v) -> Optional[int]:
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return None


def probe(path: Path, ffprobe: str) -> VideoInfo:
    """Read resolution, duration and stream details with ffprobe."""
    cmd = [ffprobe, "-v", "error", "-print_format", "json",
           "-show_format", "-show_streams", str(path)]
    out = subprocess.run(cmd, capture_output=True, text=True,
                         encoding="utf-8", errors="replace",
                         creationflags=_NO_WINDOW)
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "ffprobe could not read this file")
    data = json.loads(out.stdout or "{}")
    streams = data.get("streams", [])
    fmt = data.get("format", {})

    video = next((s for s in streams if s.get("codec_type") == "video"
                  and not s.get("disposition", {}).get("attached_pic")), None)
    if video is None:
        raise RuntimeError("no video stream found")
    audio = next((s for s in streams if s.get("codec_type") == "audio"), None)

    rotation = 0
    tag_rot = _int(video.get("tags", {}).get("rotate"))
    if tag_rot is not None:
        rotation = tag_rot
    for sd in video.get("side_data_list", []) or []:
        if "rotation" in sd:
            rotation = _int(sd["rotation"]) or 0
    rotation %= 360

    duration = float(fmt.get("duration") or video.get("duration") or 0)

    return VideoInfo(
        path=Path(path),
        width=_int(video.get("width")) or 0,
        height=_int(video.get("height")) or 0,
        duration=duration,
        size_bytes=_int(fmt.get("size")) or Path(path).stat().st_size,
        video_codec=video.get("codec_name", ""),
        video_kbps=(_int(video.get("bit_rate")) or 0) // 1000 or None,
        audio_codec=audio.get("codec_name", "") if audio else "",
        audio_kbps=((_int(audio.get("bit_rate")) or 0) // 1000 or None) if audio else None,
        audio_channels=_int(audio.get("channels")) if audio else None,
        rotation=rotation,
    )


# --------------------------------------------------------------------------- #
# Settings and building the ffmpeg command
# --------------------------------------------------------------------------- #

# Codec label -> (ffmpeg encoder, sensible default CRF).  Lower CRF = better/bigger.
CODECS = {
    "H.264 (plays everywhere)": ("libx264", 23),
    "H.265 / HEVC (~40% smaller, slower)": ("libx265", 26),
}

PRESETS = ["veryfast", "faster", "fast", "medium", "slow"]

# Audio label -> list of ffmpeg args (bitrate decided at run time for "half").
AUDIO_MODES = [
    "AAC 128 kbps (recommended)",
    "AAC 96 kbps (smaller)",
    "Half the original bitrate",
    "Keep original audio (copy)",
]


@dataclass
class Settings:
    target_height: int = 720               # 720 or 480 (the short side)
    codec_label: str = next(iter(CODECS))
    crf: Optional[int] = None              # None = codec default
    preset: str = "medium"
    audio_mode: str = AUDIO_MODES[0]
    output_dir: Optional[Path] = None      # None = "<source folder>/shrunk"
    suffix: str = ""                       # e.g. "_720p"; "" = auto
    skip_if_not_larger: bool = True        # don't touch files already <= target
    overwrite: bool = False
    sample_seconds: Optional[int] = None   # encode only a clip, to preview quality

    @property
    def encoder(self) -> str:
        return CODECS[self.codec_label][0]

    @property
    def effective_crf(self) -> int:
        return self.crf if self.crf is not None else CODECS[self.codec_label][1]


def scale_filter(info: VideoInfo, target: int) -> str:
    """Scale so the *short* side becomes `target`, keeping aspect ratio.

    -2 tells ffmpeg "work out this side from the aspect ratio, and keep it an
    even number" (H.264/H.265 need even dimensions).  ffmpeg auto-rotates phone
    videos before the filter, so we decide using the displayed orientation.
    """
    if info.display_width >= info.display_height:      # landscape / square
        return f"scale=-2:{target}:flags=lanczos"
    return f"scale={target}:-2:flags=lanczos"          # portrait


def audio_args(info: VideoInfo, mode: str) -> list[str]:
    if not info.audio_codec:
        return ["-an"]
    if mode.startswith("Keep"):
        return ["-c:a", "copy"]
    if mode.startswith("Half"):
        src = info.audio_kbps or 192   # unknown -> assume a typical 192k
        kbps = max(64, src // 2)
    elif "96" in mode:
        kbps = 96
    else:
        kbps = 128
    # Never "shrink" audio to a higher bitrate than it already has.
    if info.audio_kbps and info.audio_kbps < kbps and info.audio_codec == "aac":
        return ["-c:a", "copy"]
    args = ["-c:a", "aac", "-b:a", f"{kbps}k"]
    # Surround (5.1 etc) at 96-128k sounds poor; fold it to stereo.
    if (info.audio_channels or 2) > 2:
        args += ["-ac", "2"]
    return args


def output_path(info: VideoInfo, s: Settings) -> Path:
    out_dir = s.output_dir or (info.path.parent / "shrunk")
    suffix = s.suffix or f"_{s.target_height}p"
    if s.sample_seconds:
        suffix += "_sample"
    ext = ".mp4"
    # MP4 can't hold some audio formats when copying; fall back to MKV.
    if s.audio_mode.startswith("Keep") and info.audio_codec not in ("", "aac", "mp3", "ac3", "eac3", "opus", "alac", "flac"):
        ext = ".mkv"
    return out_dir / f"{info.path.stem}{suffix}{ext}"


def build_command(ffmpeg: str, info: VideoInfo, s: Settings, out: Path) -> list[str]:
    cmd = [ffmpeg, "-hide_banner", "-nostdin", "-y" if s.overwrite else "-n"]
    if s.sample_seconds:
        # Take the clip from the middle, where there's usually real action.
        start = max(0.0, info.duration / 2 - s.sample_seconds / 2)
        cmd += ["-ss", f"{start:.2f}"]
    cmd += ["-i", str(info.path)]
    if s.sample_seconds:
        cmd += ["-t", str(s.sample_seconds)]
    cmd += [
        "-map", "0:v:0", "-map", "0:a:0?",
        "-vf", scale_filter(info, s.target_height),
        "-c:v", s.encoder, "-crf", str(s.effective_crf), "-preset", s.preset,
        "-pix_fmt", "yuv420p",
    ]
    if s.encoder == "libx265":
        cmd += ["-tag:v", "hvc1", "-x265-params", "log-level=error"]  # hvc1: plays in Windows/Apple players
    cmd += audio_args(info, s.audio_mode)
    if out.suffix == ".mp4":
        cmd += ["-movflags", "+faststart"]
    cmd += ["-map_metadata", "0", "-progress", "pipe:1", "-nostats", str(out)]
    return cmd


# --------------------------------------------------------------------------- #
# Running a job
# --------------------------------------------------------------------------- #

@dataclass
class Result:
    source: Path
    output: Optional[Path] = None
    status: str = "done"         # done | skipped | failed | cancelled
    message: str = ""
    before_bytes: int = 0
    after_bytes: int = 0

    @property
    def saved_pct(self) -> float:
        if not self.before_bytes or not self.after_bytes:
            return 0.0
        return 100.0 * (1 - self.after_bytes / self.before_bytes)


class Shrinker:
    """Runs ffmpeg for one file at a time; can be cancelled from another thread."""

    def __init__(self, ffmpeg: str, ffprobe: str):
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self._proc: Optional[subprocess.Popen] = None
        self._cancelled = False

    def cancel(self) -> None:
        self._cancelled = True
        if self._proc and self._proc.poll() is None:
            try:
                self._proc.stdin and self._proc.stdin.close()
            except OSError:
                pass
            self._proc.terminate()

    def shrink(self, src: Path, s: Settings,
               on_progress: Callable[[float], None] = lambda f: None) -> Result:
        self._cancelled = False
        src = Path(src)
        res = Result(source=src)
        try:
            info = probe(src, self.ffprobe)
        except Exception as e:  # noqa: BLE001 - report anything to the user
            return Result(src, status="failed", message=f"Couldn't read file: {e}")
        res.before_bytes = info.size_bytes

        if s.skip_if_not_larger and info.short_side <= s.target_height:
            res.status = "skipped"
            res.message = f"already {info.short_side}p, not larger than {s.target_height}p"
            return res

        out = output_path(info, s)
        res.output = out
        if out.exists() and not s.overwrite:
            res.status = "skipped"
            res.message = f"output already exists: {out.name}"
            return res
        out.parent.mkdir(parents=True, exist_ok=True)

        total = float(s.sample_seconds or info.duration or 0)
        cmd = build_command(self.ffmpeg, info, s, out)
        tmp_log: list[str] = []
        self._proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace",
            creationflags=_NO_WINDOW,
        )

        # Collect stderr on a side thread so the pipe never fills up and blocks.
        import threading
        def _drain():
            for line in self._proc.stderr:  # type: ignore[union-attr]
                tmp_log.append(line)
                del tmp_log[:-40]
        t = threading.Thread(target=_drain, daemon=True)
        t.start()

        time_re = re.compile(r"^out_time_(?:us|ms)=(\d+)")
        for line in self._proc.stdout:  # type: ignore[union-attr]
            m = time_re.match(line.strip())
            if m and total > 0:
                on_progress(min(1.0, int(m.group(1)) / 1_000_000 / total))
        code = self._proc.wait()
        t.join(timeout=2)
        self._proc = None

        if self._cancelled:
            out.unlink(missing_ok=True)   # don't leave a half-written file behind
            res.status, res.message = "cancelled", "cancelled"
            return res
        if code != 0:
            out.unlink(missing_ok=True)
            res.status = "failed"
            res.message = "".join(tmp_log[-6:]).strip() or f"ffmpeg exit code {code}"
            return res

        on_progress(1.0)
        res.after_bytes = out.stat().st_size
        res.message = f"{format_size(res.before_bytes)} -> {format_size(res.after_bytes)}"
        if s.sample_seconds and info.duration:
            # Project what the whole file would be, so samples are useful.
            projected = res.after_bytes * info.duration / s.sample_seconds
            res.message = (f"{s.sample_seconds}s sample is {format_size(res.after_bytes)}; "
                           f"full file would be about {format_size(projected)} "
                           f"(now {format_size(res.before_bytes)})")
        if res.after_bytes >= res.before_bytes:
            res.message += ("  - NOT smaller: the original is already well compressed; "
                            "keep the original or try 480p / a higher CRF")
        return res


# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #

def collect_videos(paths: list[Path], recursive: bool = True) -> list[Path]:
    """Expand folders into the video files inside them."""
    found: list[Path] = []
    for p in paths:
        p = Path(p)
        if p.is_dir():
            it = p.rglob("*") if recursive else p.glob("*")
            for f in sorted(it):
                # Don't re-shrink our own output (the "shrunk" subfolders).
                if (f.is_file() and f.suffix.lower() in VIDEO_EXTENSIONS
                        and "shrunk" not in f.relative_to(p).parts[:-1]):
                    found.append(f)
        elif p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS:
            found.append(p)
    seen, unique = set(), []
    for f in found:
        if f not in seen:
            seen.add(f)
            unique.append(f)
    return unique


def format_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit in ("B", "KB") else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def format_duration(sec: float) -> str:
    sec = int(sec)
    h, rem = divmod(sec, 3600)
    m, s = divmod(rem, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"
