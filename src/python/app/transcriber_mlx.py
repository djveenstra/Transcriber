from typing import Callable, Optional
from app.transcriber import TranscriptionSegment

MODEL_REPOS = {
    "tiny": "mlx-community/whisper-tiny-mlx",
    "base": "mlx-community/whisper-base-mlx",
    "small": "mlx-community/whisper-small-mlx",
    "medium": "mlx-community/whisper-medium-mlx",
    "large": "mlx-community/whisper-large-v3-mlx",
}


class MLXTranscriber:
    def __init__(self, model_size: str = "base"):
        self.model_size = model_size

    def run(
        self,
        audio_path: str,
        progress_callback: Optional[Callable[[int], None]] = None,
    ) -> list[TranscriptionSegment]:
        import mlx_whisper

        repo = MODEL_REPOS.get(self.model_size, MODEL_REPOS["base"])
        result = mlx_whisper.transcribe(audio_path, path_or_hf_repo=repo, verbose=False)

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
        return segments
