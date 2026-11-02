@echo off
rem Builds dist\VideoShrinker.exe. Needs Python on PATH.
rem Put ffmpeg.exe and ffprobe.exe next to the exe afterwards (or have ffmpeg on PATH).
cd /d "%~dp0"
python -m pip install --upgrade pyinstaller || exit /b 1
python -m PyInstaller --noconfirm --onefile --windowed --name VideoShrinker video_shrinker.py || exit /b 1
echo.
echo Built dist\VideoShrinker.exe
