-- Own native UMG layout; artwork and typeface come from the installed menu theme.
local AI=require('ai_state');local Input=require('ui_input');local Party=require('companions');local Settings=require('companion_settings')
local root=require('runtime_path');local M={};local view=nil;local Theme=nil;local serial=0
local function cls(path)return assert(AI.find(path),path)end
local function text(w,value)
 local cache=view and view.textCache
 if cache and cache[w]==value then return end
 w:SetText(cls('/Script/Engine.Default__KismetTextLibrary'):Conv_StringToText(value))
 if cache then cache[w]=value end
end
local function new(kind)return StaticConstructObject(cls('/Script/UMG.'..kind),view.tree)end
local function add(panel,w)return panel:AddChild(w)end
local function fill(slot)slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0);return slot end
local function size(w,x,y)local box=new('SizeBox');if x then box:SetWidthOverride(x)end;if y then box:SetHeightOverride(y)end;box:SetContent(w);return box end
local function art(name)return Theme.image(view.tree,view.theme,name,{construct=function(path,tree)return StaticConstructObject(cls(path),tree)end})end
local function caption(value,points)
 local w=new('TextBlock');text(w,value);w:SetAutoWrapText(true);w:SetVisibility(3)
 Theme.font(w,view.theme,points or 26);Theme.textColor(w,'body');return w
end
local function describe(title,body)
 if not view then return end;text(view.detailTitle,title);text(view.detailBody,body)
end
local function retireButtons(v)
 for _,b in ipairs(v.buttons or {})do if AI.valid(b.click)then
  b.click:ClearSelection();b.click:SetTriggeringInputAction(v.emptyAction);b.click:SetIsInteractionEnabled(false);b.click:SetIsEnabled(false)
 end end
end
local function enabled(b,on)
 if b.enabled==on then return end
 b.enabled=on;b.widget:SetIsEnabled(on);b.widget:SetRenderOpacity(on and 1 or .4)
 if b.click then b.click:SetIsInteractionEnabled(on);b.click:SetIsEnabled(on);if not on then b.click:ClearSelection()end end
end
local function clickLayer(overlay,paint)
 local click=view.library:Create(view.pc,view.clickClass,view.pc)
 click:SetIsFocusable(false);click:SetShouldSelectUponReceivingFocus(false);click:SetIsSelectable(true)
 click:SetIsToggleable(false);click:SetIsInteractableWhenSelected(true);click:ClearSelection()
 click:SetTriggeringInputAction(view.emptyAction);click:SetRenderOpacity(0);click:SetIsInteractionEnabled(true)
 -- The transparent native button must remain hit-testable to retain clicks.
 fill(add(overlay,click));paint:SetVisibility(3);return click
