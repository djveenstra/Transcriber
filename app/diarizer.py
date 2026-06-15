import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

# Formats soundfile can handle natively; everything else gets converted to wav.
_SOUNDFILE_FORMATS = {".wav", ".flac", ".ogg", ".aiff", ".aif"}


@dataclass
class DiarizationSegment:
    start: float
    end: float
    speaker: str


class Diarizer:
    _pipeline_cache = None

    def __init__(self, hf_token: str, device: str = "cpu"):
        self.hf_token = hf_token
        self.device = device

    def load_pipeline(self):
        if Diarizer._pipeline_cache is None:
            from pyannote.audio import Pipeline
            import torch
            from huggingface_hub import login
            login(token=self.hf_token, add_to_git_credential=False)
            pipeline = Pipeline.from_pretrained("pyannote/speaker-diarization-3.1")
            pipeline.to(torch.device(self.device))
            Diarizer._pipeline_cache = pipeline
        return Diarizer._pipeline_cache

    def _to_wav(self, audio_path: str, tmp_dir: str) -> str:
        """Convert audio to wav using ffmpeg if soundfile can't read it natively."""
        if Path(audio_path).suffix.lower() in _SOUNDFILE_FORMATS:
            return audio_path
        out = str(Path(tmp_dir) / "audio.wav")
        subprocess.run(
            ["ffmpeg", "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", out],
            check=True, capture_output=True,
        )
        return out

    def run(
        self,
        audio_path: str,
        num_speakers: Optional[int] = None,
        progress_callback: Optional[Callable[[int], None]] = None,
    ) -> list[DiarizationSegment]:
        pipeline = self.load_pipeline()
        kwargs = {}
        if num_speakers is not None:
            kwargs["num_speakers"] = num_speakers

        with tempfile.TemporaryDirectory() as tmp:
            wav_path = self._to_wav(audio_path, tmp)

            diarization = pipeline(wav_path, **kwargs)

        segments = []
        for turn, _, speaker in diarization.itertracks(yield_label=True):
            segments.append(DiarizationSegment(
                start=turn.start,
                end=turn.end,
                speaker=speaker,
            ))

        if self.device == "mps":
            import torch
            torch.mps.empty_cache()
        if progress_callback:
            progress_callback(100)
        return segments
