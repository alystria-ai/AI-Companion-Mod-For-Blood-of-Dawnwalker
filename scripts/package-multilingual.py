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
    notes = '''AI Companion Manager 0.30.9 — Multilingual voices

This optional pack changes conversation profiles and voices. English users can keep the normal mod.
All 26 cloud conversation profiles have separate multilingual Convai copies, with their original
biographies, relationships and game knowledge. The voices use Azure multilingual speech.

The copied profiles keep English selected while their language restriction is turned off in the
owner's Convai dashboard. All 26 profiles replied in Russian in testing. Spanish and French
spoken replies were also tested on Anca; the owner tested Arabic in the dashboard. Other
languages may work, but have not all been checked. Microphone input still needs an in-game test.

Install:
1. Install the main 0.30.9 Complete ZIP, or both matching Scripts and Runtime ZIPs.
2. Close the game and the helper if it is running.
3. Copy this archive's Dawnwalker folder into the game installation folder and overwrite the file.
4. Start the game. The F5 menu and companion combat stay the same.

To return to the original English Kokoro voices, reinstall the normal 0.30.9 Runtime or Complete
ZIP and overwrite the configuration file. After updating the main mod, install the matching
multilingual pack again. Conversation history and cloud memory for these new character IDs begin
separately from the English profiles. This pack does not translate the game or mod menu.

Contents: one JSON configuration file and this text file. No executable, DLL, API key, or script.
'''
    data = (json.dumps(config, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    args.output_zip.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(args.output_zip, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(CONFIG, data)
        archive.writestr('README-MULTILINGUAL.txt', notes.encode('utf-8'))
    with zipfile.ZipFile(args.output_zip) as verify:
        assert sorted(verify.namelist()) == sorted([CONFIG, 'README-MULTILINGUAL.txt'])
        assert verify.read(CONFIG) == data
        assert b'apiKey' not in data and b'endUserId' not in data
    print('Built', args.output_zip.name, 'with 26 multilingual character IDs')
    print('SHA256:', hashlib.sha256(args.output_zip.read_bytes()).hexdigest())

if __name__ == '__main__':
    main()
