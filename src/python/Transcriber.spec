# -*- mode: python ; coding: utf-8 -*-
from pathlib import Path

from PyInstaller.utils.hooks import collect_data_files
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.utils.hooks import collect_all

spec_dir = Path(SPECPATH)

datas = [(str(spec_dir / 'app'), 'app')]
binaries = []
hiddenimports = ['pyannote.audio', 'pyannote.audio.pipelines', 'pyannote.core', 'pyannote.metrics', 'pyannote.pipeline', 'speechbrain', 'whisper', 'torch', 'torchaudio', 'sklearn', 'sklearn.cluster', 'mlx', 'mlx.core', 'mlx_whisper']
datas += collect_data_files('speechbrain')
datas += collect_data_files('torch')
datas += collect_data_files('torchaudio')
hiddenimports += collect_submodules('speechbrain.inference')
hiddenimports += collect_submodules('speechbrain.nnet')
hiddenimports += collect_submodules('speechbrain.processing')
hiddenimports += collect_submodules('speechbrain.utils')
tmp_ret = collect_all('pyannote')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('whisper')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('asteroid_filterbanks')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('mlx_whisper')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]
tmp_ret = collect_all('mlx')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    [str(spec_dir / 'app' / 'main.py')],
    pathex=[str(spec_dir)],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=['speechbrain.integrations.k2_fsa', 'speechbrain.lobes.models.g2p'],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='Transcriber',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='Transcriber',
)
app = BUNDLE(
    coll,
    name='Transcriber.app',
    icon=None,
    bundle_identifier=None,
)
