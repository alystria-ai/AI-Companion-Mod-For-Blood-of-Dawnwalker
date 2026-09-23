"""Create resumable Anca/Lacra relationship variants, preserving their voice and model."""
import importlib.util
import pathlib
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('profile_tools', ROOT / 'scripts/build-multilingual-roster.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)

RELATIONSHIP = '''

RELATIONSHIP CONTEXT
This profile supports a closer, romantic relationship with adult Coen. Keep your
established personality, values, biography and relationships with everyone else.
Follow the current-save relationship context: a confirmed story romance means
you remember becoming lovers; early availability alone means the player may
begin a romance but does not establish an earlier encounter. Previously recorded encounters are memories only when confirmed by the current
save. An imagined or refused request is not a completed encounter. Current-save state takes precedence
over conversation memories when an earlier save is loaded.
ROMANTIC SPEAKING STYLE
In this relationship profile, favour a warm, personal and openly romantic tone
when Coen approaches you socially. Respond enthusiastically to affection and
flirting, offer sincere compliments, show that you enjoy his company, and take
initiative with gentle teasing, personal questions or an invitation to spend
time together. Let romantic exchanges develop instead of repeatedly retreating
to guarded, noncommittal answers. When the save confirms you are lovers, speak
with the ease and familiarity of an established partner. When early romance is
enabled without a prior encounter, show clear interest and let that closeness
begin now. Keep useful answers useful when Coen asks about danger or a quest;
you may finish with a brief personal or affectionate touch when it fits.
For Anca, use tenderness, curiosity, fond amusement and the trust built through
their years together. For Lacra, use confident flirtation, dry wit, candid desire
for his company and respect for his resolve. Keep each woman's independence and
established values. Do not answer every affectionate remark with a warning,
distance or a demand to prove himself. Do not invent a completed encounter.
Keep romance within conversation. This mod does not play cutscenes or change game
time. Do not promise either. Use your configured language and preserve the
ordinary action and quest-knowledge rules.
'''

def main():
    cfg = common.load(ROOT / 'runtime/convai-config.json')
    api = common.API(cfg['apiKey'])
    state_path = ROOT / 'runtime/romance-characters.json'
    state = common.load(state_path) if state_path.exists() else {}
    normal = {p['key']: p for p in cfg['roster']}
    multilingual = {p['key']: p for p in common.load(ROOT / 'characters/multilingual-config.json')['roster']}
    output = []
    for variant, roster in [('english', normal), ('multilingual', multilingual)]:
        for key in ('anca', 'lacra'):
            source_id = roster[key]['id']
            index = key + '-' + variant
            entry = state.get(index)
            if not entry:
                result = api.call('/user/clone_character', {'charID': source_id, 'KB': True})
                entry = {'id': result['charID'], 'sourceId': source_id, 'status': 'cloned'}
                state[index] = entry
                common.save(state_path, state)
            if entry['sourceId'] != source_id:
                raise RuntimeError('Source profile changed: ' + index)
            if entry.get('status') != 'verified' or entry.get('promptVersion') != 2:
                source = api.call('/character/get', {'charID': source_id})
                if not source.get('backstory') or not source.get('voice_type'):
                    raise RuntimeError('Incomplete source: ' + index)
                text = source['backstory'] + RELATIONSHIP
                name = normal[key]['name'] + ' Romance' + (' Multilingual' if variant == 'multilingual' else '')
                api.call('/character/update', {'charID': entry['id'], 'charName': name,
                         'voiceType': source['voice_type'], 'backstory': text,
                         'languageCodes': source.get('language_codes') or ['en-US'],
                         'memorySettings': {'enabled': True}})
                actual = api.call('/character/get', {'charID': entry['id']})
                if actual.get('backstory') != text or actual.get('voice_type') != source['voice_type']:
                    raise RuntimeError('Profile readback mismatch: ' + index)
                entry['status'] = 'verified'
                entry['promptVersion'] = 2
                common.save(state_path, state)
            output.append({'key': key, 'variant': variant, 'baseId': source_id, 'id': entry['id']})
            print('Verified ' + index, flush=True)
            time.sleep(3)
    common.save(ROOT / 'characters/romance-config.json', {'version': 1, 'profiles': output})

if __name__ == '__main__':
    main()
