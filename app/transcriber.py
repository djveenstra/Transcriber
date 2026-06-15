from dataclasses import dataclass
from typing import Callable, Optional


@dataclass
class TranscriptionSegment:
    start: float
    end: float
    text: str


class Transcriber:
    _model_cache: dict = {}

    def __init__(self, model_size: str = "base", device: str = "cpu"):
        self.model_size = model_size
        self.device = device

    def load_model(self):
        import whisper
        key = (self.model_size, self.device)
        if key not in Transcriber._model_cache:
            try:
                model = whisper.load_model(self.model_size, device=self.device)
            except NotImplementedError:
                # PyTorch Whisper uses sparse tensor ops that aren't implemented
                # on the MPS backend (aten::_sparse_coo_tensor_with_dims_and_tensors).
                # Fall back to CPU so the app keeps working instead of crashing.
                if self.device == "mps":
                    self.device = "cpu"
                    key = (self.model_size, self.device)
                    model = whisper.load_model(self.model_size, device="cpu")
                else:
                    raise
            Transcriber._model_cache[key] = model
        return Transcriber._model_cache[key]

    def run(
        self,
        audio_path: str,
        progress_callback: Optional[Callable[[int], None]] = None,
    ) -> list[TranscriptionSegment]:
        model = self.load_model()
        result = model.transcribe(
            audio_path,
            verbose=False,
            fp16=(self.device == "cuda"),
        )
        segments = []
        total = len(result["segments"])
        for i, seg in enumerate(result["segments"]):
            segments.append(TranscriptionSegment(
                start=seg["start"],
                end=seg["end"],
                text=seg["text"].strip(),
            ))
            if progress_callback and total > 0:
                progress_callback(int((i + 1) / total * 100))
        if self.device == "mps":
            import torch
            torch.mps.empty_cache()
        return segments
