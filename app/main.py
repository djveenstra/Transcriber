import os
import sys

# ── Ensure Homebrew binaries (ffmpeg) are findable in .app bundles ─────────
os.environ["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + os.environ.get("PATH", "")

# ── Compatibility patches (must run before any model imports) ──────────────

# 1. huggingface_hub 1.x removed use_auth_token; pyannote still passes it.
import huggingface_hub as _hf
_orig_download = _hf.hf_hub_download
def _patched_download(*args, **kwargs):
    kwargs.pop('use_auth_token', None)
    return _orig_download(*args, **kwargs)
_hf.hf_hub_download = _patched_download

# 2. PyTorch 2.6+ changed the default to weights_only=True, which breaks
#    pyannote checkpoints. These are trusted HF models, so force False.
import torch as _torch
_orig_torch_load = _torch.load
def _patched_torch_load(*args, **kwargs):
    kwargs['weights_only'] = False
    return _orig_torch_load(*args, **kwargs)
_torch.load = _patched_torch_load

from PyQt6.QtWidgets import QApplication
from app.gui import MainWindow


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Transcriber")
    app.setOrganizationName("Transcriber")
    window = MainWindow()
    window.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
