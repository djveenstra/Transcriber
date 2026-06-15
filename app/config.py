import json
import os
from pathlib import Path

CONFIG_DIR = Path.home() / "Library" / "Application Support" / "Transcriber"
CONFIG_FILE = CONFIG_DIR / "config.json"

def _default_device() -> str:
    try:
        import torch
        if torch.backends.mps.is_available():
            return "mps"
    except Exception:
        pass
    return "cpu"


def available_devices() -> list[str]:
    devices = ["cpu"]
    try:
        import torch
        if torch.backends.mps.is_available():
            devices.append("mps")
    except Exception:
        pass
    return devices


DEFAULTS = {
    "hf_token": "",
    "whisper_model": "base",
    "export_format": "txt",
    "last_directory": str(Path.home()),
    "device": _default_device(),
    "transcription_backend": "mlx-whisper",
    "theme": "oled",
    "theme_user_selected": False,
}


class Config:
    def __init__(self):
        self._data = dict(DEFAULTS)
        self._load()

    def _load(self):
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE) as f:
                saved = json.load(f)
            self._data.update(saved)

    def save(self):
        CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        with open(CONFIG_FILE, "w") as f:
            json.dump(self._data, f, indent=2)
        os.chmod(CONFIG_FILE, 0o600)

    def get(self, key: str):
        return self._data.get(key, DEFAULTS.get(key))

    def set(self, key: str, value):
        self._data[key] = value
        self.save()

    @property
    def hf_token(self) -> str:
        token = self._data.get("hf_token", "")
        if token:
            return token
        token = os.environ.get("HF_TOKEN", "")
        if token:
            return token
        hf_token_file = Path.home() / ".huggingface" / "token"
        if hf_token_file.exists():
            return hf_token_file.read_text().strip()
        return ""
