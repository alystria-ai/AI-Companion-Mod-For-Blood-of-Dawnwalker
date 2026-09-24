local M={revision=0,respawnDelay=3} -- Automatic quiet period, not a user setting.
M.schema={
 {id='DamagePercent',label='Companion damage',default=250,min=0,max=500,step=10,suffix='%',help='Scales each summoned companion’s normal physical strength, including attacks against NPCs. Special abilities can use separate damage rules.'},
 {id='AttackFrequency',label='Attack frequency',default=180,min=50,max=250,step=10,suffix='%',help='Uses the native attack-speed attribute. Higher values shorten attacks; native AI still chooses when and what to attack. This is not a forced attack timer.'},
 {id='AncaRomance',label='Anca romance profile',group='Conversations',default=0,min=-1,max=1,step=1,romance=true,help='Auto follows romance history in the loaded save. On always uses the romantic conversation profile. Off always uses the normal profile, even after romance is unlocked. This does not change quests or play cutscenes.'},
 {id='LacraRomance',label='Lacra romance profile',group='Conversations',default=0,min=-1,max=1,step=1,romance=true,help='Auto follows romance history in the loaded save. On always uses the romantic conversation profile. Off always uses the normal profile, even after romance is unlocked. This does not change quests or play cutscenes.'},
 {id='FirstPersonCamera',label='First-person camera',group='Camera',default=0,min=0,max=1,step=1,help='Experimental head-height gameplay camera. Dialogue, menus and cutscenes take priority. Turn Off to restore the normal camera.'},
 {id='HordeStartEnemies',label='Starting enemies',group='Horde',default=8,min=1,max=20,step=1,help='Regular enemies in the first horde, in addition to bosses. Changes apply to your next run.'},
 {id='HordeEnemyGrowth',label='Enemies added per level',group='Horde',default=2,min=0,max=4,step=1,help='Adds this many regular enemies with each cleared level.'},
 {id='HordeStartingWave',label='Starting wave',group='Horde',menuOnly=true,cycle=true,default=1,min=1,max=10,step=1,help='Choose the first enemy theme on the Horde page. Later waves are random without repeats.'},
 {id='HordeLevels',label='Horde levels',group='Horde',default=10,min=1,max=10,step=1,help='Number of waves to play. Choose the starting theme on the Horde page; later themes are random without repeats. Enemy counts increase each round.'},
 {id='HordeBosses',label='Bosses per level',group='Horde',default=1,min=0,max=4,step=1,help='Additional bosses per level, chosen from that level’s enemy theme. Story companions are excluded.'},
 {id='HordeTimeout',label='Horde timeout',group='Horde',default=10,min=3,max=60,step=1,suffix=' s',help='Rest between cleared levels. The countdown pauses with the game and yields its subtitle bubble to conversations.'},
}
M.values={};for _,s in ipairs(M.schema)do M.values[s.id]=s.default end
local root=require('runtime_path');local lastRead,lastText=0,nil
local function directory()
 local f=io.open(root..'/mod-directory.txt','r');if not f then return root..'/../mod'end
 local p=f:read('*l');f:close();return p
end
function M.poll()
 if os.time()==lastRead then return end;lastRead=os.time()
 local f=io.open(directory()..'/config.ini','r');if not f then return end
 local text=f:read('*a');f:close();if text==lastText then return end;lastText=text
 local values={};for k,v in text:gmatch('([%w_]+)%s*=%s*([%d%.%-]+)')do values[k]=tonumber(v)end
 for _,s in ipairs(M.schema)do local v=values[s.id];if v and v==v then M.values[s.id]=math.max(s.min,math.min(s.max,s.min+math.floor((v-s.min)/s.step+.5)*s.step))end end
 M.revision=M.revision+1
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
M.bindings={Menu='F5',SingleText='F6',SingleVoice='F7',GroupText='F8',GroupVoice='F9'}
M.bindingSchema={
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
