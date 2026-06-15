import time
from html import escape
from pathlib import Path
from PyQt6.QtWidgets import (
    QApplication, QMainWindow, QWidget, QVBoxLayout, QHBoxLayout,
    QLabel, QLineEdit, QPushButton, QComboBox, QProgressBar,
    QTextEdit, QFileDialog, QDialog, QDialogButtonBox, QMessageBox,
    QSpinBox, QFormLayout, QFrame,
)
from PyQt6.QtCore import Qt, QTimer
from PyQt6.QtGui import QFont, QAction, QActionGroup, QDragEnterEvent, QDropEvent
from app.config import Config, available_devices
from app.pipeline import TranscriptionPipeline
from app.exporter import export, format_timestamp, display_name, friendly_speaker_name

AUDIO_EXTENSIONS = "Audio Files (*.wav *.mp3 *.m4a *.flac *.ogg *.wma *.aac *.opus);;All Files (*)"
AUDIO_SUFFIXES = {".wav", ".mp3", ".m4a", ".flac", ".ogg", ".wma", ".aac", ".opus"}

# Distinct, OLED-friendly colors for speaker labels.
SPEAKER_COLORS = [
    "#29d3c2",  # teal
    "#f2a33b",  # amber
    "#58a6ff",  # blue
    "#f472b6",  # pink
    "#8ddc65",  # green
    "#c084fc",  # violet
    "#fb7185",  # rose
    "#67e8f9",  # cyan
]

THEMES = {
    "light": {
        "window": "#f3f6f8",
        "surface": "#ffffff",
        "surface_alt": "#f8fafc",
        "border": "#dbe3ea",
        "text": "#17212b",
        "muted": "#6b7886",
        "placeholder": "#8a96a3",
        "accent": "#0f8f8c",
        "accent_hover": "#0d7d7a",
        "accent_soft": "#dff5f3",
        "button": "#ffffff",
        "button_hover": "#f3f8f8",
        "disabled": "#a7b0ba",
        "transcript": "#ffffff",
        "timestamp": "#8895a3",
    },
    "oled": {
        "window": "#000000",
        "surface": "#05080b",
        "surface_alt": "#090d12",
        "border": "#1d2a33",
        "text": "#f1f7f8",
        "muted": "#9aa8b3",
        "placeholder": "#6e7d88",
        "accent": "#20c8bd",
        "accent_hover": "#38ded2",
        "accent_soft": "#082b2d",
        "button": "#080d12",
        "button_hover": "#0d151c",
        "disabled": "#53616c",
        "transcript": "#030608",
        "timestamp": "#8d9aa5",
    },
}


