import fs from 'node:fs';import test from 'node:test';import fengari from 'fengari';
const{lua,lauxlib,lualib,to_luastring,to_jsstring}=fengari;
test('Player utility guards reject detached and replaced save-load bindings',()=>{
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
const source=String.raw`
local serial=0
local function obj(name)
 serial=serial+1;local o={name=name,address=serial,valid=true}
 function o:IsValid()return self.valid end
 function o:HasAnyFlags()return false end
 function o:GetAddress()return self.address end
 function o:GetFullName()return self.name end
 function o:IsActorBeingDestroyed()return self.destroying or false end
 function o:GetWorld()return self.world end
 return o
end
EObjectFlags={RF_BeginDestroyed=1,RF_FinishDestroyed=2}
local pc,pawn,world,asc,dev=obj('pc'),obj('pawn'),obj('world'),obj('asc'),obj('dev')
pc.Pawn=pawn;pc.world=world;pawn.world=world;pawn.Controller=pc;pawn.RootComponent=obj('root');world.PersistentLevel=obj('level');asc.AvatarActor=pawn
local bound=asc;dev.PlayerASC={Get=function()return bound end}
local libraries={};StaticFindObject=function(path)return libraries[path]end
local function lib(path,values)local o=obj('Class '..path);for k,v in pairs(values)do o[k]=v end;libraries[path]=o end
lib('/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary',{GetAbilitySystemComponent=function()return asc end})
lib('/Script/Engine.Default__SubsystemBlueprintLibrary',{GetGameInstanceSubsystem=function()return dev end})
local now=100;os.time=function()return now end
lib('/Script/Engine.Default__KismetSystemLibrary',{GetGameTimeInSeconds=function()return now end})
lib('/Script/DogwoodCharacterDevelopment.CharacterDevelopmentSubsystem',{})
lib('/Script/DogwoodFocus.FocusAbilityBase',{})
local AI=assert(load(${JSON.stringify(fs.readFileSync('mod/Scripts/ai_state.lua','utf8'))}))()
assert(AI.playerReady(pc)==pawn);assert(AI.playerAbilitySystem(pc)==asc);assert(AI.developmentBound(dev,asc))
pawn.Controller=nil;assert(not AI.playerReady(pc));pawn.Controller=pc
pawn.destroying=true;assert(not AI.playerReady(pc));pawn.destroying=false
local level=world.PersistentLevel;world.PersistentLevel=nil;assert(not AI.playerReady(pc));world.PersistentLevel=level
asc.AvatarActor=obj('old pawn');assert(not AI.playerAbilitySystem(pc));asc.AvatarActor=pawn
bound=nil;assert(not AI.developmentBound(dev,asc));bound=asc
local trait=obj('trait');trait.AlwaysEquippedWithoutSlotCost=false
local ability=obj('ability');function ability:IsA()return true end;function ability:IsAbilityPassive()return true end
trait.CombatFocusAbility=obj('ability class');function trait.CombatFocusAbility:GetCDO()return ability end
asc.ActivatableAbilities={Items={}}
function dev:GetAllTraits()return {trait}end;function dev:GetTraitLevel()return 1 end;function dev:IsTraitEquipped()return false end
local grants,removes=0,0
function dev:SetCombatFocusAbilityActive(t,on)
 assert(bound==asc,'Native setter called with detached PlayerASC')
 if on then grants=grants+1 else removes=removes+1 end
end
local modules={ai_state=AI,UEHelpers={GetPlayerController=function()return pc end}}
require=function(n)return modules[n]end
local m=assert(load(${JSON.stringify(fs.readFileSync('mod/Scripts/player_passives.lua','utf8'))}))()
m.tick(pc,true);assert(grants==1 and trait.AlwaysEquippedWithoutSlotCost)
bound=nil;now=now+3;m.tick(pc,true);assert(grants==1 and removes==0 and not trait.AlwaysEquippedWithoutSlotCost)
bound=asc;now=now+3;m.tick(pc,true);assert(grants==2)
bound=obj('replacement asc');m.cleanup();assert(removes==0 and not trait.AlwaysEquippedWithoutSlotCost)
bound=asc;now=now+3;m.tick(pc,true);m.tick(pc,false);assert(grants==3 and removes==1 and not trait.AlwaysEquippedWithoutSlotCost)
print('Reload guards: possession, destruction, world, avatar, null/replaced skill binding and normal passive disable passed')
`;
const rc=lauxlib.luaL_dostring(L,to_luastring(source));if(rc!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));

});
