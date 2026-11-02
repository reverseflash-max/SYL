"""Video Shrinker - a small Windows app that downsizes videos to 720p or 480p.

Run:  python video_shrinker.py      (needs ffmpeg; see README.md)
"""

from __future__ import annotations

import os
import queue
import subprocess
import sys
import threading
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

import shrink_core as core

APP_NAME = "Video Shrinker"


class App(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        self.title(APP_NAME)
        self.geometry("1060x660")
        self.minsize(820, 520)

        self.ffmpeg = core.find_tool("ffmpeg")
        self.ffprobe = core.find_tool("ffprobe")
        self.shrinker = (core.Shrinker(self.ffmpeg, self.ffprobe)
                         if self.ffmpeg and self.ffprobe else None)

        self.files: list[Path] = []
        self.events: "queue.Queue[tuple]" = queue.Queue()
        self.worker: threading.Thread | None = None
        self.stop_requested = False

        self._build_ui()
        self.after(100, self._pump_events)
        if not self.shrinker:
            self.after(300, self._ffmpeg_missing)

    # ------------------------------------------------------------------ UI --

    def _build_ui(self) -> None:
        pad = {"padx": 8, "pady": 4}

        # --- file list ---------------------------------------------------
        top = ttk.Frame(self)
        top.pack(fill="x", **pad)
        ttk.Button(top, text="Add files…", command=self.add_files).pack(side="left")
        ttk.Button(top, text="Add folder…", command=self.add_folder).pack(side="left", padx=4)
        ttk.Button(top, text="Remove selected", command=self.remove_selected).pack(side="left")
        ttk.Button(top, text="Clear", command=self.clear).pack(side="left", padx=4)
        self.count_lbl = ttk.Label(top, text="No files yet")
        self.count_lbl.pack(side="right")

        lst = ttk.Frame(self)
        lst.pack(fill="both", expand=True, **pad)
        cols = ("file", "info", "status")
        self.tree = ttk.Treeview(lst, columns=cols, show="headings", selectmode="extended")
        self.tree.heading("file", text="File")
        self.tree.heading("info", text="Now")
        self.tree.heading("status", text="Result")
        self.tree.column("file", width=300)
        self.tree.column("info", width=300)
        self.tree.column("status", width=340)
        sb = ttk.Scrollbar(lst, orient="vertical", command=self.tree.yview)
        self.tree.configure(yscrollcommand=sb.set)
        self.tree.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")
        self.tree.bind("<Double-1>", self._open_selected_output)

        # --- settings ----------------------------------------------------
        opts = ttk.LabelFrame(self, text="Settings")
        opts.pack(fill="x", **pad)

        ttk.Label(opts, text="Resolution:").grid(row=0, column=0, sticky="w", **pad)
        self.res_var = tk.IntVar(value=720)
        rf = ttk.Frame(opts)
        rf.grid(row=0, column=1, sticky="w")
        ttk.Radiobutton(rf, text="720p", value=720, variable=self.res_var).pack(side="left")
        ttk.Radiobutton(rf, text="480p", value=480, variable=self.res_var).pack(side="left", padx=8)
        ttk.Label(rf, text="(aspect ratio is always kept)", foreground="gray").pack(side="left")

        ttk.Label(opts, text="Video codec:").grid(row=1, column=0, sticky="w", **pad)
        self.codec_var = tk.StringVar(value=next(iter(core.CODECS)))
        codec_cb = ttk.Combobox(opts, textvariable=self.codec_var, values=list(core.CODECS),
                                state="readonly", width=30)
        codec_cb.grid(row=1, column=1, sticky="w")
        codec_cb.bind("<<ComboboxSelected>>", lambda e: self._reset_crf())

        ttk.Label(opts, text="Quality:").grid(row=2, column=0, sticky="w", **pad)
        qf = ttk.Frame(opts)
        qf.grid(row=2, column=1, sticky="w")
        self.crf_var = tk.IntVar(value=23)
        self.crf_lbl = ttk.Label(qf, width=16)
        self.crf_lbl.pack(side="left")
        ttk.Label(qf, text="better").pack(side="left")
        ttk.Scale(qf, from_=18, to=32, variable=self.crf_var, length=140,
                  command=lambda v: self._update_crf_label()).pack(side="left", padx=4)
        ttk.Label(qf, text="smaller").pack(side="left")

        ttk.Label(opts, text="Speed:").grid(row=0, column=2, sticky="w", **pad)
        self.preset_var = tk.StringVar(value="medium")
        ttk.Combobox(opts, textvariable=self.preset_var, values=core.PRESETS,
                     state="readonly", width=12).grid(row=0, column=3, sticky="w")
        ttk.Label(opts, text="slower = a bit smaller", foreground="gray").grid(
            row=0, column=4, sticky="w", padx=4)

        ttk.Label(opts, text="Audio:").grid(row=1, column=2, sticky="w", **pad)
        self.audio_var = tk.StringVar(value=core.AUDIO_MODES[0])
        ttk.Combobox(opts, textvariable=self.audio_var, values=core.AUDIO_MODES,
                     state="readonly", width=27).grid(row=1, column=3, columnspan=2, sticky="w")

        ttk.Label(opts, text="Save to:").grid(row=2, column=2, sticky="w", **pad)
        of = ttk.Frame(opts)
        of.grid(row=2, column=3, columnspan=2, sticky="w")
        self.out_var = tk.StringVar(value="")
        self.out_lbl = ttk.Label(of, width=30)
        self.out_lbl.pack(side="left")
        ttk.Button(of, text="Choose…", command=self.choose_output).pack(side="left", padx=4)
        ttk.Button(of, text="Reset", command=lambda: self._set_output("")).pack(side="left")

        self.skip_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(opts, text="Skip videos that are already this size or smaller",
                        variable=self.skip_var).grid(row=3, column=1, sticky="w", **pad)
        self.overwrite_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(opts, text="Overwrite existing outputs",
                        variable=self.overwrite_var).grid(row=3, column=3, columnspan=2, sticky="w")

        opts.columnconfigure(1, weight=1)
        self._reset_crf()
        self._set_output("")

        # --- run ---------------------------------------------------------
        run = ttk.Frame(self)
        run.pack(fill="x", **pad)
        self.sample_btn = ttk.Button(run, text="Test 30-second sample",
                                     command=lambda: self.start(sample=True))
        self.sample_btn.pack(side="left")
        self.go_btn = ttk.Button(run, text="Shrink all", command=lambda: self.start(sample=False))
        self.go_btn.pack(side="left", padx=6)
        self.cancel_btn = ttk.Button(run, text="Cancel", command=self.cancel, state="disabled")
        self.cancel_btn.pack(side="left")
        ttk.Button(run, text="Open output folder", command=self.open_output_folder).pack(side="right")

        prog = ttk.Frame(self)
        prog.pack(fill="x", **pad)
        ttk.Label(prog, text="This file:").grid(row=0, column=0, sticky="w")
        self.file_bar = ttk.Progressbar(prog, maximum=100)
        self.file_bar.grid(row=0, column=1, sticky="ew", padx=6)
        ttk.Label(prog, text="Overall:").grid(row=1, column=0, sticky="w")
        self.all_bar = ttk.Progressbar(prog, maximum=100)
        self.all_bar.grid(row=1, column=1, sticky="ew", padx=6, pady=2)
        prog.columnconfigure(1, weight=1)

        self.status = ttk.Label(self, text="Add some videos to get started.", anchor="w")
        self.status.pack(fill="x", padx=8, pady=(0, 8))

    def _reset_crf(self) -> None:
        self.crf_var.set(core.CODECS[self.codec_var.get()][1])
        self._update_crf_label()

    def _update_crf_label(self) -> None:
        crf = int(round(self.crf_var.get()))
        self.crf_var.set(crf)
        default = core.CODECS[self.codec_var.get()][1]
        note = " (default)" if crf == default else ""
        self.crf_lbl.config(text=f"CRF {crf}{note}")

    def _set_output(self, folder: str) -> None:
        self.out_var.set(folder)
        self.out_lbl.config(text=folder or "'shrunk' folder beside each video")

    # -------------------------------------------------------------- files --

    def add_files(self) -> None:
        exts = " ".join("*" + e for e in sorted(core.VIDEO_EXTENSIONS))
        picked = filedialog.askopenfilenames(
            title="Choose videos", filetypes=[("Videos", exts), ("All files", "*.*")])
        self._add([Path(p) for p in picked])

    def add_folder(self) -> None:
        folder = filedialog.askdirectory(title="Choose a folder of videos (subfolders included)")
        if folder:
            self._add([Path(folder)])

    def _add(self, paths: list[Path]) -> None:
        new = [p for p in core.collect_videos(paths) if p not in self.files]
        for p in new:
            self.files.append(p)
            self.tree.insert("", "end", iid=str(p), values=(p.name, "reading…", ""))
        self._update_count()
        if new and self.shrinker:
            threading.Thread(target=self._probe_all, args=(new,), daemon=True).start()

    def _probe_all(self, paths: list[Path]) -> None:
        for p in paths:
            try:
                info = core.probe(p, self.ffprobe)
                self.events.put(("info", p, info.describe()))
            except Exception as e:  # noqa: BLE001
                self.events.put(("info", p, f"can't read: {e}"))

    def remove_selected(self) -> None:
        if self._busy():
            return
        for iid in self.tree.selection():
            self.tree.delete(iid)
            self.files = [f for f in self.files if str(f) != iid]
        self._update_count()

    def clear(self) -> None:
        if self._busy():
            return
        self.tree.delete(*self.tree.get_children())
        self.files.clear()
        self._update_count()

    def _update_count(self) -> None:
        total = sum(p.stat().st_size for p in self.files if p.exists())
        self.count_lbl.config(text=f"{len(self.files)} video(s), {core.format_size(total)}"
                              if self.files else "No files yet")

    def choose_output(self) -> None:
        folder = filedialog.askdirectory(title="Where should the smaller videos go?")
        if folder:
            self._set_output(folder)

    # ---------------------------------------------------------------- run --

    def _busy(self) -> bool:
        return bool(self.worker and self.worker.is_alive())

    def _settings(self, sample: bool) -> core.Settings:
        return core.Settings(
            target_height=self.res_var.get(),
            codec_label=self.codec_var.get(),
            crf=int(self.crf_var.get()),
            preset=self.preset_var.get(),
            audio_mode=self.audio_var.get(),
            output_dir=Path(self.out_var.get()) if self.out_var.get() else None,
            skip_if_not_larger=self.skip_var.get(),
            overwrite=self.overwrite_var.get() or sample,
            sample_seconds=30 if sample else None,
        )

    def start(self, sample: bool) -> None:
        if not self.shrinker:
            self._ffmpeg_missing()
            return
        if self._busy():
            return
        if sample:
            sel = self.tree.selection()
            targets = [Path(sel[0])] if sel else self.files[:1]
        else:
            targets = list(self.files)
        if not targets:
            messagebox.showinfo(APP_NAME, "Add some videos first.")
            return

        settings = self._settings(sample)
        self.stop_requested = False
        self._set_running(True)
        self.all_bar["value"] = 0
        self.worker = threading.Thread(target=self._run, args=(targets, settings), daemon=True)
        self.worker.start()

    def _run(self, targets: list[Path], s: core.Settings) -> None:
        before = after = 0
        done = skipped = failed = 0
        for i, path in enumerate(targets):
            if self.stop_requested:
                break
            self.events.put(("status_row", path, "working… 0%"))
            self.events.put(("status", f"[{i + 1}/{len(targets)}] {path.name}"))

            def progress(frac: float, i=i, path=path) -> None:
                self.events.put(("progress", path, frac, (i + frac) / len(targets)))

            res = self.shrinker.shrink(path, s, progress)
            self.events.put(("result", path, res))
            if res.status == "done":
                done += 1
                if not s.sample_seconds:
                    before += res.before_bytes
                    after += res.after_bytes
            elif res.status == "skipped":
                skipped += 1
            elif res.status == "failed":
                failed += 1
        self.events.put(("finished", done, skipped, failed, before, after,
                         bool(s.sample_seconds)))

    def cancel(self) -> None:
        self.stop_requested = True
        if self.shrinker:
            self.shrinker.cancel()
        self.status.config(text="Cancelling…")

    def _set_running(self, running: bool) -> None:
        state = "disabled" if running else "normal"
        self.go_btn.config(state=state)
        self.sample_btn.config(state=state)
        self.cancel_btn.config(state="normal" if running else "disabled")

    # The worker thread never touches widgets; it posts events handled here.
    def _pump_events(self) -> None:
        try:
            while True:
                ev = self.events.get_nowait()
                kind = ev[0]
                if kind == "info":
                    _, p, text = ev
                    if self.tree.exists(str(p)):
                        self.tree.set(str(p), "info", text)
                elif kind == "status_row":
                    _, p, text = ev
                    if self.tree.exists(str(p)):
                        self.tree.set(str(p), "status", text)
                        self.tree.see(str(p))
                elif kind == "status":
                    self.status.config(text=ev[1])
                elif kind == "progress":
                    _, p, frac, overall = ev
                    self.file_bar["value"] = frac * 100
                    self.all_bar["value"] = overall * 100
                    if self.tree.exists(str(p)):
                        self.tree.set(str(p), "status", f"working… {frac * 100:.0f}%")
                elif kind == "result":
                    _, p, res = ev
                    if self.tree.exists(str(p)):
                        text = res.message
                        if res.status == "done" and res.saved_pct > 0 and "sample" not in text:
                            text += f"  (saved {res.saved_pct:.0f}%)"
                        elif res.status != "done":
                            text = f"{res.status}: {text}"
                        self.tree.set(str(p), "status", text)
                        self.tree.item(str(p), tags=(str(res.output),) if res.status == "done" else ())
                elif kind == "finished":
                    _, done, skipped, failed, before, after, sample = ev
                    self._set_running(False)
                    self.file_bar["value"] = 0
                    if sample:
                        msg = "Sample done - double-click the row to watch it and judge the quality."
                    else:
                        msg = f"Finished: {done} shrunk, {skipped} skipped, {failed} failed."
                        if before:
                            msg += (f"  {core.format_size(before)} -> {core.format_size(after)}"
                                    f"  (saved {core.format_size(before - after)},"
                                    f" {100 * (1 - after / before):.0f}%)")
                    if self.stop_requested:
                        msg = "Cancelled. " + msg
                    else:
                        self.all_bar["value"] = 100
                    self.status.config(text=msg)
        except queue.Empty:
            pass
        self.after(100, self._pump_events)

    # -------------------------------------------------------------- misc --

    def _open_selected_output(self, _event=None) -> None:
        sel = self.tree.selection()
        if not sel:
            return
        tags = self.tree.item(sel[0], "tags")
        target = Path(tags[0]) if tags and tags[0] else Path(sel[0])
        if target.exists():
            _open(target)

    def open_output_folder(self) -> None:
        folder = Path(self.out_var.get()) if self.out_var.get() else (
            self.files[0].parent / "shrunk" if self.files else None)
        if folder and folder.exists():
            _open(folder)
        else:
            messagebox.showinfo(APP_NAME, "Nothing has been saved yet.")

    def _ffmpeg_missing(self) -> None:
        messagebox.showerror(
            APP_NAME,
            "ffmpeg wasn't found.\n\n"
            "Easiest fix: open PowerShell and run\n"
            "    winget install Gyan.FFmpeg\n"
            "then restart this app.\n\n"
            "Or put ffmpeg.exe and ffprobe.exe in the same folder as this app.")


def _open(path: Path) -> None:
    if os.name == "nt":
        os.startfile(path)  # type: ignore[attr-defined]
    elif sys.platform == "darwin":
        subprocess.Popen(["open", str(path)])
    else:
        subprocess.Popen(["xdg-open", str(path)])


def main() -> None:
    try:
        # Crisp text on high-DPI Windows screens instead of blurry scaling.
        from ctypes import windll  # type: ignore[attr-defined]
        windll.shcore.SetProcessDpiAwareness(1)
    except Exception:  # noqa: BLE001
        pass
    App().mainloop()


if __name__ == "__main__":
    main()