def app_stylesheet(theme_name: str) -> str:
    theme = THEMES.get(theme_name, THEMES["oled"])
    return f"""
QMainWindow, QDialog {{
    background: {theme["window"]};
}}
QMenuBar {{
    background: {theme["window"]};
    color: {theme["text"]};
}}
QMenuBar::item:selected, QMenu {{
    background: {theme["surface_alt"]};
    color: {theme["text"]};
}}
QWidget {{
    color: {theme["text"]};
    font-size: 13px;
}}
QFrame#TranscriptPanel, QFrame#SidePanel, QFrame#ProgressPanel {{
    background: {theme["surface"]};
    border: 1px solid {theme["border"]};
    border-radius: 8px;
}}
QFrame#DropZone {{
    background: {theme["surface_alt"]};
    border: 1px dashed {theme["border"]};
    border-radius: 8px;
}}
QLabel#AppTitle {{
    font-size: 25px;
    font-weight: 700;
    color: {theme["text"]};
}}
QLabel#PanelTitle {{
    font-size: 18px;
    font-weight: 700;
    color: {theme["text"]};
}}
QLabel#SectionLabel {{
    font-size: 11px;
    font-weight: 700;
    color: {theme["muted"]};
}}
QLabel#MutedLabel, QLabel#StatusLabel, QLabel#DropHint {{
    color: {theme["muted"]};
}}
QLabel#DropTitle {{
    font-size: 15px;
    font-weight: 700;
    color: {theme["text"]};
}}
QLineEdit, QComboBox, QSpinBox {{
    background: {theme["surface_alt"]};
    border: 1px solid {theme["border"]};
    border-radius: 6px;
    color: {theme["text"]};
    min-height: 32px;
    padding: 4px 10px;
}}
QComboBox::drop-down, QSpinBox::up-button, QSpinBox::down-button {{
    border: none;
    width: 22px;
}}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus {{
    border: 1px solid {theme["accent"]};
}}
QLineEdit[readOnly="true"] {{
    color: {theme["muted"]};
}}
QLineEdit::placeholder {{
    color: {theme["placeholder"]};
}}
QPushButton {{
    background: {theme["button"]};
    border: 1px solid {theme["border"]};
    color: {theme["text"]};
    min-height: 34px;
    padding: 7px 14px;
    border-radius: 7px;
    font-weight: 600;
}}
QPushButton#PrimaryButton {{
    background: {theme["accent"]};
    border: 1px solid {theme["accent"]};
    color: #021112;
    font-size: 15px;
}}
QPushButton#PrimaryButton:hover {{
    background: {theme["accent_hover"]};
    border-color: {theme["accent_hover"]};
}}
QPushButton#SecondaryButton {{
    background: {theme["button"]};
    border: 1px solid {theme["border"]};
    color: {theme["text"]};
}}
QPushButton#GhostButton {{
    background: transparent;
    border: 1px solid {theme["border"]};
    color: {theme["text"]};
}}
QPushButton#SecondaryButton:hover {{
    background: {theme["button_hover"]};
    border-color: {theme["accent"]};
}}
QPushButton#GhostButton:hover {{
    background: {theme["button_hover"]};
    border-color: {theme["accent"]};
}}
QPushButton:disabled {{
    color: {theme["disabled"]};
    background: {theme["surface_alt"]};
    border-color: {theme["border"]};
}}
QProgressBar {{
    background: {theme["surface_alt"]};
    border: 1px solid {theme["border"]};
    border-radius: 5px;
    color: transparent;
    max-height: 10px;
}}
QProgressBar::chunk {{
    background: {theme["accent"]};
    border-radius: 4px;
}}
QTextEdit#TranscriptEdit {{
    background: {theme["transcript"]};
    border: 1px solid {theme["border"]};
    border-radius: 8px;
    color: {theme["text"]};
    padding: 14px;
}}
"""


def speaker_color(raw: str) -> str:
    """Pick a stable color for a raw speaker id."""
    if raw == "Unknown":
        return "#6b7280"  # gray
    idx = 0
    if raw.startswith("SPEAKER_"):
        try:
            idx = int(raw.split("_")[1])
        except (IndexError, ValueError):
            idx = 0
    return SPEAKER_COLORS[idx % len(SPEAKER_COLORS)]


class AutoSpeakerSpinBox(QSpinBox):
    def textFromValue(self, value: int) -> str:
        if value == 0:
            return "Auto"
        return str(value)

    def valueFromText(self, text: str) -> int:
        if text.strip().lower() == "auto":
            return 0
        return super().valueFromText(text)


