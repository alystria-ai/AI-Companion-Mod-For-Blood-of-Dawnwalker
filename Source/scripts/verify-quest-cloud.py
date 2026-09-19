"""Read back the current NPC's cloud memories without exposing credentials."""
import json,pathlib,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
config=json.loads((root/'runtime/convai-config.json').read_text(encoding='utf-8-sig'))
status=json.loads((root/'runtime/quest-cloud-status.json').read_text())
body={'character_id':status['profileId'],'end_user_id':status['userId'],'page':1,'page_size':100}
request=urllib.request.Request('https://api.convai.com/memory/list',data=json.dumps(body).encode(),headers={'CONVAI-API-KEY':config['apiKey'],'Content-Type':'application/json'})
with urllib.request.urlopen(request,timeout=40) as response:data=json.load(response)
(root/'runtime/quest-cloud-readback.json').write_text(json.dumps(data,indent=2))
print(json.dumps(data,indent=2))
