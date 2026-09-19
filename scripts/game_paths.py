"""Resolve private installation paths without embedding a developer's location."""
from pathlib import Path
import json
import os

ROOT = Path(__file__).resolve().parents[1]

def game_bin():
    directory = os.environ.get('DAWNWALKER_GAME_DIRECTORY')
    if directory:
        return Path(directory) / 'Dawnwalker/Binaries/Win64'
    manifest = ROOT / 'runtime/installation.json'
    if manifest.is_file():
        return Path(json.loads(manifest.read_text(encoding='utf-8-sig'))['gameBin'])
    raise RuntimeError('Set DAWNWALKER_GAME_DIRECTORY or install the mod first.')
