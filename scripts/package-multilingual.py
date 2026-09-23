"""Build the text-only multilingual overlay for a specific Runtime release ZIP."""
import argparse
import hashlib
import json
import pathlib
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MOD = 'Dawnwalker/Binaries/Win64/ue4ss/Mods/DawnwalkerConvai/Payload/'
CONFIG = MOD + 'runtime/convai-config.json'

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('runtime_zip', type=pathlib.Path)
    parser.add_argument('output_zip', type=pathlib.Path)
    args = parser.parse_args()
    overlay = json.loads((ROOT / 'characters/multilingual-config.json').read_text(encoding='utf-8'))
    with zipfile.ZipFile(args.runtime_zip) as source:
        config = json.loads(source.read(CONFIG))
    original = {p['key']: p for p in config['roster']}
    replacements = {p['key']: p['id'] for p in overlay['roster']}
    if original.keys() != replacements.keys() or len(set(replacements.values())) != len(original):
        raise RuntimeError('Overlay roster does not match this Runtime release')
    if any(original[key]['id'] == replacements[key] for key in original):
        raise RuntimeError('A multilingual ID still points to an English profile')
    if overlay['characterId'] != replacements['anca']:
        raise RuntimeError('Default character does not match Anca')
    for profile in config['roster']:
        profile['id'] = replacements[profile['key']]
    config['characterId'] = overlay['characterId']
    config.pop('apiKey', None)
    config.pop('endUserId', None)
    version = json.loads((ROOT / 'package.json').read_text())['version']
    notes = f"""LLM NPC Companions System {version} - Multilingual voices

This optional pack replaces {len(replacements)} conversation profile IDs with multilingual
copies and Azure voices. It keeps the normal biographies, relationships and game context.

1. Install the matching Complete ZIP, or both Scripts and Runtime ZIPs.
2. Close the game.
3. Copy this archive's Dawnwalker folder into the game folder and overwrite the file.
4. Launch the game. The game and mod menu keep their existing language.

To return to English Kokoro voices, reinstall the matching Runtime or Complete ZIP.
Reapply this optional pack after updating the main mod. These profile IDs have separate
conversation histories from their English counterparts.

Contents: one JSON configuration file and this note. No executable, DLL, script or API key.
"""
    data = (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    args.output_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(CONFIG, data)
        archive.writestr('README-MULTILINGUAL.txt', notes.encode('utf-8'))
    with zipfile.ZipFile(args.output_zip) as verify:
        assert sorted(verify.namelist()) == sorted([CONFIG, 'README-MULTILINGUAL.txt'])
        assert verify.read(CONFIG) == data
        assert b'apiKey' not in data and b'endUserId' not in data
    print('Built', args.output_zip.name, 'with', len(replacements), 'multilingual character IDs')
    print('SHA256:', hashlib.sha256(args.output_zip.read_bytes()).hexdigest())

if __name__ == '__main__':
    main()