end
local function button(panel,label,fn,width,help)
 local b=new('Button');b.IsFocusable=false;local c=caption(label,26)
 b:SetContent(c);Theme.button(b,c,view.theme,false)
 -- The dependency's default button font is deliberately small; our design is 1920x1080.
 Theme.font(c,view.theme,26);c:SetJustification(0)
 c.Slot:SetHorizontalAlignment(0);c.Slot:SetVerticalAlignment(2);c.Slot:SetPadding({Left=24,Top=4,Right=18,Bottom=4})
 local overlay=new('Overlay');fill(add(overlay,b))
 local click=clickLayer(overlay,b)
 add(panel,size(overlay,width or 770,52)):SetPadding({Left=0,Top=2,Right=8,Bottom=2})
 local item={widget=b,click=click,label=c,action=fn,title=label,help=help,enabled=true};view.buttons[#view.buttons+1]=item;return item
end
local function dependency()
 if Theme then return end
 local f=assert(io.open(root..'/mod-directory.txt','r'),'Native menu install path missing');local dir=f:read('*l');f:close()
 Theme=assert(loadfile(dir..'/../DawnwalkerModMenu/Scripts/theme.lua'),'Install Dawnwalker Mod Menu 1.0.6.2 or later')()
end
local function marker(value)local f=io.open(root..'/native-menu-open.txt','w');if f then f:write(value);f:close()end end
function M.isOpen()return view~=nil end
function M.close()
 local old=view;view=nil;if not old then return end
 retireButtons(old)
 if AI.valid(old.backClick)then old.backClick:ClearSelection();old.backClick:SetIsInteractionEnabled(false);old.backClick:SetIsEnabled(false)end
 if AI.valid(old.host)then pcall(function()old.host:DeactivateWidget();old.host:RemoveFromParent()end)end
 Input.release(old.lease)
 if AI.valid(old.parent)then pcall(function()
  old.parent.bIsBackHandler=old.parentBack;old.parent:SetIsEnabled(old.parentEnabled)
  old.library:SetInputMode_GameAndUIEx(old.pc,old.parent,0,false,true);old.parent:SetUserFocus(old.pc)
 end)end
 marker('0')
end
-- Pure batch reduction: completion belongs to the request returned by this menu,
-- not whichever companion happens to finish first. Values are loading stages.
function M.batch(requests,state)
 local byId,actors={},{};for _,r in ipairs(state.summons or {})do byId[r.id]=r end
 for _,m in ipairs(state.members or {})do actors[m.id]=m end
 local stages={queued=0,character=1,body=2,ai=3,reactions=3.5,spawning=4,ready=5,failed=5}
 local result={ready=0,pending=0,failed=0,progress=0,lines={}}
 for _,r in ipairs(requests)do
  if not r.terminal then
   local status=byId[r.id];local actor=actors[r.id]
   if status and status.phase=='failed'then r.phase='failed';r.message=status.message;r.terminal=true
   elseif actor and not actor.loading then r.phase='ready';r.message='Ready';r.terminal=true
   elseif status and status.phase=='ready'then r.phase='spawning';r.message='Waiting for companion to arrive'
   elseif status then r.phase=status.phase;r.message=status.message end
  end
  local phase=r.phase or 'queued'
  if phase=='ready'then result.ready=result.ready+1
  elseif phase=='failed'then result.failed=result.failed+1
  else result.pending=result.pending+1 end
  result.progress=result.progress+(stages[phase]or 0)
  if phase~='ready'and #result.lines<3 then result.lines[#result.lines+1]=r.name..' · '..(r.message or 'Queued')end
 end
 result.progress=#requests>0 and result.progress/(#requests*5)or 0
 result.total=#requests;return result
end
local function latestCopy(v,state)
 local selected=v.selection;if not selected then return end
 for i=#(state.pending or {}),1,-1 do local m=state.pending[i];if m.characterId==selected.id and not v.dismissing[m.id]then return m end end
 for i=#state.members,1,-1 do local m=state.members[i];if m.characterId==selected.id and not v.dismissing[m.id]then return m end end
end
local function showSelection(v)
 if v.selection then describe(v.selection.name,v.selection.help)else describe('Choose your companions','Select a character on the left, then choose Summon. Dismiss removes the newest copy of that character. Use Party to choose a specific copy.')end
 for _,b in ipairs(v.buttons)do if b.characterId then b.active=v.selection and b.characterId==v.selection.id or false end end
end
local function refresh(v,state)
 local loading=state.queued or 0;for _,m in ipairs(state.members)do if m.loading then loading=loading+1 end end
 text(v.summary,#state.members..' in party · '..loading..' loading')
 if v.page~='Summon'then if v.feedback then text(v.feedback,v.message or '')end;return end
 enabled(v.summonButton,v.selection~=nil);enabled(v.dismissButton,latestCopy(v,state)~=nil)
 local batch=M.batch(v.requests,state)
 local count=0;if v.selection then
  for _,m in ipairs(state.members)do if m.characterId==v.selection.id then count=count+1 end end
  for _,m in ipairs(state.pending or {})do if m.characterId==v.selection.id then count=count+1 end end
 end
 text(v.copyCount,v.selection and (count..' summoned or queued · Dismiss removes the newest copy')or '')
 if v.progressValue~=batch.progress then v.progressValue=batch.progress;v.progress:SetPercent(batch.progress)end
 text(v.progressTitle,batch.total>0 and (batch.ready..' / '..batch.total..' ready'..(batch.pending>0 and ' · '..batch.pending..' loading'or '')..(batch.failed>0 and ' · '..batch.failed..' failed'or ''))or 'Ready to summon')
 local lines=table.concat(batch.lines,'\n');if batch.pending>3 then lines=lines..'\n+'..(batch.pending-3)..' more loading'end
 text(v.feedback,(v.message~=''and (v.message..(lines~=''and '\n'or ''))or '')..lines)
 text(v.queueHint,(state.note or ''):match('^Paused')and 'Unpause the game to continue loading. You can still select and summon other characters while you wait.'or 'You can select and summon other characters while these load. Repeated Summon clicks queue additional copies.')
 if batch.total>0 and batch.pending==0 and batch.failed==0 then v.readyAt=v.readyAt or os.time()else v.readyAt=nil end
end
local function bindingLabels(v)
 for _,b in ipairs(v.buttons)do if b.binding then
  text(b.label,b.binding.label..'     '..(v.capture==b.binding.id and '[ Press a key… ]'or Settings.bindings[b.binding.id]))
 end end
end
local render
local function page(name)view.page=name;view.capture=nil;view.focus=1;view.dirty=true;view.touched=os.time();view.autoClose=nil end
local function back()
 if view.capture then view.capture=nil;view.message='Binding unchanged';bindingLabels(view)
 elseif view.page~='Summon'then page('Summon')else M.close()end
end
local function changeSetting(s,delta)
 Settings.change(s.id,delta)
 for _,b in ipairs(view.buttons)do if b.setting==s then text(b.value,Settings.label(s))end end
 for _,slider in ipairs(view.sliders)do if slider.setting==s then
  slider.value=Settings.values[s.id];slider.widget:SetValue(slider.value)
 end end
end
render=function()
 local v=view;retireButtons(v);v.content:ClearChildren();v.textCache={};v.progressValue=nil;v.buttons={};v.sliders={};v.dirty=false;v.hover=nil;v.feedback=nil
 local tabs=new('HorizontalBox');add(v.content,tabs)
 for _,name in ipairs({'Summon','Party','Settings','Controls','Help'})do local item=button(tabs,name,function()page(name)end,300);item.active=v.page==name end
 add(v.content,size(art('horizontal'),1580,3)):SetPadding({Left=0,Top=14,Right=0,Bottom=24})
 local columns=new('HorizontalBox');add(v.content,columns)
 local left=new('VerticalBox');add(columns,size(left,790,710))
 add(columns,size(art('vertical'),24,710)):SetPadding({Left=18,Top=0,Right=26,Bottom=0})
 local detailScroll=new('ScrollBox');Theme.scroll(detailScroll,v.theme);add(columns,size(detailScroll,710,710)):SetPadding({Left=20,Top=4,Right=0,Bottom=0})
 local detail=new('VerticalBox');add(detailScroll,detail)
 v.detailTitle=caption('',32);add(detail,v.page=='Summon'and size(v.detailTitle,670,82)or v.detailTitle)
 v.detailBody=caption('',24);add(detail,v.page=='Summon'and size(v.detailBody,670,160)or v.detailBody):SetPadding({Left=0,Top=12,Right=8,Bottom=0})
 local model=Party.view();local list=new('ScrollBox');Theme.scroll(list,v.theme);v.list=list
 if not v.trackingInitialized then
  v.trackingInitialized=true;local names={};for _,c in ipairs(model.characters)do names[c.id]=c.name end
  for _,m in ipairs(model.members)do if m.loading then v.requests[#v.requests+1]={id=m.id,name=m.name,phase='queued'}end end
  for _,m in ipairs(model.pending or {})do v.requests[#v.requests+1]={id=m.id,name=names[m.characterId]or m.characterId,phase='queued'}end
 end
 if v.page=='Summon'then
  local groups=new('HorizontalBox');add(left,groups)
  for _,category in ipairs({'story','combat'})do
   local item=button(groups,category=='story'and 'Characters'or 'Creatures & combatants',function()v.category=category;v.selection=nil;v.focus=6;v.dirty=true;v.touched=os.time()end,category=='story'and 300 or 470)
   item.label:SetAutoWrapText(false);item.active=category==(v.category or 'story')
  end
  add(left,size(list,790,632)):SetPadding({Left=0,Top=14,Right=0,Bottom=0})
  for _,c in ipairs(model.characters)do if c.category==(v.category or 'story')then
   local choice={id=c.id,name=c.id=='marat'and 'Crake'or c.id=='matriarch'and 'Bakr-Erga'or c.name,
    help=c.chat==false and 'Combat-only companion. Follows and fights using native abilities. Cannot join conversations. Large creatures need open terrain.'or 'Talk through text or voice, alone or in a group. Follows and fights using native abilities. Copies share this character’s conversation history.'}
   local item=button(list,choice.name,function()v.selection=choice;v.message='';showSelection(v);refresh(v,Party.view())end)
   item.characterId=choice.id
  end end
  local actions=new('HorizontalBox');add(detail,actions):SetPadding({Left=0,Top=12,Right=0,Bottom=8})
  v.summonButton=button(actions,'Summon',function()
   if not v.selection then return end
   local ok,id=pcall(Party.enqueue,'spawn',v.selection.id)
   if ok then v.requests[#v.requests+1]={id=id,name=v.selection.name,phase='queued',message='Waiting to begin loading'};v.readyAt=nil;v.autoCloseQueued=true;v.message=''
   else v.message=tostring(id)end
   refresh(v,Party.view())
  end,310);v.summonButton.prominent=true
  v.dismissButton=button(actions,'Dismiss',function()
   local target=latestCopy(v,Party.view());if not target then return end
   local ok,why=pcall(Party.enqueue,'dismiss',target.id)
   if ok then v.dismissing[target.id]=true;v.message='Dismissal queued'else v.message=tostring(why)end
   refresh(v,Party.view())
  end,310);v.dismissButton.prominent=true
  v.copyCount=caption('',21);add(detail,size(v.copyCount,670,48))
  v.progressTitle=caption('',24);add(detail,size(v.progressTitle,670,38)):SetPadding({Left=0,Top=8,Right=0,Bottom=0})
  v.progress=new('ProgressBar');v.progress:SetVisibility(3);v.progress:SetFillColorAndOpacity({R=.7,G=.48,B=.17,A=1})
  v.progress.WidgetStyle.BackgroundImage.DrawAs=3;v.progress.WidgetStyle.BackgroundImage.TintColor.SpecifiedColor={R=.035,G=.028,B=.018,A=1}
  v.progress.WidgetStyle.FillImage.DrawAs=3;v.progress.WidgetStyle.FillImage.TintColor.SpecifiedColor={R=1,G=1,B=1,A=1}
  add(detail,size(v.progress,640,10)):SetPadding({Left=0,Top=8,Right=0,Bottom=14})
  local feedbackScroll=new('ScrollBox');Theme.scroll(feedbackScroll,v.theme)
  v.feedback=caption('',21);add(feedbackScroll,v.feedback);add(detail,size(feedbackScroll,670,120))
  v.queueHint=caption('',22);add(detail,v.queueHint):SetPadding({Left=0,Top=12,Right=0,Bottom=0})
  showSelection(v)
 elseif v.page=='Party'then
  add(left,size(list,790,710));describe('Your travelling party','Select a companion to dismiss that copy. Fallen companions return automatically after combat. Health bars stay hidden.')
  for _,m in ipairs(model.members)do local id=m.id;local item=button(list,m.name..' · '..m.status,function()Party.enqueue('dismiss',id);v.message='Dismissal queued';v.refreshAt=0 end,nil,'Dismiss this copy from your party.');item.memberId=id end
  if #model.members>0 then button(list,'Dismiss everyone',function()Party.enqueue('dismiss_all');v.refreshAt=0 end)else add(list,caption('No companions summoned yet.'))end
 elseif v.page=='Settings'then
  add(left,size(list,790,710));describe('Companion combat','Adjust damage and attack frequency. Changes save immediately. Native AI chooses attacks and powers. Fallen companions revive automatically once combat ends.')
  for _,s in ipairs(Settings.schema)do
   local item=button(list,s.label,function()changeSetting(s,1)end,nil,s.help);item.setting=s
   local row=new('HorizontalBox');item.widget:SetContent(row)
   -- Button content otherwise defaults to centering its desired width. Toggle
   -- rows are narrower than slider rows, so that default indented their labels.
   fill(row.Slot):SetPadding({Left=24,Top=0,Right=18,Bottom=0})
   local label=caption(s.label,26);label:SetAutoWrapText(false)
   local labelBox=size(label,410,52);label.Slot:SetVerticalAlignment(2);add(row,labelBox)
   local control
   if s.max~=1 then
    item.click:SetVisibility(1);item.click:SetIsInteractionEnabled(false);item.widget:SetVisibility(0)
    local slider=new('Slider');slider:SetMinValue(s.min);slider:SetMaxValue(s.max);slider:SetStepSize(s.step);slider:SetValue(Settings.values[s.id]);Theme.slider(slider,v.theme)
    control=slider
    v.sliders[#v.sliders+1]={widget=slider,setting=s,value=Settings.values[s.id],item=item}
   else control=new('Spacer')end
   add(row,size(control,185,52)):SetPadding({Left=0,Top=0,Right=12,Bottom=0})
   local value=caption(Settings.label(s),26);value:SetAutoWrapText(false)
   local valueBox=size(value,100,52);value.Slot:SetVerticalAlignment(2)
   add(row,valueBox):SetPadding({Left=10,Top=0,Right=0,Bottom=0});item.value=value
  end
 elseif v.page=='Controls'then
  add(left,size(list,790,710));describe('Keyboard controls','Select an action, then press its new key. Changes save immediately to keybindings.ini.\n\nUse F1–F11, letters, numbers, Home, End, PageUp, PageDown, Insert or Delete. Each action needs a different key. Escape cancels capture.\n\nChoose keys that do not conflict with your game controls. Voice keys toggle recording: press once to speak, and again to finish.')
  for _,s in ipairs(Settings.bindingSchema)do local id=s.id
   local item=button(list,s.label..'     '..(v.capture==id and '[ Press a key… ]'or Settings.bindings[id]),function()v.capture=id;v.message='Press a new key for '..s.label..'. Esc cancels.';bindingLabels(v)end);item.binding=s
  end
  if Settings.bindingError then v.message=Settings.bindingError end
 else
  add(left,size(list,790,710));add(list,caption('Conversations',32))
  local k=Settings.bindings
  add(list,caption(k.SingleText..' · Single text chat\n'..k.SingleVoice..' · Single voice chat\n'..k.GroupText..' · Group text chat\n'..k.GroupVoice..' · Group voice chat\n\nPress a voice key once to start and again to finish. Aim at someone to speak to them; otherwise the closest talking companion is used.'))
  add(list,caption('Support',32)):SetPadding({Left=0,Top=28,Right=0,Bottom=12})
  local copy=button(list,'Copy logs',function()
   if v.supportPending then return end
   v.supportSequence=(v.supportSequence or 0)+1
   local id=v.session..'-'..v.supportSequence
   local f=io.open(root..'/support-copy.request','w')
   if f then f:write(id);f:close();v.supportPending=id;v.supportStarted=os.time();v.message='Preparing diagnostic report…'
   else v.message='Cannot write the diagnostic request. Check mod-folder permissions.'end
   refresh(v,Party.view())
  end);copy.prominent=true
  add(list,caption('Copies recent diagnostic logs to your clipboard and saves support-report.txt. Conversation history and configuration are excluded.',22))
  describe('Travelling together','Companions follow and fight automatically. You can ask them to stop or follow during a conversation.\n\nQueue multiple summons without waiting. The panel closes when loading completes and you stop browsing. Loading waits while the game is paused.\n\nUp / Down: select a row\nLeft / Right: change a setting\nEnter: choose\nEsc: go back\n'..k.Menu..': close the menu\n\nReassign the five shortcuts under Controls.')
 end
 if not v.feedback then v.feedback=caption('',22);add(detail,v.feedback):SetPadding({Left=0,Top=20,Right=0,Bottom=0})end
 v.summary=caption('',23);v.summary:SetAutoWrapText(false);add(v.content,size(v.summary,1580,36)):SetPadding({Left=0,Top=18,Right=0,Bottom=0})
 refresh(v,model)
 v.focus=math.min(v.focus or 1,#v.buttons)
end
function M.toggle(pc)
 if view then M.close();return end
 assert(AI.valid(pc)and AI.valid(pc.Pawn),'Load a save first');dependency();Settings.poll();Settings.pollBindings()
 serial=serial+1
 local v={pc=pc,world=pc.Pawn:GetWorld(),page='Summon',focus=1,buttons={},textCache={},touched=os.time(),message='',refreshAt=0,inputOffset=0,requests={},dismissing={},session=tostring(os.time())..'-'..serial};view=v
 local ok,err=pcall(function()
  v.theme=Theme.resolve(function(event,detail)print('[DawnwalkerConvai UI] '..event..': '..tostring(detail)..'\n')end)
  local lib=cls('/Script/UMG.Default__WidgetBlueprintLibrary');v.library=lib
  v.host=lib:Create(pc,cls('/Script/CommonUI.CommonActivatableWidget'),pc);assert(AI.valid(v.host),'Native widget creation failed');v.tree=v.host.WidgetTree
  v.clickClass=Theme.asset('/Game/_Dawnwalker/UI/_Unified/BaseWidgets/DWW_Button.DWW_Button_C')
  v.emptyAction={RowName=FName('None')}
  v.host.bIsBackHandler=true;v.host.bIsModal=true;v.host.bAutoActivate=false;v.host.bAutoRestoreFocus=false
  local border=new('Border');border:SetBrushColor({R=.003,G=.004,B=.006,A=1});border:SetPadding({Left=0,Top=0,Right=0,Bottom=0});border:SetHorizontalAlignment(0);border:SetVerticalAlignment(0);v.tree.RootWidget=border
  local outer=new('Overlay');border:SetContent(outer);fill(add(outer,art('background')))
  local design=new('Overlay');local scale=new('ScaleBox');scale:SetStretch(2);scale:SetContent(size(design,1920,1080));fill(add(outer,scale))
  v.content=new('VerticalBox');fill(add(design,v.content)):SetPadding({Left=150,Top=92,Right=150,Bottom=88})
  -- Persistent footer, independent of scroll content and selected page.
  v.backButton=new('Button');v.backButton.IsFocusable=false
  local label=caption('BACK',21);Theme.button(v.backButton,label,v.theme,false);Theme.font(label,v.theme,21);label:SetAutoWrapText(false)
  local footer=new('HorizontalBox');v.backButton:SetContent(footer);fill(footer.Slot):SetPadding({Left=0,Top=0,Right=0,Bottom=0})
  add(footer,size(art('esc'),36,36)):SetVerticalAlignment(2)
  local labelSlot=add(footer,label);labelSlot:SetVerticalAlignment(2);labelSlot:SetPadding({Left=10,Top=0,Right=0,Bottom=0})
  local backOverlay=new('Overlay');fill(add(backOverlay,v.backButton));v.backClick=clickLayer(backOverlay,v.backButton)
  local slot=add(design,size(backOverlay,180,44));slot:SetHorizontalAlignment(1);slot:SetVerticalAlignment(3);slot:SetPadding({Left=150,Top=0,Right=0,Bottom=64})
  render()
  for _,parent in ipairs(FindAllOf('WBP_PauseMenu_C')or {})do if AI.valid(parent)and parent:IsInViewport()and parent:IsActivated()then
   v.parent=parent;v.parentBack=parent.bIsBackHandler;v.parentEnabled=parent:GetIsEnabled();parent.bIsBackHandler=false;parent:SetIsEnabled(false);break
  end end
  v.host:AddToViewport(150);v.host:ActivateWidget();v.lease=assert(Input.acquire(pc,lib,cls('/Script/Engine.Default__GameplayStatics'),v.host))
  local f=io.open(root..'/native-menu-input.txt','w');if f then f:close()end
  marker(tostring(os.time())..'\t'..v.session)
 end)
 if not ok then M.close();error(err)end
end
function M.input(name)
 local v=view;if not v then return end;v.touched=os.time()
 if v.capture then
  if name=='Escape'then back();return end
  local ok,why=Settings.bind(v.capture,name)
  if ok then v.message='Saved '..name;v.capture=nil;bindingLabels(v) else v.message=why end
  return
 end
 if name=='Escape'then back();return end
 if name==Settings.bindings.Menu then M.close();return end
 if name=='Down'or name=='Up'then
  v.focus=((v.focus-1+(name=='Down'and 1 or -1))%#v.buttons)+1
  local b=v.buttons[v.focus];pcall(function()v.list:ScrollWidgetIntoView(b.widget,true,0,12)end)
 elseif name=='Enter'then local b=v.buttons[v.focus];if b and b.enabled then b.action()end
 elseif name=='Left'or name=='Right'then local b=v.buttons[v.focus];if b and b.setting then changeSetting(b.setting,name=='Left'and -1 or 1)end end
end
local function readInput(v)
 local f=io.open(root..'/native-menu-input.txt','r');if not f then return end
 f:seek('set',v.inputOffset)
 for _=1,32 do local pos=f:seek();local line=f:read('*l');if not line then break end
  local session,name=line:match('^([^\t]+)\t([%w]+)$')
  if not name then f:seek('set',pos);break end
  v.inputOffset=f:seek();if session==v.session then M.input(name);if view~=v then break end end
 end
 f:close()
end
function M.tick()
 local v=view;if not v then return end
 if not AI.valid(v.pc)or not AI.valid(v.pc.Pawn)or not AI.same(v.pc.Pawn:GetWorld(),v.world)or not AI.valid(v.host)or not v.host:IsActivated()then M.close();return end
 readInput(v);if view~=v then return end
 if v.previewUntil then
  if os.time()>=v.previewUntil then M.close();return end
  if not v.previewShot and os.time()>=v.previewUntil-2 then
   v.previewShot=true
   cls('/Script/Engine.Default__KismetSystemLibrary'):ExecuteConsoleCommand(v.pc,'Shot SHOWUI',v.pc)
  end
 end
 if v.dirty then render()end
 -- IsPressed survives Slate routing; PlayerController key polling does not.
 if v.backClick:GetSelected()then v.backClick:ClearSelection();back();return end
 for _,s in ipairs(v.sliders)do
  local value=s.widget:GetValue();local snapped=math.max(s.setting.min,math.min(s.setting.max,math.floor((value-s.setting.min)/s.setting.step+.5)*s.setting.step+s.setting.min))
  if snapped~=s.value then
   Settings.change(s.setting.id,(snapped-Settings.values[s.setting.id])/s.setting.step);s.value=snapped;text(s.item.value,Settings.label(s.setting));v.touched=os.time()
  end
 end
 for i,b in ipairs(v.buttons)do
  local hovered=b.setting and b.setting.max~=1 and b.widget:IsHovered()or b.click:IsHovered();local clicked=b.click:GetSelected()
  if hovered and v.hover~=b then v.touched=os.time();v.hover=b;v.focus=i end
  local selected=i==v.focus
  -- selectionState writes native brush proxies. Call it only when the visual
  -- state changes; idle ticks should neither invalidate layout nor scan objects.
  local paintedSelected=selected or b.active or (b.prominent and b.enabled)or false
  local visual=paintedSelected and 2 or hovered and 1 or 0
  if b.visual~=visual then
   b.visual=visual
   local alpha=Theme.selectionState(b.widget,v.theme,paintedSelected,hovered,false)
   b.widget:SetBackgroundColor({R=1,G=1,B=1,A=alpha})
  end
  if selected and b.help then describe(b.title,b.help)end
  -- CommonUI retains even a completed quick click until we consume it. Clear
  -- before dispatch; other rows keep their latches for the next EngineTick.
  if clicked then
   b.click:ClearSelection()
   if b.enabled and not v.capture then v.touched=os.time();b.action();return end
  end
 end
 if os.time()~=(v.refreshAt or 0)then
  v.refreshAt=os.time();marker(tostring(os.time())..'\t'..v.session)
  if v.supportPending then
   local f=io.open(root..'/support-copy.result','r');local result=f and f:read(512)or '';if f then f:close()end
   local id,message=result:match('^([^\t]+)\t([^\r\n]+)')
   if id==v.supportPending then v.message=message;v.supportPending=nil
   elseif os.time()-(v.supportStarted or 0)>15 then v.message='The helper did not respond. Restart the game and try Copy logs again.';v.supportPending=nil end
  end
  if Settings.pollBindings()then if v.page=='Controls'then bindingLabels(v)elseif v.page=='Help'then v.dirty=true end end
  local state=Party.view();refresh(v,state)
  if v.page=='Party'then local byId={};for _,m in ipairs(state.members)do byId[m.id]=m end
   for _,b in ipairs(v.buttons)do if b.memberId then local m=byId[b.memberId];if m then text(b.label,m.name..' · '..m.status)else v.dirty=true end end end
  end
  if v.page=='Summon'and v.autoCloseQueued and not v.capture and v.readyAt and os.time()-v.readyAt>=2 and os.time()-v.touched>3 then M.close();return end
 end
end
function M.preview(pc)
 if view then M.close()end;M.toggle(pc);view.previewUntil=os.time()+5
end
function M.probe(pc)
 local reports={};local ok,err=pcall(function()
  if view then M.close()end;M.toggle(pc)
  for _,name in ipairs({'Summon','Party','Settings','Controls','Help'})do
   view.page=name;render();assert(view.buttons[1].label.Font.Size==26,'Button theme reset the font size')
   for _,s in ipairs(view.sliders)do assert(math.abs(s.widget:GetValue()-Settings.values[s.setting.id])<.01,'Slider value mismatch')end
   reports[#reports+1]=name..': '..#view.buttons..' controls'
  end
  view.page='Summon';view.category='combat';render();reports[#reports+1]='Combat roster: '..#view.buttons..' controls'
  local candidate;for _,b in ipairs(view.buttons)do if b.characterId then candidate=b;break end end
  local queued=Party.view().queued
  candidate.click:HandleButtonClicked();assert(candidate.click:GetSelected(),'Native click was not retained')
  M.tick();assert(view.selection and view.selection.id==candidate.characterId,'Native click did not select the character')
  assert(Party.view().queued==queued,'Selecting a character unexpectedly summoned it')
  candidate.click:HandleButtonClicked();M.tick();assert(not candidate.click:GetSelected(),'Repeated click was not consumed')
  reports[#reports+1]='Native click latch: repeated selection consumed without spawning'
  view.page='Controls';render();view.capture='Menu';M.input('Escape');assert(view and not view.capture and view.page=='Controls','Escape must cancel capture first')
  M.input('Escape');assert(view and view.page=='Summon','Escape must go back to Summon')
  M.input('Escape');assert(not view,'Escape must close the root page')
  reports[#reports+1]='Escape: capture cancellation, page back and close passed'
 end)
 M.close();if not ok then error(err)end;return table.concat(reports,'\n')
end
return M
