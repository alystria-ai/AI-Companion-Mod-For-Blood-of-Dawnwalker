local M={revision=0,respawnDelay=3} -- Automatic quiet period, not a user setting.
M.schema={
 {id='FastTravelAnywhere',label='Fast travel from anywhere',group='Player',default=0,min=0,max=1,step=1,help='Travel through the normal map without a roadshrine. Shrines keep their native Fast Travel action; hover other map icons or custom waypoints and press F once for Travel here. The native loading screen covers destination loading. Requires safe standing room; unavailable ground cancels the trip. Outside combat and cutscenes only.'},
 {id='AnytimeAbilities',label='Day and night abilities',group='Player',default=0,min=0,max=1,step=1,help='Allow learned human and vampire active abilities at either time of day. Does not unlock skills, remove their costs or change the world clock. Off restores the native restrictions. Experimental: some movement powers can still require their native form.'},
 {id='SlotlessPassives',label='Passives without slots',group='Player',default=0,min=0,max=1,step=1,help='Activate learned passive skills without assigning ability slots. Does not unlock unlearned skills or change your saved quickslots. Native day/night conditions still apply unless Day and night abilities is On. Off restores normal passive equipment rules.'},
 {id='SkillsAnywhere',label='Spend skill points anywhere',group='Player',default=0,min=0,max=1,step=1,help='Buy skills from the normal Skills page without visiting a roadshrine. Skill-point costs, prerequisites, books, quest locks and time costs remain native. Off restores the normal shrine requirement.'},
 {id='AutoLoot',label='Auto-loot nearby items',group='Player',default=0,min=0,max=1,step=1,help='Collect freely available loot, herbs and resources within 3.5 metres, only outside combat after a two-second quiet period. Skips locked or stealable items and items behind walls. Uses normal inventory rules; full bags are retried later.'},
 {id='FollowerCloseness',label='Follower closeness',group='Following',default=100,min=50,max=150,step=5,suffix='%',help='Higher values bring the rear formation closer to Coen; lower values leave more room behind him. Minimum body clearance is preserved. Applies on the next real follow, so changing it does not shuffle companions while you approach them.'},
 {id='PartySpacing',label='Party spacing',group='Following',default=100,min=75,max=175,step=5,suffix='%',help='Lower values make the formation tighter; higher values spread companions out. Character size sets a safe minimum to prevent overlapping seats. Applies on the next real follow. Both following controls default to 100%.'},
 {id='NarrowFormation',label='Narrow formation',group='Following',default=0,min=0,max=1,step=1,help='Prefers a narrower group behind Coen, with more companions arranged front-to-back so they are easier to keep in view together. Larger parties gain extra columns to avoid a long single-file tail. Still respects closeness, spacing and body clearance. Off keeps the rear fan. Applies on the next real follow; camera turns do not reshuffle the party.'},
 {id='DamagePercent',label='Companion damage',default=250,min=0,max=500,step=10,suffix='%',help='Scales each summoned companion’s normal physical strength, including attacks against NPCs. Special abilities can use separate damage rules.'},
 {id='AttackFrequency',label='Attack frequency',default=180,min=50,max=250,step=10,suffix='%',help='Uses the native attack-speed attribute. Higher values shorten attacks; native AI still chooses when and what to attack. This is not a forced attack timer.'},
 {id='AncaRomance',label='Anca romance profile',group='Conversations',default=0,min=-1,max=1,step=1,romance=true,help='Auto follows romance history in the loaded save. On always uses the romantic conversation profile. Off always uses the normal profile, even after romance is unlocked. This does not change quests or play cutscenes.'},
 {id='LacraRomance',label='Lacra romance profile',group='Conversations',default=0,min=-1,max=1,step=1,romance=true,help='Auto follows romance history in the loaded save. On always uses the romantic conversation profile. Off always uses the normal profile, even after romance is unlocked. This does not change quests or play cutscenes.'},
 {id='LootComments',label='React to collected loot',group='Conversations',default=1,min=0,max=1,step=1,help='One random nearby companion may comment after you finish collecting a batch of items. Ordinary loot has a 20% chance and at least ten minutes between comments. Newly acquired Unique-tier weapons or clothing bypass that chance, with a two-minute special-item cooldown. Storage withdrawals stay silent. Requires the conversation Runtime.'},
 {id='AmbientComments',label='React to Coen’s observations',group='Conversations',default=1,min=0,max=1,step=1,help='A nearby talking companion can briefly respond after Coen finishes a spoken exploration observation. Uses the actual solo game line, without a random roll and with at least three minutes between reactions. Excludes conversations with other characters and stays quiet during combat, cutscenes and manual chat. Requires the conversation Runtime.'},
 {id='FollowUpQuestions',label='Follow-up questions',group='Conversations',default=1,min=0,max=1,step=1,help='Companions normally end with one natural, relevant question, skipping it when there is a clear reason to stop or avoid asking. Only the final group speaker asks Coen. Off removes this encouragement. Applies to new replies; it does not turn on your microphone automatically.'},
 {id='TransparentChatHud',label='Transparent chat HUD',group='Conversations',default=1,min=0,max=1,step=1,help='Makes subtitles, voice status and the typing field transparent. Subtitle and status text keep a dark outline for readability. Turn Off to restore the shaded panel.'},
 {id='HideChatBoxes',label='Hide chat boxes',group='Conversations',default=0,min=0,max=1,step=1,help='On keeps only the microphone indicator during voice input and hides all conversation text, including NPC subtitles. Text entry still opens with your text shortcut, then disappears after sending. Horde countdowns are unaffected.'},
 {id='ShowNpcSubtitles',label='NPC subtitles',group='Conversations',default=1,min=0,max=1,step=1,help='Shows subtitles for spoken NPC replies. Turn Off to hear replies without reading them while retaining the normal voice-input HUD. Hide chat boxes overrides this setting. This affects mod conversations only.'},
 {id='ChatHudBottomOffset',label='Chat HUD bottom offset',group='Conversations',default=0,min=0,max=40,step=1,suffix='%',help='Extra height above the original HUD position. Zero keeps the current placement; higher values move text input, NPC subtitles, voice indicators and Horde countdowns upward together, by a percentage of screen height. Tall content stays inside the screen. Applies live.'},
 {id='FirstPersonCamera',label='First-person camera',group='Camera',default=0,min=0,max=1,step=1,help='Experimental head-height gameplay camera. Native dialogue and cutscenes take priority. The mod camera is retained through the companion menu. Turn Off to restore the normal camera.'},
 {id='FirstPersonFOV',label='First-person field of view',group='Camera',default=90,min=60,max=120,step=5,suffix='°',help='Horizontal field of view for the mod camera. Higher values show more surroundings. Applies live in first person; normal gameplay and cinematic cameras are unchanged.'},
 {id='FirstPersonHeight',label='Camera height offset',group='Camera',default=0,min=-20,max=20,step=2,suffix=' cm',help='Moves the first-person camera above or below Coen’s native eye height. Crouching still follows the game’s eye height. Applies live.'},
 {id='FirstPersonForward',label='Camera forward offset',group='Camera',default=42,min=20,max=70,step=2,suffix=' cm',help='Moves the first-person viewpoint forward from Coen’s capsule. Lower values stay nearer his head; higher values move it further forward. Applies live.'},
 {id='GazeHorizontal',label='Companion gaze horizontal',group='Camera',default=5,min=-20,max=20,step=1,suffix=' cm',help='Offsets the point companions look at in first person. Positive values aim toward your right; negative values aim toward your left. Zero targets the camera centre. Default: 5 cm right. Applies live without moving your camera.'},
 {id='GazeVertical',label='Companion gaze vertical',group='Camera',default=-1,min=-20,max=20,step=1,suffix=' cm',help='Offsets the point companions look at in first person. Positive values aim up; negative values aim down, relative to your view. Zero targets the camera centre. Default: 1 cm down. Applies live without moving your camera.'},
 {id='HordeStartEnemies',label='Starting enemies',group='Horde',default=8,min=1,max=20,step=1,help='Regular enemies in the first Horde wave, in addition to bosses. In Nightmare, both counts become bosses fighting together per round. Changes apply to your next run.'},
 {id='HordeEnemyGrowth',label='Enemies added per level',group='Horde',default=2,min=0,max=4,step=1,help='Adds this many enemies with each cleared level, or extra bosses per Nightmare round.'},
 {id='HordeStartingWave',label='Starting wave',group='Horde',menuOnly=true,cycle=true,default=1,min=1,max=10,step=1,help='Choose the first enemy theme on the Horde page. Later waves are random without repeats.'},
 {id='HordeLevels',label='Horde levels',group='Horde',default=10,min=1,max=10,step=1,help='Number of Horde waves or Nightmare rounds. Normal Horde themes are random without repeats; Nightmare draws a full group of bosses from its separate pool.'},
 {id='HordeBosses',label='Bosses per level',group='Horde',default=1,min=0,max=4,step=1,help='Additional bosses per level, chosen from that level’s enemy theme. Nightmare adds this number to its boss count per round.'},
 {id='HordeTimeout',label='Horde timeout',group='Horde',default=10,min=3,max=60,step=1,suffix=' s',help='Rest between cleared levels. The countdown pauses with the game and yields its subtitle bubble to conversations.'},
}
M.values={};for _,s in ipairs(M.schema)do M.values[s.id]=s.default end
local root=require('runtime_path');local lastRead,lastText=0,nil
local function directory()
 local f=io.open(root..'/mod-directory.txt','r');if not f then return root..'/../mod'end
 local p=f:read('*l');f:close();return p
