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
local function definition(id)
 local d=assert(byId['combat_'..id],'Missing horde definition: '..id)
 assert(d.category=='combat'and not storyPaths[d.path],'Story character excluded from hordes: '..id)
 local copy={};for k,v in pairs(d)do copy[k]=v end;copy.hordeEnemy=true
 return copy
end
for _,wave in ipairs(waves)do
 for _,kind in ipairs({'units','bosses'})do for i,id in ipairs(wave[kind])do wave[kind][i]=definition(id)end end
end
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
return M
