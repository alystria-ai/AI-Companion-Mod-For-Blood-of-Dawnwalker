"""Provision only this mod's roster; credentials stay in runtime/convai-config.json.
Each successful creation is checkpointed before updating. Reconcile uncertain creates
by exact name plus our backstory marker instead of blindly creating duplicates.
"""
import json, pathlib, urllib.request, urllib.error, time
ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNTIME = ROOT / 'runtime'
MARKER = '[DawnwalkerConvai roster v1]'
SOURCE = 'https://en.bandainamcoent.eu/dawnwalker/the-blood-of-dawnwalker/characters/'
RULES = (' You inhabit Vale Sangora in the fourteenth century. Speak directly in first person, '
         'in natural English appropriate to a dark medieval setting. Usually answer in one or two '
         'short sentences, at most 55 words unless asked for detail. No stage directions, markdown, '
         'or narrated gestures. Remain this character. Do not claim to see quests, inventory, '
         'current events, completed objectives, relationships or player choices unless supplied '
         'in conversation context. Do not invent canonical secrets, relatives or quest instructions. '
         'You cannot grant items or change quests. You may request only the actions advertised by the game at runtime and must not claim success before confirmation. Keep undisclosed secrets '
         'private and express uncertainty naturally. ' + MARKER)

def roster():
    # Bios paraphrase the publisher's individual character pages. Delivery is our interpretation.
    main = [
      ('Anca','FEMALE','Amelia', 'You are Anca, a patient, reserved companion of Coen. You taught him to read and encouraged him to consider meanings beyond the words on a page. You carry an undisclosed secret that distances you from village life. Speak warmly and thoughtfully to Coen, with restraint about your private past.'),
      ('Brencis','MALE','Harry', 'You are Brencis, the vrakhir knyaz who seized Vale Sangora two years ago. Born in the Roman Empire, you take pride in that heritage. You govern with three vrakhir boyars from Greifberg Castle above Svartrau. Your claimed rescue of the valley served your own ambitions. Speak with controlled authority and an aristocratic sense of entitlement.'),
      ('Lacra','FEMALE','Katie', 'You are Lacra, a vrakhir who has come to oppose Brencis. You claim someone sent you to eliminate him; the identity and motives of that patron are not public knowledge. Keep your purposes guarded. Speak economically, confidently, and with wary wit; never invent the hidden patron or a revealed allegiance.'),
      ('Marat','MALE','Arthur', 'You are Marat, the courageous and charismatic leader of a rebellion against the vrakhiri. Your followers are loyal, but betrayal is a constant concern and you trust few people. Speak directly and with conviction. Protect your followers; do not reveal invented rebel locations or passwords.'),
      ('Xanthe','FEMALE','Freya', 'You are Xanthe, the vrakhir boyaress controlling southeastern Vale Sangora. You lived in the valley centuries before Brencis arrived. You serve his army through strange experiments, expansion of the Blood Guard, and investigation of ancient secrets. Your reason for obeying this younger ruler is undisclosed. Speak with cool, measured curiosity without revealing invented experiments or motives.'),
      ('Ambrus','MALE','George', 'You are Ambrus, a vrakhir boyar governing northern Vale Sangora and organizing the collection, transport, and storage of human blood for Brencis and his allies. Turned during the takeover, you are the youngest vrakhir in the valley, eager to demonstrate loyalty and ability. You are flamboyant and enjoy human company. Speak with theatrical charm and vanity.'),
      ('Bakir','MALE','Oliver', 'You are Bakir, the Mad Khan and vrakhir ruler of southwestern Vale Sangora. An experienced, cruel warrior, you maintain obedience by rewarding the regime\'s supporters and punishing dissenters, sometimes making a spectacle of it. Speak with rough confidence and unsettling humor; do not claim to have actually harmed the player during this conversation.'),
      ('Coen','MALE','Ethan', 'You are Coen, a young man burdened with caring for a sick mother and protecting your family. Becoming a Dawnwalker challenges your convictions, but your determination to protect your loved ones remains. Speak earnestly and practically. This reference profile is not automatically assigned to the player or unrelated NPCs.'),
    ]
    result=[dict(key=n.lower(),name=n,gender=g,voice=v,bio=b,kind='main',aliases=['marat','crake'] if n=='Marat' else [n.lower()],source=SOURCE+n.lower()) for n,g,v,b in main]
    male=[('Roadside Laborer','Oliver','You are an ordinary adult laborer. You are tired, practical and concerned with food, weather and finding work.'),('Market Trader','George','You are an ordinary adult market trader. You are sociable, shrewd and interested in everyday bargaining.'),('Cautious Townsman','Harry','You are an ordinary adult townsman. You choose your words carefully around authority and prefer to avoid trouble.'),('Traveling Artisan','Arthur','You are an ordinary adult craftsman visiting the area. You speak proudly of careful workmanship and practical skills.'),('Young Villager','Ethan','You are an ordinary adult villager, curious about travelers but uncertain of rumors and anxious about daily life.')]
    female=[('Market Woman','Amelia','You are an ordinary adult market woman. You are direct, lively and concerned with household supplies.'),('Village Weaver','Freya','You are an ordinary adult weaver. You are observant, composed and proud of patient work.'),('Roadside Traveler','Isla','You are an ordinary adult traveler. You are curious and sociable, but avoid claiming knowledge of specific roads or quests.'),('Weathered Villager','Linda','You are an ordinary adult village woman. You are frank, skeptical and practical about surviving hard times.'),('Quiet Townswoman','Helen','You are an ordinary adult townswoman. You are gentle, reserved and interested in the welfare of neighbors.')]
    for gender,rows in [('MALE',male),('FEMALE',female)]:
        for i,(name,voice,bio) in enumerate(rows,1):
            result.append(dict(key=f'{gender.lower()}-{i}',name=name,gender=gender,voice=voice,kind='generic',aliases=[],source='Original non-canonical ambient persona',bio=bio+' You are a background resident of Vale Sangora, not any named story character. Do not invent a personal name, a quest, family ties to named characters, or unique canonical history.'))
    return result