class TokenDialog(QDialog):
    def __init__(self, config: Config, parent=None):
        super().__init__(parent)
        self.config = config
        self.setWindowTitle("HuggingFace Token Required")
        self.setMinimumWidth(480)

        layout = QVBoxLayout(self)

        instructions = QLabel(
            "<b>Speaker diarization requires a free HuggingFace account and token.</b><br><br>"
            "1. Create a free account at <a href='https://huggingface.co'>huggingface.co</a><br>"
            "2. Visit the model page and accept the terms:<br>"
            "&nbsp;&nbsp;&nbsp;<a href='https://huggingface.co/pyannote/speaker-diarization-3.1'>"
            "huggingface.co/pyannote/speaker-diarization-3.1</a><br>"
            "3. Create an access token at:<br>"
            "&nbsp;&nbsp;&nbsp;<a href='https://huggingface.co/settings/tokens'>"
            "huggingface.co/settings/tokens</a><br><br>"
            "Paste your token below:"
        )
        instructions.setOpenExternalLinks(True)
        instructions.setWordWrap(True)
        layout.addWidget(instructions)

        self.token_edit = QLineEdit()
        self.token_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.token_edit.setPlaceholderText("hf_...")
        layout.addWidget(self.token_edit)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_save)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _on_save(self):
        token = self.token_edit.text().strip()
        if not token:
            QMessageBox.warning(self, "Token Required", "Please enter a HuggingFace token.")
            return
        self.config.set("hf_token", token)
        self.accept()


class SettingsDialog(QDialog):
    def __init__(self, config: Config, parent=None):
        super().__init__(parent)
        self.config = config
        self.setWindowTitle("Settings")
        self.setMinimumWidth(400)

        layout = QVBoxLayout(self)

        # HF Token
        layout.addWidget(QLabel("HuggingFace Token:"))
        self.token_edit = QLineEdit()
        self.token_edit.setEchoMode(QLineEdit.EchoMode.Password)
        self.token_edit.setText(config.get("hf_token"))
        self.token_edit.setPlaceholderText("hf_...")
        layout.addWidget(self.token_edit)

        # Device
        device_row = QHBoxLayout()
        device_row.addWidget(QLabel("Compute Device:"))
        self.device_combo = QComboBox()
        self.device_combo.addItems(available_devices())
        self.device_combo.setCurrentText(config.get("device"))
        device_row.addWidget(self.device_combo)
        layout.addLayout(device_row)

        # Transcription backend
        backend_row = QHBoxLayout()
        backend_row.addWidget(QLabel("Transcription Backend:"))
        self.backend_combo = QComboBox()
        backends = ["whisper"]
        try:
            import mlx_whisper  # noqa: F401
            backends.append("mlx-whisper")
        except ImportError:
            pass
        self.backend_combo.addItems(backends)
        self.backend_combo.setCurrentText(config.get("transcription_backend"))
        backend_row.addWidget(self.backend_combo)
        layout.addLayout(backend_row)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.accepted.connect(self._on_save)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def _on_save(self):
        token = self.token_edit.text().strip()
        if token:
            self.config.set("hf_token", token)
        self.config.set("device", self.device_combo.currentText())
        self.config.set("transcription_backend", self.backend_combo.currentText())
        self.accept()


