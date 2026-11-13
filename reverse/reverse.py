#!/usr/bin/env python3
"""Reverse a video and its audio.

    python reverse.py INPUT [OUTPUT]

OUTPUT defaults to INPUT's name with "_reversed" added, e.g. clip.mp4 -> clip_reversed.mp4.
Needs ffmpeg and ffprobe on PATH.

Long videos are reversed in short pieces so memory use stays small: each piece is reversed
on its own, then the pieces are joined in reverse order.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile

CHUNK_SECONDS = 10


def fail(message):
    sys.exit(f"error: {message}")


def run(cmd):
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if result.returncode != 0:
        fail(f"{cmd[0]} failed:\n{result.stderr.strip()[-2000:]}")
    return result.stdout


def probe(path):
    out = run(["ffprobe", "-v", "error", "-show_format", "-show_streams", "-of", "json", path])
    info = json.loads(out)
    types = {s.get("codec_type") for s in info.get("streams", [])}
    try:
        duration = float(info["format"]["duration"])
    except (KeyError, ValueError):
        fail("could not read the input's duration")
    return duration, "video" in types, "audio" in types


def main():
    if len(sys.argv) not in (2, 3) or sys.argv[1] in ("-h", "--help"):
        sys.exit(__doc__)

    src = sys.argv[1]
    if not os.path.isfile(src):
        fail(f"no such file: {src}")
    base, ext = os.path.splitext(src)
    dst = sys.argv[2] if len(sys.argv) == 3 else f"{base}_reversed{ext or '.mp4'}"
    if os.path.abspath(dst) == os.path.abspath(src):
        fail("output must be a different file from the input")

    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            fail(f"{tool} not found; install ffmpeg (https://ffmpeg.org/download.html)")

    duration, has_video, has_audio = probe(src)
    if not has_video and not has_audio:
        fail("input has no video or audio")

    with tempfile.TemporaryDirectory() as tmp:
        pieces = []
        start, i = 0.0, 0
        while start < duration:
            piece = os.path.join(tmp, f"{i:05d}.mkv")
            cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{start:.3f}", "-t", str(CHUNK_SECONDS), "-i", src]
            if has_video:
                cmd += ["-map", "0:v:0", "-vf", "reverse",
                        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18", "-pix_fmt", "yuv420p"]
            if has_audio:
                cmd += ["-map", "0:a:0", "-af", "areverse", "-c:a", "pcm_s16le"]
            run(cmd + [piece])
            pieces.append(piece)
            start += CHUNK_SECONDS
            i += 1
            print(f"\rreversing... {min(start, duration) / duration:4.0%}", end="", flush=True)
        print()

        listing = os.path.join(tmp, "list.txt")
        with open(listing, "w") as f:
            for piece in reversed(pieces):
                f.write(f"file '{piece}'\n")

        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", listing]
        if has_video:
            cmd += ["-c:v", "copy"]
        if has_audio and has_video:
            cmd += ["-c:a", "aac", "-b:a", "192k"]
        if dst.lower().endswith((".mp4", ".mov", ".m4v")):
            cmd += ["-movflags", "+faststart"]
        run(cmd + [dst])

    print(f"saved {dst}")


if __name__ == "__main__":
    main()
