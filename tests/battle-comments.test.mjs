import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';

const sources=Object.fromEntries(['battle_comments','loot_comments','reaction_policy'].map(name=>[name,fs.readFileSync(`mod/Scripts/${name}.lua`,'utf8')]));
function run(body){
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const script=`
local now=10000;local game=100;local paused=false;local ready=true;local files={};local errors={}
os.time=function()return now end;math.random=function()return .1 end
print=function(text)errors[#errors+1]=text end
io.open=function(path,mode)
 if mode=='w'then local text='';return {write=function(_,...)for i=1,select('#',...)do text=text..tostring(select(i,...))end end,close=function()files[path]=text end}end
 if path:match('ambient%-ready.tsv$')then return {read=function()return now..'\\t'..(ready and '1'or '0')end,close=function()end}end
 if not files[path]then return end;return {read=function()return files[path]end,close=function()end}
end
local world={};local pawn={GetWorld=function()return world end};local pc={Pawn=pawn};local board={Combat={bInCombat=false}}
local battles={records={}};local inventory={items={}};local stash={items={}}
local function list(self)
 local rows={};for asset,count in pairs(self.items)do local row={ItemDataAsset=asset,Quantity=count};rows[#rows+1]={get=function()return row end}end;return rows
end
inventory.GetCurrentItems=list;stash.GetCurrentItems=list;pawn.GetInventoryComponent=function()return inventory end
local subs={GetPlayerInventoryComponent=function()return inventory end,GetPlayerStorageComponent=function()return stash end}
local cinematic={ActiveGameplayDialogues={},GetActiveDialogue=function()return nil end,IsCurrentlySpeakingInGameplayDialogue=function()return false end}
local libs={
 ['/Script/Engine.Default__KismetSystemLibrary']={GetGameTimeInSeconds=function()return game end},
 ['/Script/Engine.Default__GameplayStatics']={IsGamePaused=function()return paused end},
 ['/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary']={GetAIStub=function()return {}end},
 ['/Script/Engine.Default__SubsystemBlueprintLibrary']={GetWorldSubsystem=function()return cinematic end,GetGameInstanceSubsystem=function()return subs end}
}
local AI={find=function(k)return libs[k]or k end,playerReady=function()return pawn,world end,sameInstance=function(a,b)return a==b end,same=function(a,b)return a==b end,valid=function(v)return type(v)=='table'end,board=function()return board end}
local modules={ai_state=AI,runtime_path='mock',companion_combat={battles=battles}}
require=function(name)assert(modules[name],'Unexpected module '..name);return modules[name]end
modules.reaction_policy=(function()${sources.reaction_policy}end)()
local Policy=modules.reaction_policy
local Loot=(function()${sources.loot_comments}end)()
local Battle=(function()${sources.battle_comments}end)()
local observation,observationContext,observationWaiting
local Ambient={waitingForBattle=function()return observationWaiting end,consumeForBattle=function()local text=observation;observation=nil;return text,observationContext end}
local function step(seconds,busy,speaker,closing)
 now=now+(seconds or 1);game=game+(seconds or 1)
 local line=Battle.tick(pc,true,busy==true,speaker~=false,Loot,closing~=false,Ambient)
 local solo=Loot.tick(pc,true,busy==true or line~=nil,true,Battle.holdLoot())
 assert(#errors==0,table.concat(errors,'; '));return line,solo
end
local function begin(key,kind)
 local r={key=key,kind=kind or 'battle',state='fighting',enemies={one='Brencis',two='Bandit'},witnesses={anca=true},kills=0}
 battles.records[#battles.records+1]=r;board.Combat.bInCombat=true;return r
end
local function ended(r,state)r.state=state or 'combat-ended';board.Combat.bInCombat=false end
local function item(name,rarity,kind)
 return {GetFullName=function()return name end,GetItemName=function()return {ToString=function()return name end}end,ItemRarity=rarity or 1,ItemType=kind or 1}
end
step() -- Baseline the loaded world and inventories.
${body}
`;
 try{const rc=lauxlib.luaL_dostring(L,to_luastring(script));assert.equal(rc,lua.LUA_OK,rc===lua.LUA_OK?'':to_jsstring(lauxlib.luaL_tolstring(L,-1)));}finally{lua.lua_close(L);}
}

test('battle comments form one pair and the ten-minute cooldown starts at its end',()=>run(`
 local first=begin('one');assert(not step());assert(not step())
 local opening=step();assert(opening and opening.phase=='start' and opening.text:find('Brencis',1,true))
 assert(not step(),'Opening repeated while combat remained active')
 -- A long fight must not expire its pair's eligibility.
 assert(not step(650));ended(first);assert(not step())
 local endedAt=now;assert(not step(7))
 local closing=step();assert(closing and closing.phase=='end' and closing.text:find('victory or retreat is not established',1,true))
 assert(not step(),'Closing repeated')
 local second=begin('two');assert(not step(1));assert(not step(3),'Fight inside cooldown opened')
 ended(second);assert(not step(1));assert(not step(10),'Fight inside cooldown closed')
 now=endedAt+600;game=game+600
 local third=begin('three');assert(not step());local nextOpening=step(2);assert(nextOpening and nextOpening.phase=='start','Cooldown did not end ten minutes after the first fight ended')
`));