end
function M.poll(force)
 if not force and os.time()==lastRead then return end;lastRead=os.time()
 local path=directory()..'/config.ini';local f=io.open(path,'r')
 local text=f and f:read('*a')or '';if f then f:close()end
 if text==lastText then return end
 local repaired,values=M.repairConfig(text)
 if repaired~=text then
  -- Native choice controls require exactly one assignment even for new defaults.
  f=io.open(path,'w');if not f then lastText=nil;return end
  f:write(repaired);f:close();text=repaired
 end
 lastText=text
 if values.HideChatBoxes==nil and values.ShowConversationText~=nil then values.HideChatBoxes=1-values.ShowConversationText end
 for _,s in ipairs(M.schema)do local v=values[s.id];if v and v==v then M.values[s.id]=math.max(s.min,math.min(s.max,s.min+math.floor((v-s.min)/s.step+.5)*s.step))end end
 M.revision=M.revision+1
end
function M.repairConfig(text)
 local original=text;text=text:gsub('^\239\187\191','')
 local schema,seen,values={},{},{};for _,s in ipairs(M.schema)do schema[s.id]=s end
 local rows={};local section;local found=false;local changed=text~=original
 for line in (text..'\n'):gmatch('(.-)\r?\n')do
  local heading=line:match('^%s*%[([^%]]+)%]');if heading then section=heading;if section=='Companions'then found=true end end
  local id,raw=line:match('^%s*([%w_]+)%s*=%s*([^;#]*)')
  if section=='Companions'and schema[id]then
   local s=schema[id]
   if seen[id]then changed=true
   else
    seen[id]=true;local n=tonumber(raw);local v=n and n==n and math.abs(n)~=math.huge and n or s.default
    v=math.max(s.min,math.min(s.max,s.min+math.floor((v-s.min)/s.step+.5)*s.step));values[id]=v
    if n~=v then line=id..' = '..v;changed=true end
    rows[#rows+1]=line
   end
  else rows[#rows+1]=line end
 end
 local missing={};for _,s in ipairs(M.schema)do if not seen[s.id]then missing[#missing+1]=s.id..' = '..s.default;values[s.id]=s.default end end
 if #missing>0 then
  changed=true
  -- Insert into the first Companions section, never beneath an unrelated one.
  local at=#rows+1
  if found then for i,line in ipairs(rows)do if line:match('^%s*%[Companions%]')then at=i+1;break end end
  else rows[#rows+1]='[Companions]';at=#rows+1 end
  for i=#missing,1,-1 do table.insert(rows,at,missing[i])end
 end
 return changed and table.concat(rows,'\n')or text,values
end
local romanceStory={}
function M.setRomanceStory(anca,lacra)
 romanceStory={AncaRomance=anca==true,LacraRomance=lacra==true}
end
function M.effective(id)
 if id=='AncaRomance'or id=='LacraRomance'then
  local value=M.values[id]
  return (value==1 or value==0 and romanceStory[id])and 1 or 0
 end
 return M.values[id]
end
function M.change(id,delta)
 for _,s in ipairs(M.schema)do if s.id==id then
  if s.romance then M.values[id]=((M.values[id]+1+(delta or 1))%3)-1
  elseif s.cycle then M.values[id]=s.min+(M.values[id]-s.min+(delta or 1)*s.step)%(s.max-s.min+s.step)
  else M.values[id]=(s.min==0 and s.max==1)and (1-M.values[id])or math.max(s.min,math.min(s.max,M.values[id]+delta*s.step))end
  local f=assert(io.open(directory()..'/config.ini','w'));f:write('[Companions]\n')
  for _,item in ipairs(M.schema)do f:write(item.id..' = '..M.values[item.id]..'\n')end
  f:close();lastText=nil;lastRead=0;M.poll();return
 end end
end
function M.label(s)if s.romance then return M.values[s.id]==0 and 'Auto'or M.values[s.id]==1 and 'On'or 'Off'end;local v=M.effective(s.id);return (s.min==0 and s.max==1)and (v==1 and 'On'or 'Off')or tostring(v)..(s.suffix or '')end
-- These bindings are shared with the desktop input helper. Keep one file for
-- both editors; gameplay settings must never overwrite keyboard preferences.
M.bindings={Camera='F4',Menu='F5',SingleText='F6',SingleVoice='F7',GroupText='F8',GroupVoice='F9'}
M.bindingSchema={
 {id='Camera',label='First / third person'},
 {id='Menu',label='Companion menu'}, {id='SingleText',label='Single text chat'},
 {id='SingleVoice',label='Single voice chat'}, {id='GroupText',label='Group text chat'},
 {id='GroupVoice',label='Group voice chat'}
}
local bindingText=nil
function M.validKey(key)
 return type(key)=='string'and (key:match('^[A-Z0-9]$')~=nil or
  key:match('^F[1-9]$')~=nil or key:match('^F1[01]$')~=nil or
  key=='Home'or key=='End'or key=='PageUp'or key=='PageDown'or key=='Insert'or key=='Delete')
end
function M.pollBindings()
 local f=io.open(directory()..'/keybindings.ini','r');if not f then return end
 local source=f:read('*a');f:close();if source==bindingText then return end;bindingText=source
 local candidate,seen={},{}
 for line in source:gmatch('[^\r\n]+')do
  local id,key=line:match('^%s*([%w]+)%s*=%s*([%w]+)%s*$')
  if id and M.bindings[id]then candidate[id]=key end
 end
 for _,s in ipairs(M.bindingSchema)do
  local key=candidate[s.id]
  if s.id=='Camera'and key==nil then
   for _,fallback in ipairs({'F4','F10','F11','F3','F2','F1'})do
    local used=false;for _,bound in pairs(candidate)do if bound==fallback then used=true end end
    if not used then key=fallback;candidate[s.id]=key;break end
   end
  end
  if not M.validKey(key)or seen[key]then M.bindingError='Invalid or duplicate binding in keybindings.ini. Keeping the previous bindings.';return end
  seen[key]=true
 end
 M.bindings=candidate;M.bindingError=nil;return true
end
function M.bind(id,key)
 if not M.bindings[id]or not M.validKey(key)then return false,'Use F1–F11, A–Z, 0–9, Home, End, PageUp, PageDown, Insert or Delete.'end
 for other,value in pairs(M.bindings)do if other~=id and value==key then return false,key..' is already assigned to another action.'end end
 local f,err=io.open(directory()..'/keybindings.ini','w');if not f then return false,tostring(err)end
 f:write('; Edit while the menu is closed, or use Controls in the companion menu.\n[Keybindings]\n')
 for _,s in ipairs(M.bindingSchema)do f:write(s.id..' = '..(s.id==id and key or M.bindings[s.id])..'\n')end
 f:close();bindingText=nil;M.pollBindings();return true
end
return M
