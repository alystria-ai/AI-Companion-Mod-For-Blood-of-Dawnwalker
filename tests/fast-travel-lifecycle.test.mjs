import fs from 'node:fs';
import test from 'node:test';
import {lua,lauxlib,lualib,to_luastring,to_jsstring} from 'fengari';
test('Fast travel retires closed UI and defers early menu requests',()=>{
const source=fs.readFileSync('mod/Scripts/fast_travel.lua','utf8');
const script=`
local scans,creates=0,0;local now=100;local paused=true;local selected=false;local closed=false;local cancelled=0;local retained={}
local function obj(name)
 return {valid=true,visible=true,GetFullName=function()return name end,IsVisible=function(self)return self.visible end,GetClass=function()return name..'_Class' end}
end
local world=obj('world');world.PersistentLevel=obj('level');local pawn=obj('pawn');pawn.GetWorld=function()return world end
local pc={Pawn=pawn};local board={Combat={}}
local tip=obj('tip');tip.InputBox={visible=1,GetVisibility=function(self)return self.visible end,SetVisibility=function(self,v)self.visible=v end,AddChild=function()end}
tip.FastTravelButton={TriggeringInputAction={}};tip['Pin Instance Id']={Value=0};tip['Setup Fast Travel Button']=function()end
local map=obj('map');map.GetWorld=function()return world end;map.ToolTip=tip
local button
local libs={}
libs['/Script/Engine.Default__GameplayStatics']={IsGamePaused=function()return paused end}
libs['/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary']={GetAIStub=function()return {}end}
libs['/Script/Engine.Default__SubsystemBlueprintLibrary']={GetWorldSubsystem=function()return nil end,GetGameInstanceSubsystem=function()return {valid=true}end}
libs['/Script/DogwoodMap.Default__MappinSystemBlueprintLibrary']={GetMappinInstanceType=function()return 23 end,GetMappinInstanceLocation=function(_,_,id)return {X=id.Value,Y=0,Z=0}end}
libs['/Script/Engine.Default__KismetTextLibrary']={Conv_StringToText=function(_,v)return v end}
libs['/Script/UMG.Default__WidgetBlueprintLibrary']={GetAllWidgetsOfClass=function(_,_,out)scans=scans+1;out[1]=map end,Create=function()
 creates=creates+1;button=obj('button');button.visibility=0
 for _,key in ipairs({'SetTriggeringInputAction','SetHideInputAction','SetShouldSelectUponReceivingFocus','SetIsSelectable','SetIsToggleable','SetIsInteractableWhenSelected','ClearSelection','RemoveFromParent'})do button[key]=function()end end
 button.SetButtonText=function(self,text)assert(not closed,'Arrival accessed closed map button');self.text=text end
 button.SetVisibility=function(self,v)self.visibility=v end;button.GetVisibility=function(self)return self.visibility end
 button.SetIsInteractionEnabled=function(self,v)self.enabled=v end;button.GetSelected=function()return selected end
 return button
end}
local AI={retainUIClass=function(c)retained[c]=true;return c end,valid=function(o)return o and o.valid end,find=function(path)return libs[path]or path end,playerReady=function()return pawn,world end,sameInstance=function(a,b)return a==b end,board=function()return board end}
require=function(name)if name=='runtime_path'then return 'mock'end;return AI end
local m=assert(load(${JSON.stringify(source)}))()
os.time=function()return now end
m.tick(pc,true,250);assert(scans==1 and creates==0 and m.active())
tip['Pin Instance Id'].Value=81;m.tick(pc,true,48)
assert(scans==1 and creates==1 and button.enabled and button.text=='Travel here' and tip.InputBox.visible==0,'New waypoint must show its action without a clock second passing')
for i=1,5 do m.tick(pc,true,48)end;assert(scans==1 and creates==1)
tip['Pin Instance Id'].Value=0;m.tick(pc,true,48);assert(not button.enabled and tip.InputBox.visible==1)
tip['Pin Instance Id'].Value=82;m.tick(pc,true,48);assert(button.enabled and tip.InputBox.visible==0)
m.tick(pc,false,48);assert(not m.active())

-- Exercise actual journey cleanup with its origin widget tree already gone.
local anchor=obj('anchor');local stream=obj('stream');local pos={X=0,Y=0,Z=0}
anchor.IsActorBeingDestroyed=function()return false end;anchor.SetActorHiddenInGame=function()end;anchor.SetActorEnableCollision=function()end
anchor.AddComponentByClass=function()return stream end;anchor.K2_DestroyActor=function()anchor.destroyed=true end
stream.EnableStreamingSource=function()end;stream.DisableStreamingSource=function()end;stream.IsStreamingCompleted=function()return true end
local gameplay=libs['/Script/Engine.Default__GameplayStatics'];gameplay.BeginDeferredActorSpawnFromClass=function()return anchor end;gameplay.FinishSpawningActor=function()return anchor end
pawn.GetTransform=function()return {}end;pawn.K2_GetActorRotation=function()return {}end;pawn.K2_GetActorLocation=function()return pos end
pawn.CapsuleComponent={valid=true,GetScaledCapsuleHalfHeight=function()return 80 end,GetScaledCapsuleRadius=function()return 30 end}
libs['/Script/RebelLoading.Default__AsynAction_RequestLoadingScreen']={RequestLoadingScreen=function()return {valid=true,Activate=function()end,Cancel=function()cancelled=cancelled+1 end}end}
libs['/Script/Engine.Default__KismetSystemLibrary']={LineTraceSingle=function(_,_,a,b,c,d,e,f,hit)hit.Time=.5;hit.Distance=100;hit.PenetrationDepth=0;hit.ImpactNormal={Z=1};hit.ImpactPoint={X=800,Y=100,Z=0};return true end,CapsuleTraceSingle=function()return false end}
libs['/Script/Engine.Default__SubsystemBlueprintLibrary'].GetWorldSubsystem=function(_,pc,class)
 if class=='/Script/DogwoodMap.FastTravelSystem' then return {valid=true,FastTravelToLocation=function(_,p)pos=p;return 2 end}end
end
local widgets=libs['/Script/UMG.Default__WidgetBlueprintLibrary'];local old=widgets.GetAllWidgetsOfClass
widgets.GetAllWidgetsOfClass=function(self,pc,out,class)
 if class=='/Script/DogwoodUI.DWHUBWidgetBase'then out[1]={valid=true,IsVisible=function()return not closed end,RequestCloseHub=function()closed=true;paused=false;tip.valid=false end}
 else old(self,pc,out)end
end
io.open=function()return {write=function()end,close=function()end}end
m.tick(pc,true,250);selected=true;m.tick(pc,true,48);selected=false
assert(closed and not m.active() and not m.uiReady(pc),'Travel left map UI alive or accepted early menu')
now=103;m.tick(pc,true,250);now=104;m.tick(pc,true,250)
assert(cancelled==1 and anchor.destroyed and not m.uiReady(pc),'Arrival cleanup failed')
for i=1,3 do m.tick(pc,true,250);assert(not m.uiReady(pc),'Menu was released before stable player samples')end
m.tick(pc,true,250);assert(m.uiReady(pc),'Queued menu never became ready')
assert(retained['map_Class'] and retained['tip_Class'],'Map Blueprint classes were not retained')
print('Map action cadence, closed tooltip retirement, loading cleanup and early menu gate passed')

`;
const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);const rc=lauxlib.luaL_dostring(L,to_luastring(script));if(rc!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));

});