test('battle ending combines the settled loot batch, excludes storage and prevents a second reply',()=>run(`
 local stored=item('Old Legendary Sword',6,6);stash.items[stored]=1;step()
 local r=begin('loot-fight','horde');step();step(2);ended(r,'cleared');r.kills=3;step()
 local herb=item('Sage');inventory.items[herb]=4;step(2)
 -- Withdrawing a previously stored Legendary item cannot become a discovery.
 stash.items[stored]=nil;inventory.items[stored]=1;step(2)
 local sword=item('New Legendary Sword',6,6);inventory.items[sword]=1;step(2)
 local pending=Loot.pending();assert(pending and pending.top)
 assert(not step(3),'Ending cut into ongoing looting')
 local closing,solo=step(3)
 assert(closing and closing.phase=='end' and not solo)
 assert(closing.text:find('Sage x4',1,true) and closing.text:find('New Legendary Sword',1,true))
 assert(not closing.text:find('Old Legendary Sword',1,true),'Storage withdrawal leaked into reaction')
 assert(closing.text:find('Confirmed enemies defeated in this wave: 3.',1,true))
 assert(not Loot.pending(),'Merged batch was not consumed')
 local more=item('Wolfsbane');inventory.items[more]=2;step(1);local _,again=step(6);assert(not again,'Post-combat looting produced a duplicate reaction')
`));

test('end waits for an idle speaker, but continuous loot cannot postpone it forever',()=>run(`
 local r=begin('busy-end');step();step(2);ended(r);step()
 local herb=item('Herb');inventory.items[herb]=1;step(7,false,true,false)
 assert(not step(1,false,true,false),'End used a fighting companion with no idle speaker')
 assert(Loot.pending(),'Unavailable closing speaker consumed loot')
 for i=1,15 do inventory.items[herb]=i+1;assert(not step(1,false,true,true))end
 inventory.items[herb]=30;local closing=step(2,false,true,true)
 assert(closing and closing.phase=='end','Continuous pickups exceeded the bounded end wait')
`));

test('manual chat, pause, combat flicker and reload do not cause stale or repeated battle comments',()=>run(`
 local r=begin('manual');step();assert(not step(2,true))
 assert(not step(11,true),'Manual chat lost priority')
 assert(not step(),'Late opening should not appear')
 ended(r);step();assert(not step(41,true));assert(not step(),'Expired ending replayed after chat')
 now=now+700;game=game+700
 local live=begin('flicker');step();local open=step(2);assert(open,'Fresh combat opening unavailable')
 board.Combat.bInCombat=false;assert(not step())
 board.Combat.bInCombat=true;assert(not step(),'Brief native combat flag flicker repeated the opening')
 Battle.reset();assert(not step(),'Reload replayed existing battle')
 ended(live);assert(not step());assert(not step(10),'Reload replayed old battle ending')
 step(31) -- Keep the separate automatic-reaction spacing out of this pause check.
 local fresh=begin('paused');paused=true;assert(not step(5),'Paused combat commented');paused=false;assert(not step(),'Paused combat skipped stability wait');local freshOpening=step(2);assert(freshOpening,'Fresh combat after pause did not open')
`));

test('cooldown survives code reload, but loading a save clears all reaction cooldowns',()=>run(`
 local r=begin('short');step();local first=step(2);assert(first)
 ended(r);step();local finish=step(8);assert(finish,'Global 30-second spacing suppressed the paired ending')
 local saved=files['mock/reaction-cooldowns.tsv'];assert(saved and saved:find('battle',1,true))
 local reloaded=(function()${sources.reaction_policy}end)()
 assert(not reloaded.beginBattle('after-reload'),'Reload bypassed battle cooldown')
 reloaded.resetForSaveLoad()
 assert(files['mock/reaction-cooldowns.tsv']=='','Save load retained a reaction cooldown')
 local fresh=(function()${sources.reaction_policy}end)()
 assert(fresh.beginBattle('new-save'),'Previous save suppressed a new battle')
 assert(fresh.takeBattle('new-save','start'),'Previous reaction spacing suppressed the new opening')
 fresh.resetForSaveLoad()
 assert(fresh.take('ambient'),'Save load retained exploration spacing or an active battle pair')
`));

test('a fight already settling cannot announce a late combat opening',()=>run(`
 local r=begin('brief');step();r.quietAt=game;board.Combat.bInCombat=false
 assert(not step(2),'Opening announced after opponents stopped fighting')
 r.quietAt=nil;board.Combat.bInCombat=true
 local line=step();assert(line and line.phase=='start','Resumed stable battle could not open')
`));

test('battle with a full loot batch stays inside the bridge message limit',()=>run(`
 local r=begin('large','horde');r.enemies={};for i=1,30 do r.enemies[i]='Opponent '..i..string.rep('x',38)end
 step();step(2);ended(r,'cleared');r.kills=30;step()
 for i=1,12 do inventory.items[item('Item '..i..string.rep('z',50),6,6)]=1 end
 step();local closing=step(8);assert(closing and #closing.text<=1200,'Merged context exceeds bridge limit: '..tostring(closing and #closing.text))
`));

test('closing waits for Coen then carries his observation and loot in one reply',()=>run(`
 local r=begin('base');step();step(2);ended(r);step()
 inventory.items[item('Sage')]=3;step(2)
 observation='There is a tower we could climb.';observationContext='No exact quest link is established.';observationWaiting=true
 assert(not step(8),'Closing interrupted the observation')
 observationWaiting=false
 local closing,solo=step(2)
 assert(closing and closing.phase=='end'and not solo)
 assert(closing.text:find('tower we could climb',1,true)and closing.text:find('Sage x3',1,true))
 assert(closing.context==observationContext and not observation and not Loot.pending())
 assert(not step(),'Closing repeated')
`));
