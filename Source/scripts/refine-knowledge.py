import json,pathlib
root=pathlib.Path(__file__).resolve().parents[1]
p=root/'characters/quest-knowledge.json';d=json.loads(p.read_text(encoding='utf-8'))
rows=[l.split('\t') for l in (root/'runtime/quests.txt').read_text(encoding='utf-8-sig').splitlines()[2:] if l]
q=next(q for q in rows if q[2]=='What Hunts the Night')
if not any(r['key']=='marat-scouts-reported' for r in d['rules']):
 d['rules'].append(dict(key='marat-scouts-reported',quest=q[2],idPrefix=q[0][:-32],recipient='marat',state='EQS_Success',endingPattern=None,text='Coen reported his investigation of the dead scouts to you. You then investigated the churchyard together and escaped the ambush. You know of the winged monster encountered there.',reason='Completion guarantees the report at the start and the shared investigation. Where Loyalty Lies alone grants nothing.',source='https://www.powerpyx.com/blood-of-dawnwalker-what-hunts-the-night-walkthrough/'))
d['identitySources']={'marat':'https://www.pcgamer.com/games/rpg/blood-of-dawnwalker-romances/'}
d['withheld']=[q for q in d['withheld'] if q['quest']!='What Hunts the Night'];p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
p=root/'bridge/quest-knowledge.mjs';s=p.read_text().replace('.map(x=>x.toLowerCase());',".map(x=>x.toLowerCase()==='crake'?'marat':x.toLowerCase());").replace("['anca','lacra']","['anca','lacra','marat']");p.write_text(s)
p=root/'tests/game-context.test.mjs';s=p.read_text().replace('parseQuests,questContext,ActionQueue','parseQuests,ActionQueue');start=s.index(' assert.equal(snapshot.quests.length');end=s.index(' assert.throws',start);s=s[:start]+" assert.equal(snapshot.quests.length,2);\n const rollback=parseQuests(raw('one\\tEQS_Active\\tAnca helped\\t'),100000);\n assert.notEqual(snapshot.revision,rollback.revision);\n"+s[end:];p.write_text(s)
