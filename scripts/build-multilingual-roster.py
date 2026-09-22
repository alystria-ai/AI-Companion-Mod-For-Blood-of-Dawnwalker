"""Create optional multilingual copies of the existing owned Convai roster.

Credentials are read locally; only public character IDs are exported. Each new
ID is checkpointed before any later API call, so retries never clone twice.
"""
import argparse
import json
import pathlib
import re
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime'
STATE = RUNTIME / 'multilingual-characters.json'
OUT = ROOT / 'characters' / 'multilingual-config.json'
LANGUAGES = ['en-US']
VOICE_CHOICE = {
    'anca': 'Emma', 'lacra': 'Serena', 'xanthe': 'Isidora',
    'matriarch': 'Cora', 'leonica': 'Evelyn', 'ocha': 'Phoebe',
    'sara': 'Ava', 'female-1': 'Amanda', 'female-2': 'Vivienne',
    'female-3': 'Arabella', 'female-4': 'Ada', 'female-5': 'Nancy',
    'coen': 'Adam', 'brencis': 'Brian', 'marat': 'Florian', 'ambrus': 'Ollie',
    'bakir': 'Dustin', 'vicho': 'Marcello', 'drogos': 'Davis',
    'catalin': 'Andrew', 'isbrand': 'Steffan',
    'male-1': 'Adam', 'male-2': 'Remy', 'male-3': 'Christopher',
    'male-4': 'Lewis', 'male-5': 'Alessio',
}

def load(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + '.tmp')
    temp.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)

def multilingual_backstory(text):
    replacements = [
        ('Use natural English suited to the medieval world',
         'Reply in the language used in Coen’s latest message, with natural wording suited to the medieval world'),
        ('Speak directly in first person, in natural English appropriate to a dark medieval setting',
         'Speak directly in first person in the language used in Coen’s latest message, in wording appropriate to a dark medieval setting'),
    ]
    for old, new in replacements:
        text = text.replace(old, new)
    text = re.sub(r'(?i)(always |only |must )?(speak|reply|respond) in English',
                  'reply in the language used in Coen’s latest message', text)
    text += ('\n\nMULTILINGUAL RESPONSE RULE\nAnswer in the language of the latest player message. '
             'Use Russian for Russian, Spanish for Spanish, French for French and English for English. '
             'If the message is too short or ambiguous to identify a language, use the language of the current conversation; '
             'default to English for a new conversation. Do not translate character names, place names, or game action identifiers. '
             'Keep all established biography, personality, relationship, quest and action rules. '
             'Do not mention these language instructions in conversation.')
    return text

