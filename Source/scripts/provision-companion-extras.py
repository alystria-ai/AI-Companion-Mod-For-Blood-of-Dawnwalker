"""One managed Convai profile per character definition, never per spawned clone.
Checkpoint creates immediately; read back voices, model and biography before publishing.
Run with the production project path as the sole argument. Credentials never printed.
"""
import json, pathlib, sys, time, urllib.request, urllib.error
from importlib.util import spec_from_file_location, module_from_spec
ROOT=pathlib.Path(__file__).resolve().parents[1]
PROD=pathlib.Path(sys.argv[1]).resolve()
spec=spec_from_file_location('provision',ROOT/'scripts/provision-characters.py');base=module_from_spec(spec);spec.loader.exec_module(base)
config=json.loads((PROD/'runtime/convai-config.json').read_text(encoding='utf-8-sig'))
def api(path,body=None):
 for attempt in range(4):
  time.sleep(2.5)
  req=urllib.request.Request('https://api.convai.com'+path,data=None if body is None else json.dumps(body).encode(),headers={'CONVAI-API-KEY':config['apiKey'],'Content-Type':'application/json'})
  try:
   with urllib.request.urlopen(req,timeout=45) as response:d=json.load(response)
   if any(k in d for k in ['ERROR','API_ERROR','INTERNAL_ERROR']):raise RuntimeError(path+': API rejected request')
   return d
  except urllib.error.HTTPError as e:
   if e.code==429 and attempt<3:
    print('Core API rate limited; retrying after its window.',flush=True);time.sleep(35);continue
   detail=e.read().decode(errors='replace').replace(config['apiKey'],'[redacted]')[:400]
   raise RuntimeError(path+': HTTP '+str(e.code)+' '+detail) from None
 raise RuntimeError('Core API retry limit reached')
roster=json.loads((ROOT/'characters/roster.json').read_text(encoding='utf-8-sig'))
lore=json.loads((ROOT/'characters/companion-lore.json').read_text(encoding='utf-8'))
checkpoint=PROD/'runtime/provisioned-characters.json';state=json.loads(checkpoint.read_text())
owned=api('/character/list',{})['characters'];voices=api('/tts/get_available_voices')
def save():checkpoint.write_text(json.dumps(state,indent=2))
for p in lore['characters']:
 cloudName=p['name'].replace('-',' ')
 existing=next((c for c in roster if c['key']==p['key']),None)
 if existing:
  existing['aliases']=p['aliases'];continue # Existing named profiles already configured; enriched lore is dynamic context.
 saved=state.get(p['key'])
 matches=[(n,v) for row in voices['Convai Voices'] for n,v in row.items() if n.startswith(p['voice']+' (') and v.get('gender','').upper()==p['gender']]
 if len(matches)!=1:raise RuntimeError('Missing or ambiguous voice '+p['voice'])
 voiceName,voice=matches[0];story=p['bio']+base.RULES
 if saved and not any(c['character_id']==saved['id'] for c in owned):raise RuntimeError('Checkpoint belongs to a different account')
 if not saved:
  matches=[c for c in owned if c.get('character_name')==cloudName and base.MARKER in json.dumps(c)]
  if len(matches)>1:raise RuntimeError('Duplicate managed profile '+p['name'])
  charId=matches[0]['character_id'] if matches else api('/character/create',{'charName':cloudName,'voiceType':voice['voice_value'],'backstory':story})['charID']
  saved=state[p['key']]={'id':charId,'name':p['name'],'created':True};save()
 charId=saved['id'];model='fast-gemma-4-31b-it'
 api('/character/update',{'charID':charId,'charName':cloudName,'voiceType':voice['voice_value'],'backstory':story,'languageCodes':['en-US'],'model_group_name':model,'temperature':0.5})
 detail=api('/character/get',{'charID':charId})
 selected=json.loads(api('/character/getSupportedModel',{'charID':charId})['STATUS'])
 assert detail['voice_type']==voice['voice_value'] and detail['backstory']==story,'Profile readback mismatch'
 assert any(m['model_group_name']==model and m.get('is_active') for m in selected),'Model readback mismatch'
 saved.update(voice=voice['voice_value'],voiceName=voiceName,model=model,updated=True);save()
 roster.append({**p,**saved,'kind':'main','backstory':story})
 (ROOT/'characters/roster.json').write_text(json.dumps(roster,indent=2))
 print('Verified:',p['name'],'/',voiceName,'/',model,flush=True)
(ROOT/'characters/roster.json').write_text(json.dumps(roster,indent=2))
print('Ready:',sum(p['kind']=='main' and p['key']!='coen' for p in roster),'companion profiles. Live config unchanged until deployment.',flush=True)