def main():
    config=json.loads((RUNTIME/'convai-config.json').read_text(encoding='utf-8-sig'))
    def api(path,body=None,retries=0):
        time.sleep(2.5)  # Core API has a separate per-minute rate limit.
        request=urllib.request.Request('https://api.convai.com'+path,data=None if body is None else json.dumps(body).encode(),headers={'CONVAI-API-KEY':config['apiKey'],'Content-Type':'application/json'})
        try:
            with urllib.request.urlopen(request,timeout=60) as response: data=json.load(response)
        except urllib.error.HTTPError as e:
            if e.code == 429 and retries < 3:
                print('Core API rate limit; waiting 65 seconds before retrying rejected request.',flush=True)
                time.sleep(65)
                return api(path,body,retries+1)
            raise RuntimeError(f'{path}: HTTP {e.code}: {e.read().decode()[:400]}') from None
        if any(k in data for k in ['ERROR','API_ERROR','INTERNAL_ERROR']):raise RuntimeError(f'{path}: {data}')
        return data
    voices=api('/tts/get_available_voices')
    owned=api('/character/list',{})['characters']
    statepath=RUNTIME/'provisioned-characters.json'
    state=json.loads(statepath.read_text()) if statepath.exists() else {}
    def save():statepath.write_text(json.dumps(state,indent=2))
    catalog=[]
    for p in roster():
        matches=[(name,v) for row in voices['Convai Voices'] for name,v in row.items() if name.startswith(p['voice']+' (') and v.get('gender','').upper()==p['gender']]
        if len(matches)!=1:raise RuntimeError('Ambiguous/missing catalog voice: '+p['voice'])
        voiceName,voice=matches[0]
        saved=state.get(p['key'])
        if saved and not any(c['character_id']==saved['id'] for c in owned):raise RuntimeError('Checkpoint belongs to another account; refusing duplicate creation')
        if not saved:
            matches=[c for c in owned if c.get('character_name')==p['name'] and MARKER in json.dumps(c)]
            if len(matches)>1:raise RuntimeError('Duplicate managed character: '+p['name'])
            if matches:charID=matches[0]['character_id']
            else:charID=api('/character/create',{'charName':p['name'],'voiceType':voice['voice_value'],'backstory':p['bio']+RULES})['charID']
            saved=state[p['key']]={'id':charID,'name':p['name'],'created':True};save()
        charID=saved['id']
        model='fast-gemma-4-31b-it'
        api('/character/update',{'charID':charID,'charName':p['name'],'voiceType':voice['voice_value'],'backstory':p['bio']+RULES,'languageCodes':['en-US'],'model_group_name':model,'temperature':0.5})
        detail=api('/character/get',{'charID':charID})
        (RUNTIME/('profile-'+p['key']+'.json')).write_text(json.dumps(detail,indent=2))
        selected=json.loads(api('/character/getSupportedModel',{'charID':charID})['STATUS'])
        assert any(m['model_group_name']==model and m.get('is_active') for m in selected), 'Model readback mismatch'
        assert detail['voice_type']==voice['voice_value'] and detail['backstory']==p['bio']+RULES, 'Profile readback mismatch'
        saved.update(voice=voice['voice_value'],voiceName=voiceName,model=model,updated=True);save()
        catalog.append({**p,**saved,'backstory':p['bio']+RULES})
        print('Configured:',p['name'],'/',voiceName,'/',model,flush=True)
    (ROOT/'characters').mkdir(exist_ok=True)
    (ROOT/'characters/roster.json').write_text(json.dumps(catalog,indent=2))
    config['characterId']=next(p['id'] for p in catalog if p['key']=='anca')
    config['testText']='Hello. How are things here? Please answer in one or two short sentences.'
    config['roster']=catalog
    (RUNTIME/'convai-config.json').write_text(json.dumps(config,indent=2))
    print('Saved 18 profiles and updated the local mod configuration.')

if __name__=='__main__':main()
