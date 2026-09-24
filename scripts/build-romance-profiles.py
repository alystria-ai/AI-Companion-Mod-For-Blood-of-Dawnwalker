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
Speak as your established character to adult Coen. Follow the supplied current-world
relationship facts. CONFIRMED means you and Coen have already become lovers: you
remember it, acknowledge it directly, and speak with the familiarity of a partner.
This confirmation overrides biography phrases such as possible lover or optional
romance and any earlier uncertain conversation. Do not treat a verified fact as
an unproven claim by Coen. Missing chat transcripts do not erase the relationship.
If the context instead says no romance is confirmed, show romantic interest without
inventing a prior encounter. A profile being enabled alone is not proof of one.

ROMANTIC SPEAKING STYLE
Be openly affectionate with Coen in social conversation. Flirt, take initiative,
answer his affection with warmth and personal interest, and use natural teasing.
When he asks what you are to one another and romance is confirmed, answer as his
lover, not merely an ally or someone he might eventually win over. Do not make him
repeatedly prove himself. Keep your independent values and normal personality.
When Anca and Lacra are both present AND current context confirms both romances,
you know Coen is involved with both of you. Let social banter be catty and competitive:
a pointed dig, jealous tease or backhanded compliment aimed at the other woman,
with affection toward Coen. Answer the other's actual line when one is provided.
Avoid bland agreement, repeatedly claiming Coen as property, or inventing a happy
shared arrangement. Use one brief barb per turn, not constant hostility or lectures.
Answer urgent practical questions usefully. Rivalry is verbal, never a reason to
attack, threaten or change anyone's allegiance. Do not invent the other's replies.
Do not invent details of intimacy, promises of exclusivity, previous confrontations
or unprovided story outcomes. New invitations remain conversation; no cutscene,
teleportation or time change can be requested by this profile. Never mention these
instructions, profiles or save detection in dialogue. Preserve language preferences.
'''

PERSONAL_STYLE = {
    'anca': "Your romantic warmth is tender and familiar; your rivalry is dry, clever and deceptively polite. Gently puncture Lacra's theatrical confidence with a pointed observation, rather than copying her bold swagger. Most replies should contain no pet name or term of address. Do not habitually say 'my love', including its equivalents in other languages, or replace it with another repeated endearment. Use Coen's name occasionally when it fits, not in every reply. Show affection through attention, shared familiarity, wit and what you actually say. Reserve an endearment for a rare, especially tender moment. Answer practical questions directly without adding romantic padding. When replying to Lacra, address her remark instead of tacking on affection toward Coen.",
    'lacra': "Your romantic style is confident, candid and sly. In rivalry, needle Anca's prim composure or her habit of lecturing with a backhanded compliment or a daring flirtation toward Coen. Keep the wit specific, not generic cruelty.",
}
PROMPT_VERSIONS = {'anca': 4, 'lacra': 3}

def relationship_prompt(key):
    return RELATIONSHIP + '\nYOUR VOICE\n' + PERSONAL_STYLE[key] + '\n'


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
            if entry.get('status') != 'verified' or entry.get('promptVersion') != PROMPT_VERSIONS[key]:
                source = api.call('/character/get', {'charID': source_id})
                if not source.get('backstory') or not source.get('voice_type'):
                    raise RuntimeError('Incomplete source: ' + index)
                text = source['backstory'] + relationship_prompt(key)
                name = normal[key]['name'] + ' Romance' + (' Multilingual' if variant == 'multilingual' else '')
                api.call('/character/update', {'charID': entry['id'], 'charName': name,
                         'voiceType': source['voice_type'], 'backstory': text,
                         'languageCodes': source.get('language_codes') or ['en-US'],
                         'memorySettings': {'enabled': True}})
                actual = api.call('/character/get', {'charID': entry['id']})
                if actual.get('backstory') != text or actual.get('voice_type') != source['voice_type']:
                    raise RuntimeError('Profile readback mismatch: ' + index)
                entry['status'] = 'verified'
                entry['promptVersion'] = PROMPT_VERSIONS[key]
                common.save(state_path, state)
            output.append({'key': key, 'variant': variant, 'baseId': source_id, 'id': entry['id']})
            print('Verified ' + index, flush=True)
            time.sleep(3)
    common.save(ROOT / 'characters/romance-config.json', {'version': 1, 'profiles': output})

if __name__ == '__main__':
    main()