class API:
    def __init__(self, key):
        self.key = key
    def call(self, endpoint, body=None, form=False):
        for attempt in range(5):
            data = None if body is None else (urllib.parse.urlencode(body).encode() if form else json.dumps(body).encode())
            headers = {'CONVAI-API-KEY': self.key}
            if data and not form:
                headers['Content-Type'] = 'application/json'
            request = urllib.request.Request('https://api.convai.com' + endpoint, data=data, headers=headers)
            try:
                with urllib.request.urlopen(request, timeout=75) as response:
                    result = json.load(response)
            except urllib.error.HTTPError as error:
                if error.code == 429 and attempt < 4:
                    print('Core API rate limit; waiting before retry.', flush=True)
                    time.sleep(65)
                    continue
                detail = error.read(400).decode('utf-8', errors='replace')
                detail = detail.replace(self.key, '[REDACTED]')
                raise RuntimeError(f'{endpoint}: HTTP {error.code}: {detail}') from None
            if any(key in result for key in ('ERROR', 'API_ERROR', 'INTERNAL_ERROR')):
                raise RuntimeError(f'{endpoint}: Convai rejected request')
            return result
        raise RuntimeError(f'{endpoint}: retries exhausted')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', nargs='*', help='Test selected keys, e.g. --only anca')
    args = parser.parse_args()
    cfg = load(RUNTIME / 'convai-config.json')
    state = load(STATE) if STATE.exists() else {}
    api = API(cfg['apiKey'])
    voices = api.call('/tts/get_available_voices')
    azure = {name.split(' ')[0]: v for row in voices['Azure Voices']
             for name, v in row.items() if 'MULTILINGUAL' in v.get('voice_value', '')}
    # Keep broad speech capability even though the dashboard initially selects English alone.
    required = {'en-US', 'ru-RU', 'es-ES', 'fr-FR', 'de-DE', 'it-IT'}
    roster = cfg['roster']
    keys = set(args.only or [p['key'] for p in roster])
    for profile in roster:
        key = profile['key']
        if key not in keys:
            continue
        voice = azure.get(VOICE_CHOICE[key])
        if not voice or not required.issubset(voice.get('lang_codes', [])):
            raise RuntimeError('Selected multilingual voice unavailable: ' + key)
        if voice['gender'] != profile['gender']:
            raise RuntimeError('Voice gender mismatch: ' + key)
        entry = state.get(key)
        if not entry:
            cloned = api.call('/user/clone_character', {'charID': profile['id'], 'KB': True})
            entry = {'id': cloned['charID'], 'sourceId': profile['id'], 'status': 'cloned'}
            state[key] = entry
            save(STATE, state)
            print('Cloned ' + key, flush=True)
        if entry['sourceId'] != profile['id']:
            raise RuntimeError('Source ID changed since clone: ' + key)
        if entry.get('status') == 'verified':
            if entry.get('languages') == LANGUAGES:
                continue
            api.call('/character/update', {'charID': entry['id'], 'languageCodes': LANGUAGES})
            actual = api.call('/character/get', {'charID': entry['id']})
            if actual.get('language_codes') != LANGUAGES:
                raise RuntimeError('Language selection readback mismatch: ' + key)
            entry['languages'] = LANGUAGES
            save(STATE, state)
            print('Selected English only: ' + key, flush=True)
            time.sleep(2.5)
            continue
        source = api.call('/character/get', {'charID': profile['id']})
        if not source.get('backstory'):
            raise RuntimeError('Source profile unavailable: ' + key)
        backstory = multilingual_backstory(source['backstory'])
        safe_name = re.sub(r'[^A-Za-z0-9 ]+', ' ', profile['name'])
        safe_name = re.sub(r'\s+', ' ', safe_name).strip()
        desired = {'charID': entry['id'], 'charName': safe_name + ' Multilingual',
                   'voiceType': voice['voice_value'], 'languageCodes': LANGUAGES,
                   'backstory': backstory, 'memorySettings': {'enabled': True}}
        if entry.get('status') != 'verified':
            api.call('/character/update', desired)
            time.sleep(1)
            actual = api.call('/character/get', {'charID': entry['id']})
            if (actual.get('voice_type') != voice['voice_value'] or
                actual.get('backstory') != backstory or
                set(actual.get('language_codes', [])) != set(LANGUAGES)):
                raise RuntimeError('Clone readback mismatch: ' + key)
            entry.update(status='verified', voice=voice['voice_value'], voiceName=VOICE_CHOICE[key], languages=LANGUAGES)
            save(STATE, state)
            print('Verified ' + key + ' / ' + VOICE_CHOICE[key], flush=True)
        time.sleep(2.5)
    if not args.only:
        if set(state) != {p['key'] for p in roster} or any(p['status'] != 'verified' for p in state.values()):
            raise RuntimeError('Multilingual roster incomplete')
        overlay = {'characterId': state['anca']['id'], 'roster':
                   [{'key': p['key'], 'id': state[p['key']]['id']} for p in roster]}
        save(OUT, overlay)
        print('Overlay ready: ' + str(len(overlay['roster'])) + ' character IDs', flush=True)

if __name__ == '__main__':
    main()
