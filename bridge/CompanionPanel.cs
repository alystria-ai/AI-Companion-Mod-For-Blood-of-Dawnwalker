using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Text;
using System.Drawing.Drawing2D;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class CompanionCandidate {public string id,name,path,characterId;public override string ToString(){return name;}}
public sealed class CompanionMember {
 public string id,name,characterId,label,status,mode,detail,actor;
 public double? health,stamina;public bool canFight;
}
public sealed class CompanionReply {public string id,message;public bool ok;}
public sealed class CompanionView {
 public string epoch,note;public bool gameAlive,canSummon;public int limit,queued;public long updated;
 public CompanionCandidate[] roster;public CompanionMember[] members;public CompanionReply result;
 public CompanionSummon[] summons;
}
// Same nonactivating window strategy as conversation subtitles/composer. No
// browser window, Electron runtime, synthetic input, or game focus transfer.
public sealed class CompanionPanel : Form {
 [StructLayout(LayoutKind.Sequential)]struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)]struct PointNative {public int X,Y;}
 [DllImport("user32.dll")]static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll")]static extern bool GetClientRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")]static extern bool ClientToScreen(IntPtr h,ref PointNative p);
 [DllImport("user32.dll")]static extern bool RegisterHotKey(IntPtr h,int id,uint modifiers,uint key);
 [DllImport("user32.dll")]static extern bool UnregisterHotKey(IntPtr h,int id);
 static CompanionPanel active;
 public static bool IsOpen {get{return active!=null&&(active.opened||active.opening);}}
 public static void CloseActive(){if(active!=null)active.End();}
 readonly string runtime,token;readonly Func<bool> closeDialogue;
 readonly JavaScriptSerializer json=new JavaScriptSerializer();readonly Timer timer=new Timer();
 readonly Timer animation=new Timer();readonly Stopwatch clock=Stopwatch.StartNew();
 CompanionLoadBatch loading=new CompanionLoadBatch();
 readonly CompanionLoadBar loadBar=new CompanionLoadBar();readonly Label loadTitle=new Label(),loadStage=new Label(),loadNote=new Label(),loadProgress=new Label();
 readonly PrivateFontCollection fonts=new PrivateFontCollection();
 readonly Color ink=Color.FromArgb(236,227,206),gold=Color.FromArgb(173,148,102),panel=Color.FromArgb(19,21,19);
 readonly CompanionRoster roster=new CompanionRoster();readonly Label heading=new Label(),detail=new Label(),result=new Label(),hint=new Label();
 readonly Dictionary<Control,Rectangle> positions=new Dictionary<Control,Rectangle>();
 readonly Dictionary<Control,float> sizes=new Dictionary<Control,float>();
 readonly Dictionary<Control,int> pages=new Dictionary<Control,int>();
 readonly List<CompanionButton> helpTopics=new List<CompanionButton>();
 readonly List<Label> helpLabels=new List<Label>();
 static readonly string[][] helpCopy={
  new[]{
   "SUMMON & TRAVEL", "Choose someone under SUMMON, then summon them. They follow you and help in your fights automatically. No combat settings are needed. F5 or Esc closes this menu.",
   "YOUR COMPANY", "YOUR PARTY lists each summoned companion. Select one to dismiss them. A single character has a plain name; duplicates are numbered. Copies share memories and conversation history.",
   "NATIVE COMBAT", "Each character chooses their own attacks, timing and abilities. The mod provides a friendly ally and a hostile target. A boss move that requires a player target may be unavailable against NPCs.",
   "LEAVING A FIGHT", "Short dodges and flanking near enemies keep the fight going. Sustained movement away from the fight calls companions back after their uninterruptible actions. They rejoin before fighting again."
  },
  new[]{
   "TALK TO ONE CHARACTER", "Face a nearby character. F6 opens text chat; Enter sends. F7 toggles the microphone. Close this menu before chatting. Subtitles, voice and lip sync accompany their reply.",
   "FOLLOW & STOP", "Ask ‘follow me’ to resume following, or ‘stop walking’ to wait here. These requests work through conversation. Waiting lasts until Follow; ending chat alone does not resume a stopped companion.",
   "GROUP CONVERSATIONS", "F8 opens group text; F9 records group voice. The addressed or nearest character replies first, then up to two other distinct characters chosen by relationships, your topic and distance.",
   "CONVERSATION & MEMORY", "‘Look at me’ faces Coen during chat; ‘leave’ ends chat without dismissing a party member. Lore and reviewed quest facts are filtered per character. Copies share history; group speakers take turns."
  },
  new[]{
   "LOADING A CHARACTER", "Queue more summons while loading. Unpause to let them arrive. The bar shows stages, not seconds. The panel closes when all are ready; browsing adds a short grace period. F5 closes early.",
   "MISSING OR WAITING", "Waiting for you means they were asked to stop: ask them to follow. Catch-up does not revive the defeated or teleport during combat, scenes or airborne movement. Unloaded AI may need you closer.",
   "COMBAT VARIANTS", "Campaign AI still needs its weapons, native combat definition and a valid enemy. Some story variants have limited attacks. The mod cannot promise every scripted boss ability against other NPCs.",
   "RELOADS & LARGE PARTIES", "Mod reloads and world changes release summoned companions; summon them again. There is no party or duplicate limit. Larger parties need more space and game resources."
  }
 };
 int buildingPage=-1,currentPage; Rectangle lastGameBounds;
 bool partyList;string listSignature="";CompanionButton rosterTab,partyTab;
 string lastVisual=""; long lastLease;
 Button spawn,dismiss,dismissAll;
 CompanionView state=new CompanionView();ComposerKeys keys;IntPtr game;
 bool registered,opened,opening,loadingShown;int pendingPosts;bool busy {get{return pendingPosts>0;}}float scale=1;string selectedId="",lastReply="",message="";
 protected override bool ShowWithoutActivation {get{return true;}}
 protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000;return p;}}
 Font FontAt(float size){return fonts.Families.Length>0?new Font(fonts.Families[0],size,FontStyle.Regular,GraphicsUnit.Pixel):new Font("Georgia",size,FontStyle.Regular,GraphicsUnit.Pixel);}
 public CompanionPanel(string directory,string auth,Func<bool> closeConversation){
  runtime=directory;token=auth;closeDialogue=closeConversation;active=this;
  try{fonts.AddFontFile(Path.GetFullPath(Path.Combine(runtime,"../bridge/fonts/Afacad-Regular.ttf")));}catch{}
  FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;DoubleBuffered=true;AutoScaleMode=AutoScaleMode.None;BackColor=panel;ForeColor=ink;Opacity=1;
  Label("COMPANIONS",30,22,640,43,32);
  Label("YOUR COMPANY IN THE VALE",32,67,650,22,15).ForeColor=gold;
  Button("F5 / Esc   Close",868,32,180,36,()=>End());
  Add(hint,32,110,270,25,16);hint.ForeColor=gold;
  roster.BackColor=Color.FromArgb(22,22,19);roster.ItemHeight=28;
  rosterTab=(CompanionButton)Button("SUMMON",30,142,127,31,()=>SwitchList(false));rosterTab.TabStyle=true;
  partyTab=(CompanionButton)Button("YOUR PARTY",167,142,127,31,()=>SwitchList(true));partyTab.TabStyle=true;
  sizes[rosterTab]=17;rosterTab.Font=FontAt(17);sizes[partyTab]=17;partyTab.Font=FontAt(17);
  roster.MouseDown+=(a,e)=>{if(e.Button==MouseButtons.Left)loading.Browse(clock.ElapsedMilliseconds);};
  roster.MouseWheel+=(a,e)=>loading.Browse(clock.ElapsedMilliseconds);
  roster.SelectedIndexChanged+=(a,e)=>SelectCharacter();Add(roster,30,181,264,436,20);
  spawn=Button("Summon companion",30,630,264,40,()=>Send("spawn"));
  dismissAll=Button("Dismiss entire party",30,678,264,26,()=>Send("dismiss_all"));
  Add(heading,326,103,560,48,34);heading.ForeColor=ink;
  dismiss=Button("Dismiss",908,111,140,36,()=>Send("dismiss"));
  Add(detail,328,162,710,52,18);detail.ForeColor=Color.FromArgb(180,171,153);
  buildingPage=0;
  Label("HELP & CONTROLS",326,237,722,30,20).ForeColor=gold;
  foreach(var name in new[]{"Getting started","Conversation","Troubleshooting"}){
   int index=helpTopics.Count;var button=(CompanionButton)Button(name,326+index*244,294,234,36,()=>SelectHelp(index));
   button.TabStyle=true;sizes[button]=18;button.Font=FontAt(18);helpTopics.Add(button);
  }
  for(int block=0;block<4;block++){
   int x=326+(block%2)*371,y=351+(block/2)*157;
   var title=Label("",x,y,350,28,16);title.ForeColor=gold;helpLabels.Add(title);
   var body=Label("",x,y+33,350,118,18);body.ForeColor=Color.FromArgb(201,192,173);helpLabels.Add(body);
  }
  SelectHelp(0);
  buildingPage=-2;
  Add(loadTitle,326,253,722,47,30);
  Add(loadStage,328,313,718,35,22);loadStage.ForeColor=gold;
  Add(loadBar,328,360,716,30);
  Add(loadProgress,328,410,712,150,20);loadProgress.ForeColor=ink;
  Add(loadNote,328,563,710,82,20);loadNote.ForeColor=Color.FromArgb(180,171,153);
  buildingPage=-1;
  Add(result,326,681,722,31,16);result.ForeColor=Color.FromArgb(195,180,148);
  ShowPage(0);
  timer.Interval=200;timer.Tick+=(s,e)=>Tick();timer.Start();
  animation.Interval=40;animation.Tick+=(s,e)=>{if(opened&&loading.Active){loadBar.Sweep=clock.ElapsedMilliseconds/1600.0;loadBar.Invalidate();}};animation.Start();
  FormClosed+=(s,e)=>{End();if(registered)UnregisterHotKey(Handle,1855);timer.Dispose();animation.Dispose();fonts.Dispose();if(active==this)active=null;};
 }
 void Add(Control c,int x,int y,int w,int h,float size=20){positions[c]=new Rectangle(x,y,w,h);sizes[c]=size;pages[c]=buildingPage;c.Font=FontAt(size);c.ForeColor=ink;c.SetBounds(x,y,w,h);Controls.Add(c);}
 Label Label(string text,int x,int y,int w,int h,float size=20){var c=new Label();c.UseMnemonic=false;c.Text=text;Add(c,x,y,w,h,size);return c;}
 Button Button(string text,int x,int y,int w,int h,Action action){var b=new CompanionButton();b.Text=text;b.FlatStyle=FlatStyle.Flat;b.BackColor=Color.FromArgb(27,27,22);b.UseVisualStyleBackColor=false;b.TabStop=false;b.Click+=(a,e)=>action();Add(b,x,y,w,h);return b;}
 void SelectHelp(int index){
  for(int i=0;i<helpLabels.Count;i++)TextIfChanged(helpLabels[i],helpCopy[index][i]);
  for(int i=0;i<helpTopics.Count;i++)helpTopics[i].Selected=i==index;
 }
 void ShowPage(int index){
  currentPage=index;loadingShown=loading.Active;SuspendLayout();foreach(var pair in pages)pair.Key.Visible=PageVisible(pair.Key,index);
  ResumeLayout(false);Invalidate();
 }
 bool PageVisible(Control c,int index){int page=pages[c];if(page==-2)return loading.Active;return page<0||!loading.Active&&page==index;}
 void RefreshLoading(){
  TextIfChanged(loadTitle,loading.Pending==0?"Your company is ready":"Summoning your company");
  if(loading.Failed>0)TextIfChanged(loadTitle,"Summoning finished with an issue");
  TextIfChanged(loadStage,loading.Summary());TextIfChanged(loadProgress,loading.Progress());
  TextIfChanged(loadNote,(state.note??"").StartsWith("Paused")?"You can queue more companions while paused. Unpause to let them arrive.":loading.Choosing?"Choose another companion and press Summon. Once all arrive, the panel closes after a short pause in browsing.":loading.Failed>0?"A summon failed. You can choose another companion or close with F5.":"Keep choosing companions from the roster. This panel closes after all your summons arrive.");
  if(loadBar.Stage!=loading.Stage){loadBar.Stage=loading.Stage;loadBar.Invalidate();}
  if(loadingShown!=loading.Active)ShowPage(currentPage);
  // Loading never captures or disables the roster. Selection/header continue
  // to describe the character the player is choosing for the NEXT summon.
  EnableIfChanged(roster,true);EnableIfChanged(dismissAll,!busy&&state.gameAlive);
 }

 protected override void OnPaint(PaintEventArgs e){
  base.OnPaint(e);var g=e.Graphics;
  using(var pen=new Pen(Color.FromArgb(85,74,53))){
   g.DrawRectangle(pen,0,0,Width-1,Height-1);g.DrawRectangle(pen,7*scale,7*scale,Width-14*scale,Height-14*scale);
   g.DrawLine(pen,30*scale,97*scale,1048*scale,97*scale);
   g.DrawLine(pen,310*scale,116*scale,310*scale,704*scale);
   g.DrawLine(pen,326*scale,670*scale,1048*scale,670*scale);
   float x=792*scale,y=53*scale,d=9*scale;
   g.DrawPolygon(pen,new[]{new PointF(x,y-d),new PointF(x+d,y),new PointF(x,y+d),new PointF(x-d,y)});
   g.DrawLine(pen,x-47*scale,y,x-d*1.8f,y);g.DrawLine(pen,x+d*1.8f,y,x+47*scale,y);
  }
 }
 static void TextIfChanged(Control c,string value){if(c.Text!=value)c.Text=value;}
 static void EnableIfChanged(Control c,bool value){if(c.Enabled!=value)c.Enabled=value;}
 static string Human(string value){var text=(value??"").Replace('_',' ');return text.Length==0?text:Char.ToUpperInvariant(text[0])+text.Substring(1);}
 static string Read(string path){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var r=new StreamReader(f))return r.ReadToEnd();}
 static bool IsGame(IntPtr h){try{uint id;GetWindowThreadProcessId(h,out id);return Process.GetProcessById((int)id).ProcessName=="Dawnwalker";}catch{return false;}}
 CompanionCandidate Candidate(){return roster.SelectedItem as CompanionCandidate;}
 CompanionMember Member(string id){if(state.members!=null)foreach(var m in state.members)if(m.id==id)return m;return null;}
 void SwitchList(bool party){loading.Browse(clock.ElapsedMilliseconds);partyList=party;listSignature="";UpdateList();RefreshText();}
 void UpdateList(){
  var items=new List<CompanionCandidate>();
  if(partyList){if(state.members!=null)foreach(var m in state.members)items.Add(new CompanionCandidate{id=m.id,characterId=m.characterId??m.id,name=m.label??m.name});}
  else if(state.roster!=null)items.AddRange(state.roster);
  string signature=json.Serialize(items);if(signature!=listSignature){listSignature=signature;roster.ReplaceItems(items.ToArray(),selectedId);if(items.Count==0)selectedId="";}
  rosterTab.Selected=!partyList;partyTab.Selected=partyList;roster.SetMembers(state.members);
 }
 void SelectCharacter(){var c=Candidate();if(c==null)return;selectedId=c.id;RefreshText();}
 void RefreshText(){
  var c=Candidate();var m=Member(selectedId);TextIfChanged(heading,c==null?"Choose a companion":c.name);
  bool loading=m!=null&&(m.status=="Spawning"||(m.status??"").StartsWith("Loading"));
  TextIfChanged(detail,m==null?"AVAILABLE TO SUMMON\nFollows you and fights alongside you with their native combat AI.":"IN YOUR PARTY  ·  "+m.status+(m.health.HasValue?"  ·  Health "+Math.Round(m.health.Value*100)+"%":"")+(m.stamina.HasValue?"  ·  Stamina "+Math.Round(m.stamina.Value*100)+"%":"")+"\n"+(loading?"Preparing your companion. You can close this menu while loading.":m.mode=="stop"?"Waiting here. Ask this companion to follow when you are ready.":"Follows you automatically; chooses their own attacks and abilities."));
  bool live=m!=null&&!busy&&state.gameAlive;
  EnableIfChanged(spawn,c!=null&&(state.gameAlive||state.canSummon));EnableIfChanged(dismiss,live);
  int count=state.members==null?0:state.members.Length;
  TextIfChanged(result,message);TextIfChanged(hint,count+(count==1?" COMPANION IN PARTY":" COMPANIONS IN PARTY"));
  RefreshLoading();
 }
 void Tick(){
  try{
   try{state=json.Deserialize<CompanionView>(Read(Path.Combine(runtime,"companions-panel.json")));}catch{/* Keep the last complete snapshot, but still process close/timeouts. */}
   state.gameAlive=state.gameAlive&&DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()-state.updated<5000;
   var foreground=GetForegroundWindow();bool eligible=IsGame(foreground)&&(state.gameAlive||opened&&loading.RetainDuringStall(clock.ElapsedMilliseconds));if(eligible)game=foreground;
   if(eligible&&!File.Exists(Path.Combine(runtime,"native-ui.enabled"))&&!registered)registered=RegisterHotKey(Handle,1855,0x4000,0x74);
   if((!eligible||File.Exists(Path.Combine(runtime,"native-ui.enabled")))&&registered){UnregisterHotKey(Handle,1855);registered=false;}
   if(!eligible){if(opened)End();return;}
   if(!opened)return;
   bool wasLoading=loading.Active;
   if(loading.Advance(state,clock.ElapsedMilliseconds)&&!busy){End();return;}
   if(wasLoading&&!loading.Active){message=loading.Message;RefreshText();}
   else if(loading.Active)RefreshLoading();
   long now=DateTimeOffset.UtcNow.ToUnixTimeSeconds();if(now!=lastLease){lastLease=now;File.WriteAllText(Path.Combine(runtime,"ui-active.txt"),now.ToString());}
   UpdateList();
   if(state.result!=null&&state.result.id!=lastReply){lastReply=state.result.id;message=state.result.message;}
   var visual=json.Serialize(new{state.epoch,state.gameAlive,state.canSummon,state.limit,state.members,state.result,state.summons});
   if(visual!=lastVisual){lastVisual=visual;RefreshText();roster.SetMembers(state.members);}
   LayoutPanel();
  }catch{/* Keep the last complete frame during an atomic bridge update. */}
 }
 void ApplyScale(float next){
  if(Math.Abs(next-scale)<.005f)return;
  scale=next;SuspendLayout();
  foreach(var pair in positions){var b=pair.Value;pair.Key.SetBounds((int)(b.X*scale),(int)(b.Y*scale),(int)(b.Width*scale),(int)(b.Height*scale));GameControlFonts.Replace(pair.Key,FontAt(sizes[pair.Key]*scale));}
  roster.ItemHeight=(int)(28*scale);ResumeLayout(false);Invalidate();
 }
 void LayoutPanel(){
  Rect r;var p=new PointNative();if(!GetClientRect(game,out r)||!ClientToScreen(game,ref p))return;
  var area=new Rectangle(p.X,p.Y,r.Right-r.Left,r.Bottom-r.Top);if(area==lastGameBounds)return;lastGameBounds=area;
  float next=Math.Min(1.7f,Math.Min((area.Width-32)/1080f,(area.Height-32)/720f));if(next<.5f)return;
  ApplyScale(next);int width=(int)(1080*scale),height=(int)(720*scale);
  var bounds=new Rectangle(p.X+(area.Width-width)/2,p.Y+(area.Height-height)/2,width,height);if(Bounds!=bounds)Bounds=bounds;
 }
 async void Begin(){
  if(opened||opening)return;if(!closeDialogue())return;opening=true;
  string command="party:"+Guid.NewGuid().ToString("N");
  try{
   File.WriteAllText(Path.Combine(runtime,"ui-active.txt"),DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());File.WriteAllText(Path.Combine(runtime,"ui-control.txt"),command);
   bool ready=false;
   for(int i=0;i<30;i++){await Task.Delay(100);string s="";try{s=Read(Path.Combine(runtime,"ui-ready.txt")).Replace("\r\n","\n");}catch{}if(s.StartsWith(command+"\n")){ready=s.TrimEnd().EndsWith("\nready");break;}}
   if(!opening||!ready||!IsGame(GetForegroundWindow())){message="Companion menu not ready. Load your save and try F5 again.";return;}
   opened=true;lastVisual="";lastGameBounds=Rectangle.Empty;Tick();if(!opened)return;Show();keys=new ComposerKeys(this,()=>opened&&Visible&&GetForegroundWindow()==game,Key);
  }catch(Exception e){message=e.Message;End();}
  finally{opening=false;if(!opened){HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"close:"+Guid.NewGuid().ToString("N"));HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-active.txt"),"0");}}
 }
 void End(){
  loading.Cancel();
  if(keys!=null){keys.Dispose();keys=null;}if(!opened&&!opening){Hide();return;}
  opened=false;opening=false;Hide();HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-active.txt"),"0");HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"close:"+Guid.NewGuid().ToString("N"));
 }
 protected override void WndProc(ref Message m){if(m.Msg==0x21){m.Result=new IntPtr(3);return;}if(m.Msg==0x0312&&m.WParam.ToInt32()==1855){if(opened)End();else Begin();return;}base.WndProc(ref m);}
 void Key(Keys key,string text,bool shift,bool ctrl){
  if(key==Keys.Escape||key==Keys.F5){End();return;}
 }
 async Task<string> Post(Dictionary<string,object> body){using(var client=new WebClient()){client.Headers["Content-Type"]="application/json";client.Headers["X-Bridge-Token"]=token;try{return await client.UploadStringTaskAsync("http://127.0.0.1:32123/companions","POST",json.Serialize(body));}catch(WebException e){if(e.Response!=null)using(var reader=new StreamReader(e.Response.GetResponseStream()))throw new Exception(reader.ReadToEnd());throw;}}}
 async void Send(string op,Dictionary<string,object> extra=null){
  if(op!="spawn"&&busy)return;
  if(op=="spawn"&&Candidate()==null)return;pendingPosts++;
  string member=op=="spawn"?(Candidate().characterId??Candidate().id):selectedId,epoch=state.epoch;CompanionLoading requestLoading=null;
  if(op=="spawn")requestLoading=loading.Add(member,Candidate().name,epoch,clock.ElapsedMilliseconds);
  else loading.Browse(clock.ElapsedMilliseconds);
  RefreshText();
  try{var body=extra??new Dictionary<string,object>();body["op"]=op;body["member"]=member;body["epoch"]=epoch;
   var reply=json.Deserialize<CompanionReply>(await Post(body));
   if(requestLoading!=null&&requestLoading.Active){if(reply.ok&&!String.IsNullOrEmpty(reply.id)){requestLoading.Request=reply.id;requestLoading.Member=reply.id;}else requestLoading.Fail(reply.message??"Summon request failed");}
   message=reply.message??"Command queued";
  }
  catch(Exception e){message=e.Message;if(requestLoading!=null)requestLoading.Fail(message);}finally{pendingPosts--;RefreshText();}
 }
 public static void VerifyFonts(string directory){
  using(var p=new CompanionPanel(Path.Combine(directory,"runtime"),"",()=>true)){
   p.timer.Stop();p.animation.Stop();
   if(p.fonts.Families.Length==0)throw new Exception("Companion verification must load the real font");
   foreach(float next in new[]{1.1f,1f,16f/15f,.667f,1.25f,1.333333f}){
    p.ApplyScale(next);
    foreach(var c in p.positions.Keys){var handle=c.Handle;if(handle==IntPtr.Zero)throw new Exception("Companion control HWND unavailable");}
   }
   if(active==p)active=null;
  }
 }
 public static void RenderPreview(string directory,string output){
  using(var p=new CompanionPanel(Path.Combine(directory,"runtime"),"",()=>true)){
   p.timer.Stop();p.animation.Stop();
   var config=p.json.Deserialize<Dictionary<string,object>>(File.ReadAllText(Path.Combine(directory,"characters/companion-config.json")));
   var candidates=p.json.Deserialize<CompanionCandidate[]>(p.json.Serialize(config["characters"]));
   p.state=new CompanionView{epoch="preview",gameAlive=true,limit=0,roster=candidates,members=new[]{new CompanionMember{id="pabc",characterId="anca",label="Anca",name="Anca",status="Following",mode="follow",canFight=true,health=.8,detail="Preview fixture only; not evidence of native gameplay."}},note="Timings pause with the game."};
   p.SwitchList(true);p.roster.SetMembers(p.state.members);
   p.message="Choose someone to summon, or select a party member to dismiss.";p.RefreshText();
   p.ShowPage(0);p.ClientSize=new Size(1080,720);p.CreateControl();
   for(int topic=0;topic<helpCopy.Length;topic++){
    p.SelectHelp(topic);
    string dest=topic==0?output:Path.Combine(Path.GetDirectoryName(output),Path.GetFileNameWithoutExtension(output)+"-help-"+topic+".png");
    using(var bitmap=new Bitmap(p.Width,p.Height)){p.DrawToBitmap(bitmap,p.ClientRectangle);foreach(Control child in p.Controls)if(p.PageVisible(child,0)){var handle=child.Handle;child.DrawToBitmap(bitmap,child.Bounds);}bitmap.Save(dest,System.Drawing.Imaging.ImageFormat.Png);}
   }
   p.SelectHelp(1);p.ApplyScale(.95f);p.ClientSize=new Size(1026,684);
   using(var bitmap=new Bitmap(p.Width,p.Height)){p.DrawToBitmap(bitmap,p.ClientRectangle);foreach(Control child in p.Controls)if(p.PageVisible(child,0)){var handle=child.Handle;child.DrawToBitmap(bitmap,child.Bounds);}bitmap.Save(Path.Combine(Path.GetDirectoryName(output),Path.GetFileNameWithoutExtension(output)+"-720p.png"),System.Drawing.Imaging.ImageFormat.Png);}
   var first=p.loading.Add("anca","Anca","preview",0);first.Phase="body";first.Message="Loading appearance and animations";
   var second=p.loading.Add("ambrus","Ambrus","preview",0);second.Phase="ai";second.Message="Preparing combat and movement";
   var third=p.loading.Add("lacra","Lacra","preview",0);third.Message="Queued for arrival";p.SwitchList(false);p.loadBar.Sweep=.48;p.RefreshText();p.ShowPage(0);
   using(var bitmap=new Bitmap(p.Width,p.Height)){p.DrawToBitmap(bitmap,p.ClientRectangle);foreach(Control child in p.Controls)if(p.PageVisible(child,0)){var handle=child.Handle;child.DrawToBitmap(bitmap,child.Bounds);}bitmap.Save(Path.Combine(Path.GetDirectoryName(output),Path.GetFileNameWithoutExtension(output)+"-loading.png"),System.Drawing.Imaging.ImageFormat.Png);}
  }
 }
}
