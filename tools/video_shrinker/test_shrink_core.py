"""Tests for shrink_core.  Run:  python -m unittest test_shrink_core   (from this folder)

The end-to-end tests make tiny videos with ffmpeg and are skipped without it.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import shrink_core as core


def info(w, h, rotation=0, audio="aac", akbps=192, ch=2):
    return core.VideoInfo(path=Path("C:/v/clip.mp4"), width=w, height=h, duration=60,
                          size_bytes=1, audio_codec=audio, audio_kbps=akbps,
                          audio_channels=ch, rotation=rotation)


class ScaleTests(unittest.TestCase):
    def test_landscape_scales_height(self):
        self.assertTrue(core.scale_filter(info(1920, 1080), 720).startswith("scale=-2:720"))

    def test_portrait_scales_width(self):
        self.assertTrue(core.scale_filter(info(1080, 1920), 720).startswith("scale=720:-2"))

    def test_rotated_phone_video_counts_as_portrait(self):
        v = info(1920, 1080, rotation=90)
        self.assertEqual(v.short_side, 1080)
        self.assertTrue(core.scale_filter(v, 480).startswith("scale=480:-2"))


class AudioTests(unittest.TestCase):
    def test_default_is_aac_128(self):
        self.assertEqual(core.audio_args(info(1920, 1080), core.AUDIO_MODES[0]),
                         ["-c:a", "aac", "-b:a", "128k"])

    def test_half(self):
        self.assertIn("96k", core.audio_args(info(1920, 1080, akbps=192), core.AUDIO_MODES[2]))

    def test_half_has_a_floor(self):
        self.assertIn("64k", core.audio_args(info(1920, 1080, audio="ac3", akbps=96), core.AUDIO_MODES[2]))

    def test_never_raises_bitrate_of_small_aac(self):
        self.assertEqual(core.audio_args(info(1920, 1080, akbps=96), core.AUDIO_MODES[0]),
                         ["-c:a", "copy"])

    def test_surround_is_folded_to_stereo(self):
        args = core.audio_args(info(1920, 1080, audio="ac3", akbps=448, ch=6), core.AUDIO_MODES[0])
        self.assertEqual(args[-2:], ["-ac", "2"])

    def test_no_audio(self):
        self.assertEqual(core.audio_args(info(1920, 1080, audio=""), core.AUDIO_MODES[0]), ["-an"])


class OutputPathTests(unittest.TestCase):
    def test_default_goes_to_shrunk_subfolder(self):
        out = core.output_path(info(1920, 1080), core.Settings(target_height=480))
        self.assertEqual(out, Path("C:/v/shrunk/clip_480p.mp4"))

    def test_copying_unusual_audio_uses_mkv(self):
        s = core.Settings(audio_mode=core.AUDIO_MODES[3])
        self.assertEqual(core.output_path(info(1920, 1080, audio="truehd"), s).suffix, ".mkv")


FFMPEG, FFPROBE = core.find_tool("ffmpeg"), core.find_tool("ffprobe")


@unittest.skipUnless(FFMPEG and FFPROBE, "ffmpeg not installed")
class EndToEndTests(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp())
        self.shrinker = core.Shrinker(FFMPEG, FFPROBE)

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def make(self, name, size, seconds=2):
        p = self.dir / name
        subprocess.run([FFMPEG, "-v", "error", "-y",
                        "-f", "lavfi", "-i", f"testsrc2=size={size}:rate=25",
                        "-f", "lavfi", "-i", "sine", "-t", str(seconds),
                        "-c:v", "libx264", "-b:v", "6M", "-c:a", "aac", "-b:a", "192k",
                        str(p)], check=True)
        return p

    def test_shrinks_and_keeps_aspect(self):
        for size, target, expect in [("1920x1080", 720, (1280, 720)),
                                     ("1080x1920", 480, (480, 854)),
                                     ("1920x800", 720, (1728, 720))]:
            src = self.make(f"v{size}.mp4", size)
            progress = []
            res = self.shrinker.shrink(src, core.Settings(target_height=target, preset="veryfast"),
                                       progress.append)
            self.assertEqual(res.status, "done", res.message)
            out = core.probe(res.output, FFPROBE)
            self.assertEqual((out.width, out.height), expect)
            self.assertLess(res.after_bytes, res.before_bytes)
            self.assertEqual(progress[-1], 1.0)

    def test_skips_small_files(self):
        src = self.make("small.mp4", "854x480")
        res = self.shrinker.shrink(src, core.Settings(target_height=720))
        self.assertEqual(res.status, "skipped")

    def test_collect_ignores_own_output(self):
        self.make("a.mp4", "640x360", 1)
        (self.dir / "shrunk").mkdir()
        (self.dir / "shrunk" / "a_720p.mp4").write_bytes(b"x")
        self.assertEqual([p.name for p in core.collect_videos([self.dir])], ["a.mp4"])


if __name__ == "__main__":
    unittest.main()
