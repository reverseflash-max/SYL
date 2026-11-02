# Video Shrinker

A small Windows app that makes 1080p (or bigger) videos smaller by converting
them to **720p or 480p**. The aspect ratio always stays the same. Add a few
files or a whole folder, try a 30-second sample to check the quality, then
shrink the lot.

## Getting it

**Easiest: download the ready-made build.** Go to the repository's
*Releases* page, open **Video Shrinker (latest build)**, download
`VideoShrinker-windows.zip`, unzip it anywhere and double-click
`VideoShrinker.exe`. ffmpeg is included in the zip, so there's nothing else to install.

> Windows SmartScreen may say "Windows protected your PC" because the exe
> isn't code-signed. Click **More info → Run anyway**.

**Or run it from source** (Python 3.10+):

```bash
winget install Gyan.FFmpeg
```

```bash
python video_shrinker.py
```

## Using it

1. **Add files…** or **Add folder…** (subfolders are included). The *Now*
   column shows each video's resolution, codecs, length and size.
2. Pick **720p** or **480p**. Videos already at that size or smaller are skipped.
3. Select one video and click **Test 30-second sample**. It encodes 30 seconds
   from the middle of the video and tells you roughly how big the whole file
   would be. Double-click the row to watch it.
4. Happy with it? Click **Shrink all**. The new files go into a `shrunk` folder
   next to each original (or a folder you choose), named like `holiday_720p.mp4`.
   **Your originals are never changed or deleted.** Once you've checked the new
   files, deleting the originals is up to you.

## What the settings mean

| Setting | Recommendation | Why |
|---|---|---|
| **Resolution** | 720p for TV/laptop, 480p for phone viewing | 720p has about 44% of the pixels of 1080p, and 480p has about 20%. |
| **Video codec** | H.264 if the files must play everywhere; H.265 for the smallest files | At the same quality, H.265 is usually 30–50% smaller but encodes 2–4× slower. Older TVs and devices may not play it. |
| **Quality (CRF)** | Leave it at the default (23 for H.264, 26 for H.265) | Lower numbers look better and make bigger files. Each step of ±6 roughly doubles or halves the size. 18 looks almost identical to the source and 28+ starts to look soft. |
| **Speed** | `medium`; use `fast` if you have a lot of files | Slower presets squeeze out a few more percent but take much longer. Quality stays about the same because CRF controls it. |
| **Audio** | AAC 128 kbps | See below. |

## Should you halve the audio bitrate?

**Usually it's not worth it. Audio is a tiny part of the file.**

For a 1-hour video:

| | bitrate | size per hour |
|---|---|---|
| Typical 1080p video track | 5,000–10,000 kbps | 2.2–4.4 GB |
| 720p video after shrinking (H.264, CRF 23) | ~1,500–3,000 kbps | 0.7–1.3 GB |
| Audio at 192 kbps | 192 kbps | 86 MB |
| Audio at 128 kbps | 128 kbps | 58 MB |
| Audio at 96 kbps | 96 kbps | 43 MB |

Cutting audio from 192 to 96 kbps saves about 43 MB per hour. That's around 4%
of an already-shrunk file, and most of the time you'll hear the difference
before you notice the space saved. **AAC at 128 kbps stereo** is generally
indistinguishable from the original for normal viewing, so it's the default.

The app also:
- **won't raise** the bitrate of audio that's already small AAC (it copies it instead),
- mixes **5.1 surround down to stereo** when re-encoding, since squeezing six
  channels into 128 kbps sounds worse than good stereo. Pick
  *Keep original audio (copy)* if you want to keep the surround track.

## Good to know

- **Re-encoding loses some quality every time.** Always work from the
  original, never from a file that's already been shrunk.
- Some videos are already heavily compressed (many phone or streaming
  downloads). For those, the result can come out barely smaller or even
  bigger. The app warns you when that happens, and you should just keep the original.
- Output is always `.mp4`, which plays on almost everything. The exception is
  when you copy an audio format MP4 can't hold; then the output is `.mkv`.
- Portrait phone videos stay portrait: "720p" means the short side becomes 720.

## For developers

- `shrink_core.py`: probing, building the ffmpeg command, running it, progress. No GUI code.
- `video_shrinker.py`: the tkinter window.
- `test_shrink_core.py`: `python -m unittest test_shrink_core` (the end-to-end tests need ffmpeg).
- `build_exe.bat`: builds `dist\VideoShrinker.exe` locally with PyInstaller.
- `.github/workflows/video-shrinker.yml` builds the Windows zip on every change
  to this folder and publishes it as the `video-shrinker-latest` release.

The bundled ffmpeg is the GPL build from gyan.dev. That's fine for personal
use, but read its licence before you distribute the zip.
