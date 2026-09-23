"""Apply researched profiles to existing mod-owned Convai characters.

Default: read-only plan. --apply writes core descriptions (including speaking
rules and samples) and enables LTM. Deleted characters are never recreated.
"""
import argparse, json, pathlib, time, urllib.request, urllib.error

ROOT = pathlib.Path(__file__).resolve().parents[1]
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def write(path, data):
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    temp.replace(path)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true'); parser.add_argument('--only', nargs='*')
    options=parser.parse_args(); cfgpath=ROOT/'runtime/convai-config.json'
    cfg,roster=read(cfgpath),read(ROOT/'characters/roster.json'); rich=read(ROOT/'characters/profiles.json')
    desired={p['key']:p for p in rich['profiles']}
    folder=ROOT/'runtime/profile-enrichment'; folder.mkdir(exist_ok=True)
    def api(path,body=None):
        for attempt in range(4):
            time.sleep(2.5)
            req=urllib.request.Request('https://api.convai.com'+path,data=None if body is None else json.dumps(body).encode(),
                headers={'CONVAI-API-KEY':cfg['apiKey'],'Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(req,timeout=40) as response: result=json.load(response)
                if any(k in result for k in ['ERROR','API_ERROR','INTERNAL_ERROR']):raise RuntimeError('Convai rejected '+path)
                return result
            except urllib.error.HTTPError as e:
                if e.code==429 and attempt<3:
                    print('Core API rate limit: retrying after backoff.',flush=True); time.sleep(30); continue
                raise RuntimeError(path+' HTTP '+str(e.code)) from None
        raise RuntimeError('Core API retries exhausted')
    cloud=api('/character/list',{})['characters']; owned={p['character_id']:p for p in cloud}
    voices=api('/tts/get_available_voices')
    allowed={v['voice_value']:name for row in voices['Convai Voices'] for name,v in row.items()
             if str(v.get('voice_value','')).startswith('convai-kokoro-')}
    beforepath=folder/'cloud-before-enrichment.json'
    if options.apply and not beforepath.exists():write(beforepath,{'characters':cloud})
    family_keys={'lunka','yanna','mirto','pieter','esme'}
    def owned_marker(key, backstory):
        return ('[DawnwalkerConvai roster v1]' in backstory or
                (key in family_keys and '[Family profile v1]' in backstory))
    report={'revision':rich['revision'],'profiles':[],'missing':[],
            'strategy':'Core backstory sections include biography, rules and original sample replies; native speaking_style write API not established.'}
    for local in roster:
        key=local['key']; profile=desired[key]; current=owned.get(local['id'])
        if options.only and key not in options.only:continue
        if not current:
            report['missing'].append(key); print('Not present on account; retained as research only: '+key,flush=True); continue
        if not owned_marker(key,json.dumps(current)):
            current=api('/character/get',{'charID':local['id']})
            if not owned_marker(key,current.get('backstory','')):raise RuntimeError('Ownership marker missing: '+key)
        voice=current.get('voice_type','')
        if voice not in allowed:
            preferred=local.get('voice',''); voice=preferred if preferred in allowed else next(
                v['voice_value'] for row in voices['Convai Voices'] for _,v in row.items()
                if v.get('voice_value') in allowed and v.get('gender','').upper()==local['gender'])
        row={'key':key,'name':profile['name'],'words':profile['backstoryWords'],'voiceProvider':'Convai Kokoro',
             'voice':voice,'voiceName':allowed[voice],'memoryEnabled':False,'verified':False}
        if options.apply:
            payload={'charID':local['id'],'backstory':profile['backstory'],'memorySettings':{'enabled':True}}
            if current.get('voice_type')!=voice:payload['voiceType']=voice
            if key=='marat':payload['charName']='Crake'
            api('/character/update',payload); after=api('/character/get',{'charID':local['id']})
            if after.get('backstory')!=profile['backstory'] or after.get('voice_type')!=voice:raise RuntimeError('Profile readback mismatch: '+key)
            if not after.get('memory_settings',{}).get('enabled'):raise RuntimeError('LTM did not enable: '+key)
            if key=='marat' and after.get('character_name')!='Crake':raise RuntimeError('Crake name readback mismatch')
            row.update(memoryEnabled=True,verified=True)
            local.update(name=profile['name'],bio=profile['summary'],backstory=profile['backstory'],
                speakingRules=profile['speakingRules'],sampleDialogue=profile['sampleDialogue'],
                relationships=profile['relationships'],sources=profile['sources'],profileRevision=rich['revision'],
                voice=voice,voiceName=allowed[voice],memoryEnabled=True,cloudAvailable=True)
            write(ROOT/'characters/roster.json',roster)
            (folder/'verified').mkdir(exist_ok=True);write(folder/'verified'/f'{key}.json',after)
        report['profiles'].append(row);write(folder/'profile-update-report.json',report)
        print(('Verified ' if options.apply else 'Planned ')+profile['name']+': '+str(row['words'])+' words; Convai Kokoro; LTM '+str(row['memoryEnabled']),flush=True)
    if options.apply:
        missing=set(report['missing'])
        for p in roster:
            if p['key'] in missing:p['cloudAvailable']=False
        write(ROOT/'characters/roster.json',roster)
        cfg=read(cfgpath);verified={r['key'] for r in report['profiles'] if r['verified']}
        cfg['roster']=[next(p for p in roster if p['key']==old['key']) if old['key'] in verified else old
                       for old in cfg['roster'] if old['key'] not in missing]
        cfg['profileRevision']=rich['revision'];write(cfgpath,cfg)
        release_path=ROOT/'characters/release-config.json'
        release=read(release_path)
        release['profileRevision']=rich['revision']
        write(release_path,release)
    print('Profile pass complete: '+str(len(report['profiles']))+' existing; '+str(len(report['missing']))+' absent. No cloud characters created.',flush=True)

if __name__=='__main__':main()
