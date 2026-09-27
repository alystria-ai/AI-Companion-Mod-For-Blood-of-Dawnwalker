-- Use the game's overhead dialogue widget on the local player's screen. No
-- desktop window, replacement font, camera math or synthetic dialogue scene.
local M={};local AI=require('ai_state');local Settings=require('companion_settings')
local state;local retryAt=0
local widgetPath='/Game/_Dawnwalker/UI/_Unified/HUD/GameplayDialogue/WBP_GameplayDialogue_OverheadSubtitle.WBP_GameplayDialogue_OverheadSubtitle_C'
local function creatureAnchor(s,point)
 if not s.creature then return end
 local actor=s.actor;local position=actor:K2_GetActorLocation();local now=os.clock()
 if not s.boundsAt or now-s.boundsAt>=.25 then
  s.boundsAt=now
  local top=point.Z-position.Z
  local capsule=actor.CapsuleComponent
  if AI.valid(capsule)then top=math.max(top,capsule:K2_GetComponentLocation().Z+capsule:GetScaledCapsuleHalfHeight()-position.Z)end
  local mesh=actor.Mesh
  if AI.valid(mesh)then
   local origin,extent={},{}
   AI.find('/Script/Engine.Default__KismetSystemLibrary'):GetComponentBounds(mesh,origin,extent,{})
   if type(origin.Z)=='number'and type(extent.Z)=='number'then top=math.max(top,origin.Z+extent.Z-position.Z)end
  end
  s.bodyTop=top;s.headroom=4*math.max(1,actor:GetActorScale3D().Z)
 end
 -- Native head placement falls inside scaled quadrupeds. Keep its horizontal
 -- anchor but lift the caption above the visible body, including ears/horns.
 point.Z=math.max(point.Z,position.Z+s.bodyTop)+s.headroom
end
local function layout(s,pc)
 local now=os.time();if s.layoutAt==now then return end;s.layoutAt=now
 local lib=AI.find('/Script/UMG.Default__WidgetLayoutLibrary')
 local viewport=lib:GetViewportSize(pc);local scale=lib:GetViewportScale(pc)
 if viewport.X<=0 or scale<=0 then return end
 local width=math.min(900,math.floor(viewport.X/scale*.7))
 if s.width==width then return end;s.width=width
 -- Auto-wrap can feed the previous narrow desired size back into viewport
 -- layout. Give the native SizeBox a real width and use explicit text wrapping.
 s.widget.SubtitleLabel:SetAutoWrapText(false)
 s.widget.SubtitleLabel.WrapTextAt=width
 local box=s.widget.SubtitleLabel:GetParent()
 if AI.valid(box)and box:IsA('/Script/UMG.SizeBox')then box:SetWidthOverride(width)end
end
function M.clear()
 if state and AI.valid(state.widget)then pcall(function()state.widget:RemoveFromParent()end)end
 state=nil
end
local function create(pc,actor,generation)
 local hud
 for _,w in ipairs(FindAllOf('WBP_GameplayDialogue_HUD_C')or{})do
  -- The native dialogue child is normally collapsed. A second, unattached
  -- instance reports IsVisible=true but has no geometry and cannot draw.
  if AI.valid(w)and w:GetFullName():find('/Engine/Transient.',1,true)and AI.valid(w:GetParent())and AI.valid(w.OverheadCanvas)then hud=w;break end
 end
 if not hud then return end
 local widget=AI.find('/Script/UMG.Default__WidgetBlueprintLibrary'):Create(pc,AI.find(widgetPath),pc)
 if not AI.valid(widget)then return end
 local player=pc.Pawn
 local stub=AI.find('/Script/RebelAI.Default__RebelAIBlueprintFunctionLibrary'):GetAIStub(player)
 state={widget=widget,hud=hud,actor=actor,player=player,playerStub=stub,generation=generation,world=player:GetWorld()}
 local external=require('addon_api').identity(actor)
 state.creature=external and external.addon=='creature-companion-mounts'
 -- The game's dialogue HUD activates only for a native dialogue event. Convai
 -- has no such event. Add the native subtitle widget to the player's screen
 -- directly instead of changing the game's dialogue/cinematic visibility.
 assert(widget:AddToPlayerScreen(0),'Native caption could not join the player screen')
 widget:SetAlignmentInViewport({X=.5,Y=1})
 widget:SetVisibility(4) -- SelfHitTestInvisible: never captures game controls.
 widget:SetScale(1)
 layout(state,pc)
 return state
end
function M.tick(pc,actor,generation,frame)
 if Settings.values.OverheadSubtitles~=1 or Settings.values.ShowNpcSubtitles~=1 or Settings.values.HideChatBoxes==1
  or not AI.valid(pc)or not AI.valid(pc.Pawn)or not AI.valid(actor)then M.clear();return end
 local gen,stamp=(frame or''):match('^(%d+)\t(%d+)\n')
 local text=(frame or''):match('\nNPC%-TEXT\t([^\r\n]*)')or''
 if tonumber(gen)~=generation or not stamp or math.abs(os.time()-tonumber(stamp))>2 or text==''then M.clear();return end
 if state and(state.generation~=generation or not AI.sameInstance(state.actor,actor)
  or not AI.sameInstance(state.player,pc.Pawn)or not AI.sameInstance(state.world,pc.Pawn:GetWorld())or not AI.valid(state.hud)or not AI.valid(state.widget))then M.clear()end
 local ok,err=pcall(function()
  if not state then
   if os.time()<retryAt then return end
   retryAt=os.time()+2
   if not create(pc,actor,generation)then return end
   retryAt=0 -- Successful speakers do not inherit the failed-widget retry delay.
  end
  local s=state
  layout(s,pc)
  if s.text~=text then
   s.widget.SubtitleLabel:SetText(AI.find('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(text));s.text=text
  end
  -- Reuse native head placement and Unreal's DPI-aware projection.
  local point={};s.hud:GetActorHeadLocation(actor,point)
  creatureAnchor(s,point)
  local screen={};local visible=AI.find('/Script/UMG.Default__WidgetLayoutLibrary'):ProjectWorldLocationToWidgetPosition(pc,point,screen,true)
  if visible and s.creature then screen.Y=screen.Y-4 end -- Small DPI-aware gap below the last text line.
  local paused=AI.find('/Script/Engine.Default__GameplayStatics'):IsGamePaused(pc)
  -- PlayerController.bCinematicMode is not reflected in this game. Reading
  -- it returns truthy TrivialObject userdata, not a boolean. Use the verified
  -- native stub API, as the conversation and camera systems do.
  local cinematic=AI.board(s.playerStub)and s.playerStub:IsInCinematicMode()==true
  if visible and not paused and not cinematic then s.widget:SetPositionInViewport(screen,false);s.widget:SetVisibility(4)
  else s.widget:SetVisibility(1)end
 end)
 if not ok then M.clear();retryAt=os.time()+5;print('[DawnwalkerConvai] Native subtitle unavailable: '..tostring(err)..'\n')end
end
return M
