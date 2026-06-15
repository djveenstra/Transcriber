from concurrent.futures import ThreadPoolExecutor
from PyQt6.QtCore import QThread, pyqtSignal
from app.config import Config
from app.transcriber import Transcriber
from app.diarizer import Diarizer
from app.merger import merge_segments, MergedSegment


class TranscriptionPipeline(QThread):
    progress = pyqtSignal(int)
    status = pyqtSignal(str)
    finished = pyqtSignal(list)
    error = pyqtSignal(str)

    def __init__(self, audio_path: str, config: Config, num_speakers: int = 0, parent=None):
        super().__init__(parent)
        self.audio_path = audio_path
        self.config = config
        self.num_speakers = num_speakers

    def _make_transcriber(self, device: str):
        backend = self.config.get("transcription_backend")
        if backend == "mlx-whisper":
            from app.transcriber_mlx import MLXTranscriber
            return MLXTranscriber(model_size=self.config.get("whisper_model"))
        return Transcriber(model_size=self.config.get("whisper_model"), device=device)

    def _can_parallelize(self, device: str, backend: str) -> bool:
        # CPU: plenty of cores for both threads
        # mlx-whisper + MPS diarization: different frameworks, no contention
        # MPS-only: both compete for the same GPU queue, run sequentially
        return device == "cpu" or backend == "mlx-whisper"

    def run(self):
        try:
            device = self.config.get("device")
            backend = self.config.get("transcription_backend")
            num_speakers = self.num_speakers if self.num_speakers > 0 else None

            self.status.emit("Loading models...")
            self.progress.emit(0)

            diarizer = Diarizer(hf_token=self.config.hf_token, device=device)
            transcriber = self._make_transcriber(device)

            if self._can_parallelize(device, backend):
                self._run_parallel(diarizer, transcriber, num_speakers)
            else:
                self._run_sequential(diarizer, transcriber, num_speakers)

        except Exception as e:
            self.error.emit(str(e))

    def _run_parallel(self, diarizer, transcriber, num_speakers):
        self.status.emit("Identifying speakers + transcribing (parallel)...")
        self.progress.emit(0)

        def trans_progress(p):
            self.progress.emit(int(p * 0.85))

        with ThreadPoolExecutor(max_workers=2) as pool:
            diar_future = pool.submit(
                diarizer.run, self.audio_path, num_speakers=num_speakers,
            )
            trans_future = pool.submit(
                transcriber.run, self.audio_path, progress_callback=trans_progress,
            )

            diar_segments = diar_future.result()
            trans_segments = trans_future.result()

        self.progress.emit(90)
        self.status.emit("Aligning speakers with transcript...")
        merged = merge_segments(diar_segments, trans_segments)
        self.progress.emit(100)
        self.status.emit("Done!")
        self.finished.emit(merged)

    def _run_sequential(self, diarizer, transcriber, num_speakers):
        # Phase 1: Diarization (0–45%)
        self.status.emit("Identifying speakers...")
        self.progress.emit(-1)
        diar_segments = diarizer.run(self.audio_path, num_speakers=num_speakers)
        self.progress.emit(45)

        # Phase 2: Transcription (45–90%)
        self.status.emit("Transcribing audio...")
        trans_segments = transcriber.run(
            self.audio_path,
            progress_callback=lambda p: self.progress.emit(45 + int(p * 0.45)),
        )
        self.progress.emit(90)

        # Phase 3: Merge
        self.status.emit("Aligning speakers with transcript...")
        merged = merge_segments(diar_segments, trans_segments)
        self.progress.emit(100)
        self.status.emit("Done!")
        self.finished.emit(merged)