class RenameSpeakersDialog(QDialog):
    """Lets the user assign custom names to detected speakers."""

    def __init__(self, speakers: list[str], name_map: dict, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Rename Speakers")
        self.setMinimumWidth(440)
        self._edits: dict[str, QLineEdit] = {}

        layout = QVBoxLayout(self)
        layout.setSpacing(14)
        layout.setContentsMargins(18, 18, 18, 18)

        title = QLabel("Rename Speakers")
        title.setObjectName("PanelTitle")
        layout.addWidget(title)

        helper = QLabel("Give each detected speaker a real name. Leave blank to keep the default.")
        helper.setObjectName("MutedLabel")
        helper.setWordWrap(True)
        layout.addWidget(helper)

        form = QFormLayout()
        form.setHorizontalSpacing(14)
        form.setVerticalSpacing(12)
        for raw in speakers:
            edit = QLineEdit()
            edit.setText(name_map.get(raw, ""))
            edit.setPlaceholderText("Name this speaker")
            label = QLabel(friendly_speaker_name(raw))
            label.setStyleSheet(f"color: {speaker_color(raw)}; font-weight: 600;")
            form.addRow(label, edit)
            self._edits[raw] = edit
        layout.addLayout(form)

        buttons = QDialogButtonBox(
            QDialogButtonBox.StandardButton.Save | QDialogButtonBox.StandardButton.Cancel
        )
        buttons.button(QDialogButtonBox.StandardButton.Save).setText("Save Names")
        buttons.button(QDialogButtonBox.StandardButton.Save).setObjectName("PrimaryButton")
        buttons.button(QDialogButtonBox.StandardButton.Cancel).setObjectName("GhostButton")
        buttons.accepted.connect(self.accept)
        buttons.rejected.connect(self.reject)
        layout.addWidget(buttons)

    def result_map(self) -> dict:
        """Return {raw_speaker: custom_name} for non-empty entries."""
        out = {}
        for raw, edit in self._edits.items():
            name = edit.text().strip()
            if name:
                out[raw] = name
        return out


class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.config = Config()
        self.pipeline = None
        self.segments = []
        self.speaker_names = {}          # raw speaker id -> custom name
        self._status_text = "Ready."
        self._proc_start = None
        self._elapsed_timer = QTimer(self)
        self._elapsed_timer.setInterval(1000)
        self._elapsed_timer.timeout.connect(self._tick_elapsed)
        self._theme_name = self.config.get("theme") or "oled"
        if not self.config.get("theme_user_selected") and self._theme_name != "oled":
            self._theme_name = "oled"
            self.config.set("theme", "oled")
        if self._theme_name == "dark":
            self._theme_name = "oled"

        self.setWindowTitle("Transcriber")
        self.setMinimumSize(1040, 800)
        self.setAcceptDrops(True)
        self._apply_theme()

        self._build_menu()
        self._build_ui()

        if not self.config.hf_token:
            QTimer.singleShot(0, self._show_token_dialog)

    def _build_menu(self):
        menubar = self.menuBar()
        edit_menu = menubar.addMenu("Edit")
        settings_action = QAction("Settings", self)
        settings_action.setShortcut("Ctrl+,")
        settings_action.triggered.connect(self._show_settings)
        edit_menu.addAction(settings_action)

        view_menu = menubar.addMenu("View")
        self.theme_group = QActionGroup(self)
        self.theme_group.setExclusive(True)

        oled_action = QAction("OLED Black", self, checkable=True)
        oled_action.setChecked(self._theme_name == "oled")
        oled_action.triggered.connect(lambda: self._set_theme("oled"))
        self.theme_group.addAction(oled_action)
        view_menu.addAction(oled_action)

        light_action = QAction("Light", self, checkable=True)
        light_action.setChecked(self._theme_name == "light")
        light_action.triggered.connect(lambda: self._set_theme("light"))
        self.theme_group.addAction(light_action)
        view_menu.addAction(light_action)

    def _build_ui(self):
        central = QWidget()
        self.setCentralWidget(central)
        layout = QHBoxLayout(central)
        layout.setSpacing(14)
        layout.setContentsMargins(16, 16, 16, 16)

        transcript_panel = QFrame()
        transcript_panel.setObjectName("TranscriptPanel")
        transcript_layout = QVBoxLayout(transcript_panel)
        transcript_layout.setSpacing(12)
        transcript_layout.setContentsMargins(16, 16, 16, 16)

        transcript_header = QHBoxLayout()
        transcript_title = QLabel("Transcript")
        transcript_title.setObjectName("PanelTitle")
        transcript_header.addWidget(transcript_title)
        transcript_header.addStretch()
        self.status_label = QLabel("Ready.")
        self.status_label.setObjectName("StatusLabel")
        transcript_header.addWidget(self.status_label)
        transcript_layout.addLayout(transcript_header)

        # Transcript view — fonts for rich (proportional) and structured (mono) modes
        self._ui_font = QFont()
        self._ui_font.setPointSize(13)
        self._mono_font = QFont("Menlo")
        self._mono_font.setStyleHint(QFont.StyleHint.Monospace)
        self._mono_font.setPointSize(12)

        self.text_edit = QTextEdit()
        self.text_edit.setObjectName("TranscriptEdit")
        self.text_edit.setReadOnly(True)
        self.text_edit.setFont(self._ui_font)
        self.text_edit.setPlaceholderText("Your transcript will appear here.")
        transcript_layout.addWidget(self.text_edit, stretch=1)

        progress_panel = QFrame()
        progress_panel.setObjectName("ProgressPanel")
        progress_layout = QVBoxLayout(progress_panel)
        progress_layout.setSpacing(8)
        progress_layout.setContentsMargins(12, 10, 12, 10)
        progress_row = QHBoxLayout()
        ready_label = QLabel("Progress")
        ready_label.setObjectName("MutedLabel")
        progress_row.addWidget(ready_label)
        progress_row.addStretch()
        self.elapsed_label = QLabel("00:00")
        self.elapsed_label.setObjectName("MutedLabel")
        progress_row.addWidget(self.elapsed_label)
        progress_layout.addLayout(progress_row)

        self.progress_bar = QProgressBar()
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(0)
        progress_layout.addWidget(self.progress_bar)
        transcript_layout.addWidget(progress_panel)

        side_panel = QFrame()
        side_panel.setObjectName("SidePanel")
        side_panel.setFixedWidth(350)
        side_layout = QVBoxLayout(side_panel)
        side_layout.setSpacing(14)
        side_layout.setContentsMargins(18, 18, 18, 18)

        app_title = QLabel("Transcriber")
        app_title.setObjectName("AppTitle")
        side_layout.addWidget(app_title)

        app_subtitle = QLabel("Transcribe audio and separate speakers.")
        app_subtitle.setObjectName("MutedLabel")
        app_subtitle.setWordWrap(True)
        side_layout.addWidget(app_subtitle)

        file_label = QLabel("AUDIO FILE")
        file_label.setObjectName("SectionLabel")
        side_layout.addWidget(file_label)

        drop_zone = QFrame()
        self.drop_zone = drop_zone
        drop_zone.setObjectName("DropZone")
        drop_zone.setFixedHeight(134)
        drop_layout = QVBoxLayout(drop_zone)
        drop_layout.setSpacing(10)
        drop_layout.setContentsMargins(14, 14, 14, 14)

        drop_title = QLabel("Drop audio here")
        drop_title.setObjectName("DropTitle")
        drop_title.setAlignment(Qt.AlignmentFlag.AlignCenter)
        drop_layout.addWidget(drop_title)

        drop_hint = QLabel("or choose a file from your Mac")
        drop_hint.setObjectName("DropHint")
        drop_hint.setAlignment(Qt.AlignmentFlag.AlignCenter)
        drop_layout.addWidget(drop_hint)

        self.file_path_edit = QLineEdit()
        self.file_path_edit.setFixedHeight(42)
        self.file_path_edit.setReadOnly(True)
        self.file_path_edit.setPlaceholderText("No file selected")
        drop_layout.addWidget(self.file_path_edit)
        side_layout.addWidget(drop_zone)

        browse_btn = QPushButton("Browse...")
        browse_btn.setObjectName("SecondaryButton")
        browse_btn.setFixedHeight(50)
        browse_btn.clicked.connect(self.open_file_dialog)
        side_layout.addWidget(browse_btn)

        settings_label = QLabel("TRANSCRIPTION SETTINGS")
        settings_label.setObjectName("SectionLabel")
        side_layout.addWidget(settings_label)

        form = QFormLayout()
        form.setLabelAlignment(Qt.AlignmentFlag.AlignLeft)
        form.setFormAlignment(Qt.AlignmentFlag.AlignTop)
        form.setHorizontalSpacing(12)
        form.setVerticalSpacing(12)

        self.model_combo = QComboBox()
        self.model_combo.setFixedHeight(42)
        self.model_combo.addItems(["tiny", "base", "small", "medium", "large"])
        self.model_combo.setCurrentText(self.config.get("whisper_model"))
        self.model_combo.currentTextChanged.connect(
            lambda v: self.config.set("whisper_model", v)
        )
        form.addRow(QLabel("Model"), self.model_combo)

        self.format_combo = QComboBox()
        self.format_combo.setFixedHeight(42)
        self.format_combo.addItems(["Text", "SRT", "JSON"])
        fmt_map = {"txt": "Text", "srt": "SRT", "json": "JSON"}
        self.format_combo.setCurrentText(fmt_map.get(self.config.get("export_format"), "Text"))
        self.format_combo.currentTextChanged.connect(self._on_format_changed)
        form.addRow(QLabel("Format"), self.format_combo)

        self.speakers_spin = AutoSpeakerSpinBox()
        self.speakers_spin.setFixedHeight(42)
        self.speakers_spin.setRange(0, 20)
        self.speakers_spin.setValue(0)
        self.speakers_spin.setSpecialValueText("Auto")
        form.addRow(QLabel("Speakers"), self.speakers_spin)
        side_layout.addLayout(form)

        self.transcribe_btn = QPushButton("Transcribe")
        self.transcribe_btn.setObjectName("PrimaryButton")
        self.transcribe_btn.setFixedHeight(50)
        font = self.transcribe_btn.font()
        font.setBold(True)
        self.transcribe_btn.setFont(font)
        self.transcribe_btn.clicked.connect(self.start_transcription)
        side_layout.addWidget(self.transcribe_btn)

        side_layout.addStretch()

        self.rename_btn = QPushButton("Rename Speakers…")
        self.rename_btn.setObjectName("GhostButton")
        self.rename_btn.setFixedHeight(50)
        self.rename_btn.setEnabled(False)
        self.rename_btn.clicked.connect(self.rename_speakers)
        side_layout.addWidget(self.rename_btn)

        self.save_btn = QPushButton("Save Transcript")
        self.save_btn.setObjectName("GhostButton")
        self.save_btn.setFixedHeight(50)
        self.save_btn.setEnabled(False)
        self.save_btn.clicked.connect(self.save_transcript)
        side_layout.addWidget(self.save_btn)

        self.copy_btn = QPushButton("Copy to Clipboard")
        self.copy_btn.setObjectName("GhostButton")
        self.copy_btn.setFixedHeight(50)
        self.copy_btn.setEnabled(False)
        self.copy_btn.clicked.connect(self.copy_to_clipboard)
        side_layout.addWidget(self.copy_btn)

        layout.addWidget(transcript_panel, stretch=1)
        layout.addWidget(side_panel)

    # ── helpers ────────────────────────────────────────────────────────────

    def _apply_theme(self):
        QApplication.instance().setStyleSheet(app_stylesheet(self._theme_name))

    def _set_theme(self, theme_name: str):
        self._theme_name = theme_name
        self.config.set("theme", theme_name)
        self.config.set("theme_user_selected", True)
        self._apply_theme()
        if self.segments:
            self._render_transcript()

    def _fmt_key(self) -> str:
        return {"Text": "txt", "SRT": "srt", "JSON": "json"}.get(
            self.format_combo.currentText(), "txt"
        )

    def _show_token_dialog(self):
        dlg = TokenDialog(self.config, self)
        dlg.exec()

    def _show_settings(self):
        dlg = SettingsDialog(self.config, self)
        dlg.exec()

    def _on_progress(self, value: int):
        if value == -1:
            # Switch to indeterminate/pulse mode during diarization
            self.progress_bar.setMinimum(0)
            self.progress_bar.setMaximum(0)
        else:
            self.progress_bar.setMinimum(0)
            self.progress_bar.setMaximum(100)
            self.progress_bar.setValue(value)

    # ── status + elapsed timer ───────────────────────────────────────────────

    def _on_status(self, text: str):
        self._status_text = text
        self._refresh_status()

    def _refresh_status(self):
        if self._proc_start is not None:
            elapsed = int(time.monotonic() - self._proc_start)
            self.status_label.setText(self._status_text)
            self.elapsed_label.setText(self._format_elapsed(elapsed))
        else:
            self.status_label.setText(self._status_text)
            if hasattr(self, "elapsed_label"):
                self.elapsed_label.setText("00:00")

    def _tick_elapsed(self):
        self._refresh_status()

    def _format_elapsed(self, seconds: int) -> str:
        minutes, secs = divmod(max(seconds, 0), 60)
        hours, minutes = divmod(minutes, 60)
        if hours:
            return f"{hours:d}:{minutes:02d}:{secs:02d}"
        return f"{minutes:02d}:{secs:02d}"

    # ── transcript rendering ─────────────────────────────────────────────────

    def _name_map(self) -> dict:
        return self.speaker_names

    def _on_format_changed(self, _text: str):
        if self.segments:
            self._render_transcript()

    def _render_transcript(self):
        """Render the transcript. Text format → rich colored view; SRT/JSON → mono."""
        fmt = self._fmt_key()
        name_map = self._name_map()

        if fmt != "txt":
            self.text_edit.setFont(self._mono_font)
            self.text_edit.setPlainText(export(self.segments, fmt, name_map))
            return

        self.text_edit.setFont(self._ui_font)
        theme = THEMES.get(self._theme_name, THEMES["oled"])
        parts = [f'<div style="line-height:1.45; color:{theme["text"]}">']
        for seg in self.segments:
            color = speaker_color(seg.speaker)
            name = escape(display_name(seg.speaker, name_map))
            ts = format_timestamp(seg.start)
            text = escape(seg.text)
            parts.append(
                '<p style="margin:0 0 14px 0">'
                f'<span style="color:{color}; font-weight:600">{name}</span>'
                f'<span style="color:{theme["timestamp"]}; font-size:11px">&nbsp;&nbsp;{ts}</span>'
                f'<br><span>{text}</span>'
                '</p>'
            )
        parts.append('</div>')
        self.text_edit.setHtml("".join(parts))

    def _unique_speakers(self) -> list[str]:
        """Distinct raw speaker ids in order of first appearance."""
        seen = []
        for s in self.segments:
            if s.speaker not in seen:
                seen.append(s.speaker)
        return seen

    # ── slots ──────────────────────────────────────────────────────────────

    def open_file_dialog(self):
        start_dir = self.config.get("last_directory")
        path, _ = QFileDialog.getOpenFileName(self, "Open Audio File", start_dir, AUDIO_EXTENSIONS)
        if path:
            self.file_path_edit.setText(path)
            self.config.set("last_directory", str(Path(path).parent))

    def start_transcription(self):
        path = self.file_path_edit.text().strip()
        if not path or not Path(path).exists():
            QMessageBox.warning(self, "No File", "Please select a valid audio file.")
            return

        if not self.config.hf_token:
            dlg = TokenDialog(self.config, self)
            if dlg.exec() != QDialog.DialogCode.Accepted:
                return

        fmt = self._fmt_key()
        self.config.set("export_format", fmt)

        self.transcribe_btn.setEnabled(False)
        self.save_btn.setEnabled(False)
        self.copy_btn.setEnabled(False)
        self.rename_btn.setEnabled(False)
        self.text_edit.clear()
        self.segments = []
        self.speaker_names = {}  # reset custom names for the new file
        self.progress_bar.setValue(0)

        # Start the elapsed timer
        self._proc_start = time.monotonic()
        self._status_text = "Starting..."
        self._elapsed_timer.start()
        self._refresh_status()

        self.pipeline = TranscriptionPipeline(
            audio_path=path,
            config=self.config,
            num_speakers=self.speakers_spin.value(),
            parent=self,
        )
        self.pipeline.progress.connect(self._on_progress)
        self.pipeline.status.connect(self._on_status)
        self.pipeline.finished.connect(self.on_transcription_finished)
        self.pipeline.error.connect(self.on_transcription_error)
        self.pipeline.start()

    def on_transcription_finished(self, segments: list):
        self._elapsed_timer.stop()
        elapsed = int(time.monotonic() - self._proc_start) if self._proc_start else 0
        self._proc_start = None
        self.segments = segments
        self._render_transcript()
        self.save_btn.setEnabled(True)
        self.copy_btn.setEnabled(True)
        self.rename_btn.setEnabled(True)
        self.transcribe_btn.setEnabled(True)
        n_speakers = len(self._unique_speakers())
        self._status_text = f"Done - {len(segments)} segments, {n_speakers} speaker(s)"
        self.status_label.setText(self._status_text)
        self.elapsed_label.setText(self._format_elapsed(elapsed))
        self.progress_bar.setRange(0, 100)
        self.progress_bar.setValue(100)

    def on_transcription_error(self, error_msg: str):
        self._elapsed_timer.stop()
        self._proc_start = None
        QMessageBox.critical(self, "Transcription Error", error_msg)
        self.transcribe_btn.setEnabled(True)
        self.rename_btn.setEnabled(bool(self.segments))
        self.save_btn.setEnabled(bool(self.segments))
        self.copy_btn.setEnabled(bool(self.segments))
        self.progress_bar.setValue(0)
        self._status_text = "Error. See dialog."
        self.status_label.setText(self._status_text)
        self.elapsed_label.setText("00:00")

    def rename_speakers(self):
        if not self.segments:
            return
        dlg = RenameSpeakersDialog(self._unique_speakers(), self.speaker_names, self)
        if dlg.exec() == QDialog.DialogCode.Accepted:
            self.speaker_names = dlg.result_map()
            self._render_transcript()

    def save_transcript(self):
        if not self.segments:
            return
        fmt = self._fmt_key()
        ext_map = {"txt": ".txt", "srt": ".srt", "json": ".json"}
        ext = ext_map[fmt]

        audio_path = self.file_path_edit.text().strip()
        default_name = Path(audio_path).stem + ext if audio_path else "transcript" + ext
        start_dir = self.config.get("last_directory")

        path, _ = QFileDialog.getSaveFileName(
            self, "Save Transcript",
            str(Path(start_dir) / default_name),
            f"*{ext};;All Files (*)"
        )
        if path:
            Path(path).write_text(
                export(self.segments, fmt, self._name_map()), encoding="utf-8"
            )
            self._status_text = "Transcript saved."
            self.status_label.setText(self._status_text)

    def copy_to_clipboard(self):
        if not self.segments:
            return
        fmt = self._fmt_key()
        QApplication.clipboard().setText(export(self.segments, fmt, self._name_map()))
        previous = self._status_text
        self.status_label.setText("Copied to clipboard!")
        QTimer.singleShot(2000, lambda: self.status_label.setText(previous))

    # ── drag-and-drop ──────────────────────────────────────────────────────

    def _set_drag_highlight(self, on: bool):
        if on:
            theme = THEMES.get(self._theme_name, THEMES["oled"])
            self.drop_zone.setStyleSheet(
                f"QFrame#DropZone {{ border: 2px dashed {theme['accent']}; }}"
            )
        else:
            self.drop_zone.setStyleSheet("")

    def dragEnterEvent(self, event: QDragEnterEvent):
        if event.mimeData().hasUrls():
            url = event.mimeData().urls()[0]
            if Path(url.toLocalFile()).suffix.lower() in AUDIO_SUFFIXES:
                event.acceptProposedAction()
                self._set_drag_highlight(True)
                return
        event.ignore()

    def dragLeaveEvent(self, event):
        self._set_drag_highlight(False)

    def dropEvent(self, event: QDropEvent):
        self._set_drag_highlight(False)
        path = event.mimeData().urls()[0].toLocalFile()
        self.file_path_edit.setText(path)
        self.config.set("last_directory", str(Path(path).parent))
