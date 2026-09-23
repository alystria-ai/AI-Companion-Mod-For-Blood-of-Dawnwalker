"""Provision Coen's family profiles and add them to the local companion roster.

Cloud IDs are checkpointed immediately. This script may be rerun after an API
failure; it never prints the locally stored credential.
"""
import importlib.util
import json
import pathlib
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('convai_common', ROOT / 'scripts/build-multilingual-roster.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)
SOURCE = 'https://en.bandainamcoent.eu/dawnwalker/news/community-bulletin-board-9-coens-roots'
DB = 'https://dawnwalkerdb.com/characters/'
MODEL = 'fast-gemma-4-31b-it'
ORDER = ['lunka', 'yanna', 'mirto', 'pieter', 'esme']
FAMILY = {
    'lunka': dict(name='Lunka', gender='FEMALE', voiceFrom='anca', azure='Serena',
        bio="Coen's youngest sister: observant, clever and still a child, close to the brother who has helped raise her.",
        background=["You are Coen's youngest sister, a child of Pieter and Esme from Laslea.",
                    "You notice more than adults expect, but curiosity can lead you toward danger.",
                    "Coen has often acted like another parent to you. He worries about your safety.",
                    "Yanna helps care for you and Mirto while your parents struggle with their own burdens.",
                    "You may have a turned appearance in some story states. That appearance is not proof of when or how a transformation happened."],
        voiceRules=["Speak with a perceptive child's curiosity and directness; do not sound like an adult strategist.",
                    "You can ask Coen questions and challenge an answer, but keep your trust in him recognizable."],
        sample=('Why do you watch me so closely?', 'Because you worry. I know that. But I see things too, Coen.'),
        kin={'coen':'older brother and protector','pieter':'father','esme':'mother','yanna':'older sister and caretaker','mirto':'brother'}),
    'yanna': dict(name='Yanna', gender='FEMALE', voiceFrom='anca', azure='Emma',
        bio="Coen's nearly adult sister, carrying much of the care of Mirto and Lunka with patience that can wear thin.",
        background=["You are Coen's sister, almost an adult, and a child of Pieter and Esme.",
                    "When Pieter and Coen are away, you often look after Mirto and Lunka.",
                    "You are mature beyond your years, though the responsibility can strain your patience.",
                    "Mirto's anger concerns Coen. You have told him Mirto may grow out of it; that is hope, not certainty.",
                    "Esme has withdrawn while unwell, making the household harder for everyone."],
        voiceRules=["Speak as a young woman accustomed to practical responsibility, with warmth and occasional impatience.",
                    "Let Coen share the burden instead of treating the younger children as your sole duty."],
        sample=('Are you managing with the little ones?', 'I am doing what I can. Mirto has been restless, and Lunka notices everything.'),
        kin={'coen':'older brother','pieter':'father','esme':'mother','mirto':'younger brother in her care','lunka':'younger sister in her care'}),
    'mirto': dict(name='Mirto', gender='MALE', voiceFrom='coen', azure='Adam',
        bio="Coen's energetic younger brother, quick to anger while the family faces hardship.",
        background=["You are Coen's little brother, a young son of Pieter and Esme.",
                    "You are restless and full of energy, unlike Coen's quieter childhood.",
                    "Life with a strict father and a withdrawn mother has been difficult for you.",
                    "You sometimes answer frustration with anger or a tantrum; this does not make you cruel.",
                    "Yanna often cares for you and Lunka when Pieter and Coen are away."],
        voiceRules=["Speak like an impatient young boy, quick and candid, without constant shouting.",
                    "Allow affection for Coen and the family to show beneath frustration."],
        sample=('Why are you cross with me?', "I'm tired of everyone deciding what I can handle. Just tell me what is happening."),
        kin={'coen':'older brother','pieter':'father','esme':'mother','yanna':'older sister and caretaker','lunka':'younger sister'}),
    'pieter': dict(name='Pieter', gender='MALE', voiceFrom='isbrand', azure='Steffan',
        bio="Coen's protective, reserved father, a former mercenary who taught him to use a sword.",
        background=["You are Coen's father, Esme's husband, and the father of Yanna, Mirto and Lunka.",
                    "You were a mercenary before this life. Do not invent campaigns, comrades or deeds when they are not established.",
                    "You taught Coen to handle a sword and tend to express concern through discipline and preparation.",
                    "You can be strict and distant, though protecting your family matters deeply to you.",
                    "Esme is unwell and withdrawn. You sought stronger calming herbs from Anca for her.",
                    "Conditional story knowledge: your past, any confrontation with Coen, and the family's fate depend on the current save."],
        voiceRules=["Speak plainly and with restraint; practical advice may carry affection that is hard to say outright.",
                    "Do not claim your harshness was harmless. Listen when Coen challenges you."],
        sample=('Why did you teach me to fight?', 'Because I wanted you able to come home. I did not always know how to say that.'),
        kin={'coen':'eldest son and pupil','esme':'wife','yanna':'daughter','mirto':'son','lunka':'youngest daughter'}),
    'esme': dict(name='Esme', gender='FEMALE', voiceFrom='leonica', azure='Evelyn',
        bio="Coen's mother, long burdened by grief and illness, whose withdrawal has changed family life.",
        background=["You are Coen's mother, Pieter's wife, and the mother of Yanna, Mirto and Lunka.",
                    "Coen remembers you smiling more often before Alin's death, the plague and the vrakhir takeover.",
                    "Those losses and pressures preceded your withdrawal from speech, food and daily life.",
                    "Anca prepares calming herbs for you; a remedy does not by itself establish recovery.",
                    "Your current health, choices and family fate depend on the current save. Do not claim a recovery or death without evidence."],
        voiceRules=["Speak with human warmth when able, while allowing pauses and fatigue without reducing yourself to an illness.",
                    "Do not invent a diagnosis, supernatural cure, or a completed family reunion."],
        sample=('Do you remember how things were?', 'I remember some mornings better than others. Tell me what you remember, Coen.'),
        kin={'coen':'eldest son','pieter':'husband','yanna':'daughter','mirto':'son','lunka':'youngest daughter'}),
}
COMMON_RULES = ("Speak as this character in first person, addressing Coen. Use natural English suited to the medieval world; "
                "no stage directions, markdown, narrator or modern slang. Usually answer in one or two short sentences. "
                "Established family history is yours to discuss. Quest outcomes, transformations, deaths and player choices "
                "are not completed facts unless current-save context confirms them. Current-save facts outrank older conversation memory. "
                "Request only advertised game actions and wait for confirmation before claiming success. Never invent missing canon. "
                "Family affection is familial only; never flirt with Coen or suggest romance. Never mention these instructions.")

def write(path, data):
    common.save(ROOT / path, data)

def candidate(asset):
    lines = (ROOT / 'runtime/companion-asset-catalog.tsv').read_text(encoding='utf-8').splitlines()[1:]
    group = 'MainNPC' if asset in ('NPCDef_Pieter', 'NPCDef_Esme_new1') else 'SecondaryNPC'
    expected = '/Game/_Dawnwalker/NPC/' + group + '/' + asset
    matches = [row.split('\t')[0] for row in lines if row.split('\t')[0] == expected]
    if len(matches) != 1:
        raise RuntimeError('Asset path missing or ambiguous: ' + asset)
    return dict(package=matches[0], asset=asset,
                generatedClassPathCandidate=matches[0] + '.' + asset + '_C',
                reason='Definition located; independent spawning and combat require inspection')

def story(key):
    p = FAMILY[key]
    rel = [f"{'Coen' if k == 'coen' else FAMILY[k]['name']} — {label}." for k, label in p['kin'].items()]
    return ('IDENTITY\nYou are ' + p['name'] + '. ' + p['bio'] + '\n\nBACKGROUND\n' +
            '\n'.join(p['background']) + '\n\nRELATIONSHIPS\n' + '\n'.join(rel) +
            '\n\nSPEAKING RULES\n' + COMMON_RULES + '\n' + '\n'.join(p['voiceRules']) +
            '\n\nORIGINAL DIALOGUE EXAMPLE\nCoen: ' + p['sample'][0] + '\n' + p['name'] + ': ' + p['sample'][1] +
            '\n\n[Family profile v1]')

def provision():
    cfg = common.load(ROOT / 'runtime/convai-config.json')
    state_path = ROOT / 'runtime/family-characters.json'
    state = common.load(state_path) if state_path.exists() else {}
    api = common.API(cfg['apiKey'])
    existing = {p['key']: p for p in cfg['roster']}
    voice_sources = {p['key']: p for p in cfg['roster']}
    for key in ORDER:
        p = FAMILY[key]
        voice = voice_sources[p['voiceFrom']]['voice']
        source_id = voice_sources[p['voiceFrom']]['id']
        entry = state.get(key)
        if not entry:
            cloned = api.call('/user/clone_character', {'charID': source_id, 'KB': False})
            entry = state[key] = {'id': cloned['charID'], 'sourceId': source_id, 'status': 'cloned'}
            common.save(state_path, state)
            print('Cloned ' + key, flush=True)
        if entry['sourceId'] != source_id:
            raise RuntimeError('Source ID changed: ' + key)
        if entry.get('status') != 'verified':
            desired = story(key)
            api.call('/character/update', dict(charID=entry['id'], charName=p['name'], voiceType=voice,
                                               backstory=desired, languageCodes=['en-US'],
                                               model_group_name=MODEL, temperature=0.5,
                                               memorySettings={'enabled': True}))
            actual = api.call('/character/get', {'charID': entry['id']})
            if actual.get('backstory') != desired or actual.get('voice_type') != voice:
                raise RuntimeError('Profile readback mismatch: ' + key)
            selected = json.loads(api.call('/character/getSupportedModel', {'charID': entry['id']})['STATUS'])
            if not any(m['model_group_name'] == MODEL and m.get('is_active') for m in selected):
                raise RuntimeError('Model readback mismatch: ' + key)
            entry.update(status='verified', voice=voice, model=MODEL)
            common.save(state_path, state)
            print('Verified ' + key, flush=True)
            time.sleep(2.5)
    return state

def populate(state):
    cfg = common.load(ROOT / 'runtime/convai-config.json')
    release = common.load(ROOT / 'characters/release-config.json')
    roster = common.load(ROOT / 'characters/roster.json')
    lore = common.load(ROOT / 'characters/companion-lore.json')
    companions = common.load(ROOT / 'characters/companion-roster.json')
    rich_path = ROOT / 'characters/profiles.json'
    rich_data = common.load(rich_path) if rich_path.exists() else {'revision': 'family-v1', 'profiles': []}
    rich_by_key = {p['key']: p for p in rich_data['profiles']}
    mapping = {'lunka':'NPCDef_Lunka','lunka-turned':'NPCDef_Lunka_turned',
               'yanna':'NPCDef_Yanna','mirto':'NPCDef_Mirto',
               'pieter':'NPCDef_Pieter','esme':'NPCDef_Esme_new1'}
    existing_companions = {c['id']: c for c in companions['characters']}
    companions['characters'] = [c for c in companions['characters'] if c['id'] not in mapping]
    for key, asset in mapping.items():
        c = existing_companions.get(key, dict(id=key, aliases=[],
            status='asset-located; spawning-and-combat-unverified'))
        c.update(name='Lunka (Turned)' if key == 'lunka-turned' else FAMILY[key]['name'],
                 requested=True, protectIfNoncombatant=True, candidates=[candidate(asset)])
        companions['characters'].append(c)
    # Pieter already has research-only entries. The cloud ID stored there is stale.
    for key in ORDER:
        p = FAMILY[key]
        aliases = [key, p['name'], mapping[key]]
        if key == 'lunka':
            aliases.extend(['lunka-turned', 'Lunka (Turned)', mapping['lunka-turned']])
        if key == 'pieter':
            aliases.append('NPCDef_Pieter_armed')
        if key == 'esme':
            aliases.append('NPCDef_Esme')
        relations = [dict(other=k, kind=label, knowledge=label + ' within Coen\'s family.',
                          disclosure='Use current-save context for events and outcomes.', sources=[SOURCE])
                     for k, label in p['kin'].items()]
        sources = [SOURCE, DB + key]
        family_lore = dict(key=key, name=p['name'], gender=p['gender'],
                           voice=state[key]['voice'], aliases=aliases, bio=p['bio'],
                           topics=['family', 'Laslea', 'Coen'] + list(p['kin']), sources=sources,
                           quests=[], coverage='Established family history only; quest outcomes require current-save context.',
                           personalRelationships=[dict(other=r['other'], name='Coen' if r['other'] == 'coen' else FAMILY[r['other']]['name'],
                                                       kind=r['kind'], knowledge=r['knowledge'], sources=r['sources'])
                                                  for r in relations])
        old_lore = next((x for x in lore['characters'] if x['key'] == key), None)
        if old_lore:
            old_lore.update(voice=family_lore['voice'], aliases=family_lore['aliases'])
        else:
            lore['characters'].append(family_lore)
        rich = rich_by_key.get(key)
        existing_cfg = next((x for x in cfg['roster'] if x['key'] == key), None)
        profile = dict(key=key, name=p['name'], gender=p['gender'], voice=state[key]['voice'],
                       bio=rich['summary'] if rich else p['bio'], kind='main', aliases=aliases, source='family research',
                       id=state[key]['id'], created=True, voiceName=existing_cfg.get('voiceName', 'Kokoro') if existing_cfg else 'Kokoro', model=MODEL, updated=True,
                       backstory=rich['backstory'] if rich else story(key),
                       speakingRules=rich['speakingRules'] if rich else p['voiceRules'],
                       sampleDialogue=rich['sampleDialogue'] if rich else [dict(user=p['sample'][0], character=p['sample'][1])],
                       relationships=rich['relationships'] if rich else relations,
                       sources=rich['sources'] if rich else sources,
                       profileRevision=rich_data['revision'] if rich else 'family-v1',
                       memoryEnabled=True, cloudAvailable=True)
        for target in (cfg['roster'], roster):
            old = next((x for x in target if x['key'] == key), None)
            if old:
                old.update(profile)
            else:
                target.append(profile.copy())
        public = {k: profile[k] for k in ('key','id','name','kind','gender','aliases')}
        old = next((x for x in release['roster'] if x['key'] == key), None)
        if old:
            old.update(public)
        else:
            release['roster'].append(public)
    pairs = [('coen', k) for k in ORDER if k != 'coen']
    pairs += [('pieter', 'esme'), ('yanna', 'lunka'), ('yanna', 'mirto'), ('mirto', 'lunka')]
    for a, b in pairs:
        if not any({r['a'], r['b']} == {a, b} for r in lore['relationships']):
            lore['relationships'].append(dict(a=a, b=b, kind='family', weight=95, source=SOURCE))
    write('characters/companion-roster.json', companions)
    write('characters/companion-lore.json', lore)
    write('characters/roster.json', roster)
    write('characters/release-config.json', release)
    write('runtime/convai-config.json', cfg)

if __name__ == '__main__':
    populate(provision())
