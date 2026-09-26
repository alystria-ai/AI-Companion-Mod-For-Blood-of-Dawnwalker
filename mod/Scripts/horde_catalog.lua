-- Authored encounter progression; definitions are looked up in the captured catalogue.
local source=require('companion_config').characters
local byId,storyPaths={},{}
for _,d in ipairs(source)do byId[d.id]=d;if d.category=='story'then storyPaths[d.path]=true end end
local waves={
 {name='Roadside raiders',units={'bandit_basic','bandit_rogue','dog'},bosses={'bandit_basic_boss'}},
 {name='The hungry pack',units={'wolf','brown_wolf','dog'},bosses={'alpha_wolf'}},
 {name='Restless graves',units={'zombie','ancient_zombie','common_undead_age_of_heroes'},bosses={'undead_miniboss'}},
 {name='The armed company',units={'enemy_human','enemy_human_rogue','enemy_human_heavy'},bosses={'soldier_heavy_boss'}},
 {name='Kobold warband',units={'forest_kobold','imp_kobold','forest_kobold'},bosses={'kobold_big_un'}},
 {name='Blood and curses',units={'blood_slave','witch','zombie_ambush'},bosses={'blood_slave_boss'}},
 {name='Uriash assault',units={'uriash','uriash_fast','forest_kobold'},bosses={'uriash_heavy_boss','uriash_fast_boss'}},
 {name='Beasts of the valley',units={'tatzelwurm_small','psoglav','tatzelwurm'},bosses={'beast_of_balaur'}},
 {name='Astral breach',units={'astral_undead','astral_human_heavy','astral_wolf'},bosses={'gargoyle_weak'}},
 {name='The final onslaught',units={'astral_psoglav','ancient_astral_dual_wielder','astral_bear','tatzelwurm_ap'},bosses={'gargoyle'}}
}
-- Boss assets, including alternate boss forms, are authoritative here. Do not
-- use names containing "boss" to accidentally admit ordinary spawn variants.
local nightmare={bosses={}}
local bossPaths={}
for _,d in ipairs(source)do
 if d.category=='combat'and (d.path:find('/Bosses/',1,true)or d.path:lower():find('_boss',1,true)or d.path:lower():find('_miniboss',1,true))and not bossPaths[d.path]then
  nightmare.bosses[#nightmare.bosses+1]=d.id:gsub('^combat_','');bossPaths[d.path]=true
 end
end
-- Additional miniboss assets confirmed in the live asset registry. These are
-- encounter-only definitions, not campaign instances or summonable companions.
local extraBosses={
 {'vidmo_boss1','Vidmo elder I','_MiniBosses/Big_Vidmo/NPCDef_Vidmo_MiniBoss1_sq715'},
 {'vidmo_boss2','Vidmo elder II','_MiniBosses/Big_Vidmo/NPCDef_Vidmo_MiniBoss2_sq715'},
 {'vidmo_boss3','Vidmo elder III','_MiniBosses/Big_Vidmo/NPCDef_Vidmo_MiniBoss3_sq715'},
 {'vidmo_boss4','Vidmo elder IV','_MiniBosses/Big_Vidmo/NPCDef_Vidmo_MiniBoss_sq709'},
 {'bear_miniboss','Bear miniboss','_MiniBosses/q103_Bear_Miniboss/NPCDef_Bear_MiniBoss'}
}
for _,b in ipairs(extraBosses)do
 local asset='/Game/_Dawnwalker/Combat/Enemies/Bosses/'..b[3]
 local path=asset..'.'..b[3]:match('[^/]+$')..'_C'
 byId['combat_'..b[1]]={id='combat_'..b[1],name=b[2],path=path,category='combat',chat=false}
 nightmare.bosses[#nightmare.bosses+1]=b[1];bossPaths[path]=true
end
local function definition(id,allowBoss)
 local d=assert(byId['combat_'..id],'Missing horde definition: '..id)
 assert(d.category=='combat'and (not storyPaths[d.path]or allowBoss and bossPaths[d.path]),'Story character excluded from hordes: '..id)
 local copy={};for k,v in pairs(d)do copy[k]=v end;copy.hordeEnemy=true
 return copy
end
for _,wave in ipairs(waves)do
 for _,kind in ipairs({'units','bosses'})do for i,id in ipairs(wave[kind])do wave[kind][i]=definition(id,false)end end
end
for i,id in ipairs(nightmare.bosses)do nightmare.bosses[i]=definition(id,true)end
local M={waves=waves}
-- Keep wave identity separate from round number. Choose the first theme,
-- then draw without replacement so a run never repeats a cleared theme.
function M.order(first,count,seed)
 first=math.max(1,math.min(#waves,math.floor(first or 1)))
 count=math.max(1,math.min(#waves,math.floor(count or #waves)))
 local pool={};for i=1,#waves do if i~=first then pool[#pool+1]=i end end
 local state=math.floor(seed or os.time())%2147483647;if state==0 then state=1 end
 for i=#pool,2,-1 do state=(state*48271)%2147483647;local j=state%i+1;pool[i],pool[j]=pool[j],pool[i]end
 local order={first};for i=1,count-1 do order[#order+1]=pool[i]end
 return order
end
function M.preview()
 local result={}
 for i,w in ipairs(waves)do
  local names,seen={},{};for _,d in ipairs(w.units)do if not seen[d.id]then names[#names+1]=d.name;seen[d.id]=true end end
  local bosses={};for _,d in ipairs(w.bosses)do bosses[#bosses+1]=d.name end
  result[#result+1]={name=w.name,enemies=table.concat(names,', '),bosses=table.concat(bosses,', '),description=table.concat(names,', ')..' · Boss: '..table.concat(bosses,', ')}
 end
 return result
end
function M.wave(level,regular,bossCount)
 local w=assert(waves[level],'Unknown horde level');local result={}
 for i=1,regular do result[#result+1]=w.units[(i-1)%#w.units+1]end
 for i=1,bossCount do result[#result+1]=w.bosses[(i-1)%#w.bosses+1]end
 return result,w.name
end
-- One shuffled bag per run, retained across rounds. Refill only after every
-- boss has been drawn; avoid a repeat at the boundary of two shuffled bags.
function M.nightmareDraw(draw,count)
 draw=draw or {};local result={}
 for _=1,count do
  if not draw.pool or draw.next>#draw.pool then
   draw.pool={};for i,boss in ipairs(nightmare.bosses)do draw.pool[i]=boss end
   for i=#draw.pool,2,-1 do local j=math.random(i);draw.pool[i],draw.pool[j]=draw.pool[j],draw.pool[i]end
   if #draw.pool>1 and draw.last==draw.pool[1].id then draw.pool[1],draw.pool[2]=draw.pool[2],draw.pool[1]end
   draw.next=1
  end
  local boss=draw.pool[draw.next];draw.next=draw.next+1;draw.last=boss.id;result[#result+1]=boss
 end
 return result,'Nightmare',draw
end
return M
