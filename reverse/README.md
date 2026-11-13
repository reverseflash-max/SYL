# reverse

Reverses a video and its audio. Nothing else.

## Requirements

- Python 3
- ffmpeg (includes ffprobe): https://ffmpeg.org/download.html
  - Windows: `winget install ffmpeg`
  - macOS: `brew install ffmpeg`
  - Linux: `sudo apt install ffmpeg`

## Use

```
python reverse.py input.mp4
```

Writes `input_reversed.mp4` next to the input. To pick the output name:

```
python reverse.py input.mp4 backwards.mp4
```

Audio-only files (e.g. `.mp3`) work too.
