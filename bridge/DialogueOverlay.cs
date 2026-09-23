using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Net;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;

public sealed class DialogueState {
    public string text,hordeText,status,actor,name,microphoneStatus,microphoneTranscript,microphoneDevice,mode,room;
    public double microphoneLevel;public bool microphoneSilent;
    public bool active,gameAlive,microphoneRequested,microphoneOn;
    public long generation,updated;
}
public sealed class DialogueOverlay : Form {
    [StructLayout(LayoutKind.Sequential)] struct Rect {public int Left,Top,Right,Bottom;}
    [StructLayout(LayoutKind.Sequential)] struct PointNative {public int X,Y;}
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h,out Rect r);
    [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h,ref PointNative p);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool RegisterHotKey(IntPtr h,int id,uint modifiers,uint key);
    [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr h,int id);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h,int index);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h,int index,int value);
    [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] static extern int AddFontResourceEx(string path,uint flags,IntPtr reserved);
    readonly PrivateFontCollection gameFonts=new PrivateFontCollection();
    Font GameFont(float size,FontStyle style=FontStyle.Regular){return gameFonts.Families.Length>0?new Font(gameFonts.Families[0],size*96f/72f,style,GraphicsUnit.Pixel):new Font("Georgia",size*96f/72f,style,GraphicsUnit.Pixel);}
    readonly string runtime,token; readonly bool preview;
    readonly JavaScriptSerializer json=new JavaScriptSerializer();
    readonly TextBox input=new TextBox();readonly Button send=new Button();
    readonly Timer timer=new Timer();ComposerKeys composerKeys;
    DialogueState state=new DialogueState();IntPtr game;
    readonly ModKeyBindings bindings=new ModKeyBindings();
    ComposerKeys nativeMenuKeys;string nativeMenuSession="";bool menuRegistered;long nativeMenuStamp;
    bool NativeMenuOpen {get{return nativeMenuSession!="";}}
    void ClearHotkeys(){
        if(singleRegistered)UnregisterHotKey(Handle,1846);if(singleMicRegistered)UnregisterHotKey(Handle,1847);
        if(registered)UnregisterHotKey(Handle,1848);if(micRegistered)UnregisterHotKey(Handle,1849);if(menuRegistered)UnregisterHotKey(Handle,1845);
        singleRegistered=singleMicRegistered=registered=micRegistered=menuRegistered=false;
    }
    void NativeMenuInput(bool focused){
        string session=focused&&DateTimeOffset.UtcNow.ToUnixTimeSeconds()-nativeMenuStamp<4?nativeMenuSession:"";
        try{var row=ReadShared(Path.Combine(runtime,"native-menu-open.txt")).Trim().Split('\t');long stamp;
            if(row.Length==1&&row[0]=="0")session="";
            else if(focused&&row.Length==2&&long.TryParse(row[0],out stamp)&&DateTimeOffset.UtcNow.ToUnixTimeSeconds()-stamp<4){session=row[1];nativeMenuStamp=stamp;}}catch{}
        if(session==nativeMenuSession)return;
        if(nativeMenuKeys!=null){nativeMenuKeys.Dispose();nativeMenuKeys=null;}
        nativeMenuSession=session;
        if(session!=""){
            ClearHotkeys();
            nativeMenuKeys=new ComposerKeys(this,()=>Alive&&NativeMenuOpen&&IsGame(GetForegroundWindow()),(key,copy,shift,ctrl)=>{
                if(ctrl||shift)return;
                File.AppendAllText(Path.Combine(runtime,"native-menu-input.txt"),nativeMenuSession+"\t"+ModKeyBindings.Name(key)+"\n");
            },false);
        }
    }
    bool editing,registered,sending,opening,micRegistered,micBusy,singleRegistered,singleMicRegistered,closing;float scale=1;long composeGeneration;string error="",lastOpen="";
    bool voiceGroup,micStopping;string voiceNotice="";DateTime voiceNoticeUntil;
    bool VoiceNoticeVisible {get{return voiceNotice!=""&&DateTime.UtcNow<voiceNoticeUntil;}}
    bool VoiceVisible {get{return state.microphoneOn||(state.microphoneRequested&&VoiceFailed)||VoiceNoticeVisible;}}
    bool HordeVisible {get{return !editing&&!opening&&!sending&&!VoiceVisible&&String.IsNullOrWhiteSpace(state.text)&&!String.IsNullOrWhiteSpace(state.hordeText);}}
    string DisplayText {get{return HordeVisible?state.hordeText:state.text;}}
    string VoiceKey {get{return (micBusy||VoiceNoticeVisible?voiceGroup:state.mode=="group")?bindings.Label("GroupVoice"):bindings.Label("SingleVoice");}}
    bool VoiceFailed {get{return !state.microphoneOn&&!String.IsNullOrEmpty(state.microphoneStatus)&&(state.microphoneStatus.StartsWith("Microphone unavailable")||state.microphoneStatus.StartsWith("Microphone control failed")||state.microphoneStatus.StartsWith("Microphone disconnected"));}}
    bool Alive {get{return !closing&&!IsDisposed&&!Disposing;}}
    readonly Color ink=Color.FromArgb(236,227,206),gold=Color.FromArgb(173,148,102),panel=Color.FromArgb(19,21,19);
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000|0x20;return p;}}
    public DialogueOverlay(string directory,string auth,bool renderPreview=false){
        runtime=directory;token=auth;preview=renderPreview;
        try{var fontPath=Path.GetFullPath(Path.Combine(runtime,"../bridge/fonts/Afacad-Regular.ttf"));gameFonts.AddFontFile(fontPath);AddFontResourceEx(fontPath,0x10,IntPtr.Zero);}catch{}
        try{lastOpen=ReadShared(Path.Combine(runtime,"ui-open.txt"));}catch{}
        FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;DoubleBuffered=true;
        AutoScaleMode=AutoScaleMode.None;BackColor=panel;Opacity=0.95;KeyPreview=true;Width=760;Height=90;
        input.BorderStyle=BorderStyle.None;input.BackColor=Color.FromArgb(30,31,27);input.ForeColor=ink;
        input.Font=GameFont(16);input.MaxLength=1200;input.Visible=false;
        send.UseVisualStyleBackColor=false;send.TabStop=false;send.FlatAppearance.BorderSize=1;send.FlatAppearance.MouseOverBackColor=Color.FromArgb(47,44,35);send.FlatAppearance.MouseDownBackColor=Color.FromArgb(62,54,39);send.Text="Send";send.FlatStyle=FlatStyle.Flat;send.FlatAppearance.BorderColor=gold;send.BackColor=panel;send.ForeColor=ink;send.Font=GameFont(11);send.Visible=false;
        Controls.Add(input);Controls.Add(send);
        send.Click+=async(s,e)=>await Submit();
        AcceptButton=send;
        KeyDown+=(s,e)=>{if(e.KeyCode==Keys.Escape){e.SuppressKeyPress=true;EndCompose(false);}};
        timer.Interval=100;timer.Tick+=(s,e)=>UpdateState();if(!preview)timer.Start();
        FormClosing+=(s,e)=>{closing=true;timer.Stop();if(nativeMenuKeys!=null){nativeMenuKeys.Dispose();nativeMenuKeys=null;}if(composerKeys!=null){composerKeys.Dispose();composerKeys=null;}};
        FormClosed+=(s,e)=>{var hwnd=IsHandleCreated?Handle:IntPtr.Zero;if(hwnd!=IntPtr.Zero){if(menuRegistered)UnregisterHotKey(hwnd,1845);if(registered)UnregisterHotKey(hwnd,1848);if(micRegistered)UnregisterHotKey(hwnd,1849);if(singleRegistered)UnregisterHotKey(hwnd,1846);if(singleMicRegistered)UnregisterHotKey(hwnd,1847);}timer.Dispose();};
    }
    static string ReadShared(string path){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var r=new StreamReader(f))return r.ReadToEnd();}
    static bool IsGame(IntPtr h){try{uint id;GetWindowThreadProcessId(h,out id);return Process.GetProcessById((int)id).ProcessName=="Dawnwalker";}catch{return false;}}
    void UpdateState(){
        if(!Alive)return;
        try{
            if(CompanionPanel.IsOpen){Hide();return;}
            state=json.Deserialize<DialogueState>(ReadShared(Path.Combine(runtime,"overlay.json")));
            var foreground=GetForegroundWindow();bool gameFocused=IsGame(foreground),ours=foreground==Handle;
            if(gameFocused)game=foreground;
            if(bindings.Read(runtime))ClearHotkeys();
            NativeMenuInput(state.gameAlive&&gameFocused);
            bool eligible=state.gameAlive&&(gameFocused||ours)&&!NativeMenuOpen;
            bool shortcuts=eligible&&!editing&&!opening;
            File.WriteAllText(Path.Combine(runtime,"mic-focus.txt"),(eligible?DateTimeOffset.UtcNow.ToUnixTimeMilliseconds():0).ToString());
            if(shortcuts&&!menuRegistered)menuRegistered=RegisterHotKey(Handle,1845,0x4000,(uint)bindings["Menu"]);
            if(!shortcuts&&menuRegistered){UnregisterHotKey(Handle,1845);menuRegistered=false;}
            if(shortcuts&&!singleRegistered)singleRegistered=RegisterHotKey(Handle,1846,0x4000,(uint)bindings["SingleText"]);
            if(shortcuts&&!singleMicRegistered)singleMicRegistered=RegisterHotKey(Handle,1847,0x4000,(uint)bindings["SingleVoice"]);
            if(!shortcuts&&singleRegistered){UnregisterHotKey(Handle,1846);singleRegistered=false;}
            if(!shortcuts&&singleMicRegistered){UnregisterHotKey(Handle,1847);singleMicRegistered=false;}
            if(shortcuts&&!micRegistered)micRegistered=RegisterHotKey(Handle,1849,0x4000,(uint)bindings["GroupVoice"]);
            if(!shortcuts&&micRegistered){UnregisterHotKey(Handle,1849);micRegistered=false;}
            if(shortcuts&&!registered)registered=RegisterHotKey(Handle,1848,0x4000,(uint)bindings["GroupText"]);
            if(!shortcuts&&registered){UnregisterHotKey(Handle,1848);registered=false;}
            if(!eligible&&editing&&!sending)EndCompose(false,false);
            if(eligible&&(editing||opening))File.WriteAllText(Path.Combine(runtime,"ui-active.txt"),DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
            if(!eligible||DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()-state.updated>4000){Hide();return;}
            var openPath=Path.Combine(runtime,"ui-open.txt");
            if(File.Exists(openPath)){var request=ReadShared(openPath);if(request!=lastOpen){lastOpen=request;if(!editing)BeginCompose(false);}}
            if(editing&&state.active){
                if(composeGeneration==0)composeGeneration=state.generation;
                else if(composeGeneration!=state.generation){error="Conversation changed. Close and select her again.";send.Enabled=false;}
            }
            if(editing&&!sending)send.Enabled=state.active&&composeGeneration==state.generation;
            Rect bounds;var origin=new PointNative();
            if(game!=IntPtr.Zero&&GetClientRect(game,out bounds)&&ClientToScreen(game,ref origin)){
                int gw=bounds.Right-bounds.Left,gh=bounds.Bottom-bounds.Top;
                float next=Math.Max(0.65f,Math.Min(2f,Math.Min(gw/1920f,gh/1080f)));
                ApplyScale(next);
                int width=Math.Min(gw-S(32),S(!editing&&VoiceVisible&&String.IsNullOrWhiteSpace(state.text)?480:760));
                int height=PanelHeight(width);
                SetBounds(origin.X+(gw-width)/2,origin.Y+gh-height-S(35),width,height);
            }
            if(editing||VoiceVisible||HordeVisible||(state.active&&!String.IsNullOrWhiteSpace(state.text))){LayoutInput();if(!Visible)Show();Invalidate();}else Hide();
        }catch{if(!editing)Hide();}
    }
    protected override void WndProc(ref Message m){if(m.Msg==0x21){m.Result=new IntPtr(3);return;}if(m.Msg==0x0312){int k=m.WParam.ToInt32();if(k==1845){if(editing)EndCompose(false);HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"native-menu:"+Guid.NewGuid().ToString("N"));return;}if(k==1847||k==1849){ToggleMicrophone(k==1849);return;}if(k==1846||k==1848){if(editing)EndCompose(false);else BeginCompose(k==1848);return;}}base.WndProc(ref m);}
    int S(int value){return (int)Math.Round(value*scale);}
    void ApplyScale(float next){
        if(!Alive||Math.Abs(next-scale)<=0.01f)return;
        scale=next;GameControlFonts.Replace(input,GameFont(15*scale));GameControlFonts.Replace(send,GameFont(10*scale));
    }
    int SubtitleHeight(int width){
        using(var bitmap=new Bitmap(1,1))using(var g=Graphics.FromImage(bitmap))using(var font=GameFont(15)){
            float textHeight=g.MeasureString(DisplayText??"",font,Math.Max(80,(int)(width/scale)-48)).Height;
            return S(42+(int)Math.Ceiling(Math.Max(25,Math.Min(110,textHeight))));
        }
    }
    int VoiceHeight(int width){
        if(!VoiceVisible)return 0;
        string transcript=state.microphoneTranscript??"";
        if(String.IsNullOrWhiteSpace(transcript))return S(90);
        using(var bitmap=new Bitmap(1,1))using(var g=Graphics.FromImage(bitmap))using(var font=new Font("Segoe UI",12,FontStyle.Regular,GraphicsUnit.Pixel)){
            int lines=(int)Math.Ceiling(g.MeasureString("You: "+transcript,font,Math.Max(80,(int)(width/scale)-48)).Height);
            return S(72+Math.Max(26,lines));
        }
    }
    int PanelHeight(int width){return (editing?S(180):String.IsNullOrWhiteSpace(DisplayText)?0:SubtitleHeight(width))+VoiceHeight(width);}
    protected override bool ProcessCmdKey(ref Message msg,Keys keyData){
        if(editing&&keyData==Keys.Enter){SubmitFromKey();return true;}
        if(editing&&keyData==Keys.Escape){EndCompose(false);return true;}
        return base.ProcessCmdKey(ref msg,keyData);
    }
    async void SubmitFromKey(){await Submit();}
    void LayoutInput(){input.SetBounds(S(27),Height-S(70),Width-S(139),S(30));send.SetBounds(Width-S(95),Height-S(75),S(70),S(32));}
    void SetEditing(bool value){
        if(!Alive)return;
        editing=value;input.Visible=value;send.Visible=value;
        if(!preview){int style=GetWindowLong(Handle,-20);SetWindowLong(Handle,-20,value?(style|0x08000000)&~0x20:style|(0x08000000|0x20));}
        Height=Math.Max(S(67),PanelHeight(Width));LayoutInput();Invalidate();
        if(!value&&!VoiceVisible&&!HordeVisible&&String.IsNullOrWhiteSpace(state.text))Hide();
    }
    async void BeginCompose(bool group){
        if(!Alive||sending||opening||editing)return;opening=true;error="";
        CompanionPanel.CloseActive();
        var command=(group?"compose-group:":"compose-single:")+Guid.NewGuid().ToString("N");
        try{
            File.WriteAllText(Path.Combine(runtime,"ui-active.txt"),DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
            File.WriteAllText(Path.Combine(runtime,"ui-control.txt"),command);
            bool ready=false;
            for(int i=0;i<35;i++){
                await Task.Delay(100);
                if(!Alive)return;
                string reply="";try{reply=ReadShared(Path.Combine(runtime,"ui-ready.txt")).Replace("\r\n","\n");}catch{}
                if(reply.StartsWith(command+"\n")){ready=reply.TrimEnd().EndsWith("\nready");if(!ready)error=reply.Substring(command.Length).Trim();break;}
            }
            if(!ready){if(error=="")error="Conversation is not ready. Face an NPC and try the chat key again.";return;}
            if(!IsGame(GetForegroundWindow())){error="Return to the game and press the chat key again.";return;}
            if(!await AwaitSelection(command)){error="Waiting for the new conversation. Try the chat key again.";return;}
            if(!Alive)return;
            composeGeneration=state.generation;
            SetEditing(true);Show();
            if(!Alive)return;
            composerKeys=new ComposerKeys(this,()=>editing&&Visible&&GetForegroundWindow()==game,ComposerKey);
        }catch(Exception e){HostDiagnostics.Log("Open composer",e);if(Alive&&editing)EndCompose(false,false);error="Could not open the conversation.";}
        finally{opening=false;if(Alive)HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-status.txt"),error==""?"Composer ready":error);}
    }
    void EndCompose(bool clear,bool restoreGame=true){if(!Alive||sending)return;if(composerKeys!=null){composerKeys.Dispose();composerKeys=null;}if(clear)input.Clear();SetEditing(false);HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-active.txt"),"0");HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"close:"+Guid.NewGuid().ToString("N"));}
    public bool CloseForCompanions(){if(sending||opening)return false;if(editing)EndCompose(false,false);Hide();return true;}
    void ComposerKey(Keys key,string text,bool shift,bool ctrl){
        if(sending)return;
        // Letters and digits are text while composing, even if bound in gameplay.
        bool commandKey=(key>=Keys.F1&&key<=Keys.F12);
        if(commandKey&&key==bindings["Menu"]){EndCompose(false);HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"native-menu:"+Guid.NewGuid().ToString("N"));return;}
        if(commandKey&&(key==bindings["SingleVoice"]||key==bindings["GroupVoice"])){EndCompose(false,false);ToggleMicrophone(key==bindings["GroupVoice"]);return;}
        if(key==Keys.Enter){SubmitFromKey();return;}
        if(key==Keys.Escape||(commandKey&&(key==bindings["GroupText"]||key==bindings["SingleText"]))){EndCompose(false,false);return;}
        if(ctrl){
            if(key==Keys.A)input.SelectAll();
            if(key==Keys.C&&input.SelectionLength>0)Clipboard.SetText(input.SelectedText);
            if(key==Keys.V&&Clipboard.ContainsText())InsertText(Clipboard.GetText().Replace("\r"," ").Replace("\n"," "));
            return;
        }
        int start=input.SelectionStart,length=input.SelectionLength;
        if(key==Keys.Back){if(length==0&&start>0)input.Select(start-1,1);input.SelectedText="";return;}
        if(key==Keys.Delete){if(length==0&&start<input.TextLength)input.Select(start,1);input.SelectedText="";return;}
        if(key==Keys.Left||key==Keys.Right||key==Keys.Home||key==Keys.End){
            int next=key==Keys.Home?0:key==Keys.End?input.TextLength:key==Keys.Left?Math.Max(0,start-1):Math.Min(input.TextLength,start+length+1);
            if(shift)input.Select(Math.Min(start,next),Math.Abs(next-start));else input.Select(next,0);return;
        }
        if(!String.IsNullOrEmpty(text)&&!Char.IsControl(text[0]))InsertText(text);
    }
    void InsertText(string text){int available=input.MaxLength-input.TextLength+input.SelectionLength;if(available>0)input.SelectedText=text.Substring(0,Math.Min(available,text.Length));}
    async Task<bool> AwaitSelection(string command){
        string room=command.Substring(command.IndexOf(':')+1);
        for(int i=0;i<15;i++){
            if(!Alive)return false;
            try{state=json.Deserialize<DialogueState>(ReadShared(Path.Combine(runtime,"overlay.json")));if(state.active&&state.room==room)return true;}catch{}
            await Task.Delay(100);
        }
        return false;
    }
    async void ToggleMicrophone(bool group){
        if(!Alive||micBusy)return;
        bool turnOff=state.active&&state.microphoneRequested&&state.mode==(group?"group":"single");
        micBusy=true;micStopping=turnOff;voiceGroup=group;voiceNotice="";error="";
        UpdateState();
        try{
            if(!turnOff){
                CompanionPanel.CloseActive();
                var command=(group?"select-group:":"select-single:")+Guid.NewGuid().ToString("N");
                File.WriteAllText(Path.Combine(runtime,"ui-control.txt"),command);
                bool ready=false;
                for(int i=0;i<35;i++){await Task.Delay(100);if(!Alive)return;string reply="";try{reply=ReadShared(Path.Combine(runtime,"ui-ready.txt")).Replace("\r\n","\n");}catch{}if(reply.StartsWith(command+"\n")){ready=reply.TrimEnd().EndsWith("\nready");break;}}
                if(!ready){error="Face a nearby character and try again.";return;}
                if(!await AwaitSelection(command)){error="Waiting for the new conversation. Try again.";return;}
            }
            if(!Alive)return;
            if(!state.active){error="Face a nearby character and press the voice key again.";return;}
            if(!turnOff&&!IsGame(GetForegroundWindow())){error="Return to the game and press the voice key again.";return;}
            using(var client=new WebClient()){
                client.Headers["Content-Type"]="application/json";client.Headers["x-bridge-token"]=token;
                await client.UploadStringTaskAsync("http://127.0.0.1:32123/microphone","POST",json.Serialize(new{generation=state.generation,enabled=!turnOff}));
            }
        }catch{error="Could not change microphone state. Try again.";}
        finally{
            micBusy=false;micStopping=false;
            if(error!=""){voiceNotice=error;voiceNoticeUntil=DateTime.UtcNow.AddSeconds(8);}
            if(Alive)UpdateState();
        }
    }
    async Task Submit(){
        if(!Alive||sending)return;if(!state.active||composeGeneration!=state.generation){error="Waiting for the selected character. Try again shortly.";Invalidate();return;}
        var text=input.Text.Trim();if(text.Length==0){error="Write your reply first.";Invalidate();return;}
        sending=true;send.Enabled=false;input.Enabled=false;
        try{
            using(var client=new WebClient()){
                client.Encoding=System.Text.Encoding.UTF8;client.Headers["Content-Type"]="application/json";client.Headers["x-bridge-token"]=token;
                await client.UploadStringTaskAsync("http://127.0.0.1:32123/text","POST",json.Serialize(new{id=Guid.NewGuid().ToString("N"),generation=composeGeneration,text=text}));
            }
            if(!Alive)return;
            sending=false;input.Enabled=true;EndCompose(true);
        }catch(WebException e){error="Message could not be sent. Check the conversation and try again.";if(e.Response!=null)using(var r=new StreamReader(e.Response.GetResponseStream()))error=r.ReadToEnd();}
        catch{error="The connection is unavailable. Try again shortly.";}
        finally{sending=false;if(Alive){input.Enabled=true;send.Enabled=true;Invalidate();}}
    }
    string Speaker(){if(!String.IsNullOrEmpty(state.name))return state.name.ToUpperInvariant();if(String.IsNullOrEmpty(state.actor))return "ANCA";var name=state.actor.Substring(state.actor.LastIndexOf('.')+1);return Regex.Replace(name,"_[0-9]+$","").Replace('_',' ').ToUpperInvariant();}
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.ScaleTransform(scale,scale);int w=(int)(Width/scale),h=(int)(Height/scale);
        var logical=new Rectangle(0,0,w,h);
        using(var gradient=new LinearGradientBrush(logical,Color.FromArgb(28,29,24),panel,90))g.FillRectangle(gradient,logical);
        using(var pen=new Pen(gold,1)){g.DrawRectangle(pen,0,0,w-1,h-1);if(editing)g.DrawRectangle(pen,25,h-79,w-133,40);}
        using(var title=GameFont(11))using(var body=GameFont(15))using(var hint=new Font("Segoe UI",12,FontStyle.Regular,GraphicsUnit.Pixel))using(var light=new SolidBrush(ink))using(var brass=new SolidBrush(gold))using(var format=new StringFormat{Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Near,Trimming=StringTrimming.EllipsisWord}){
            if(!String.IsNullOrWhiteSpace(DisplayText)||editing){
                g.DrawString(HordeVisible?"HORDE":(state.mode=="group"?"GROUP · ":"")+Speaker(),title,brass,new RectangleF(24,8,w-48,22),format);
                var caption=String.IsNullOrWhiteSpace(DisplayText)?(editing?"What would you like to say?":""):DisplayText;
                g.DrawString(caption,body,light,new RectangleF(24,32,w-48,editing?60:h-39-(int)(VoiceHeight(Width)/scale)),format);
            }
            string footer=editing?(String.IsNullOrEmpty(error)?"ENTER  SEND     ·     ESC  RETURN":error):"";
            if(editing)g.DrawString(footer,hint,brass,new RectangleF(28,h-30,w-56,24),format);
            if(VoiceVisible){
                int voiceHeight=(int)(VoiceHeight(Width)/scale);int top=h-voiceHeight;
                if(top>0)using(var pen=new Pen(Color.FromArgb(65,gold),1))g.DrawLine(pen,24,top,w-24,top);
                bool listening=state.microphoneOn&&state.microphoneRequested&&!micBusy&&!VoiceNoticeVisible;
                bool stopping=micStopping||(state.microphoneOn&&!state.microphoneRequested);
                string heading=listening?"Speak now":stopping?"Finishing voice input…":VoiceNoticeVisible?"Voice chat unavailable":"Microphone unavailable";
                string instruction=listening?"Press "+VoiceKey+" again when you’re finished":VoiceNoticeVisible?voiceNotice:state.microphoneStatus??"Check your Windows default microphone";
                if(listening&&state.microphoneSilent)instruction="No input signal · check your Windows default microphone";
                if(listening&&!String.IsNullOrWhiteSpace(state.microphoneTranscript))instruction="You: "+state.microphoneTranscript;
                if(stopping)instruction="Your microphone is closing";
                string label=((micBusy||VoiceNoticeVisible?voiceGroup:state.mode=="group")?"GROUP CHAT":"SINGLE CHAT")+(listening?" · "+VoiceKey+" TO FINISH":" · MICROPHONE");
                g.DrawString(label,title,brass,new RectangleF(24,top+7,w-48,20),format);
                g.DrawString(heading,body,light,new RectangleF(24,top+28,w-48,30),format);
                g.DrawString(instruction,hint,brass,new RectangleF(24,top+60,w-48,voiceHeight-64),format);
                if(listening)using(var live=new SolidBrush(Color.FromArgb(147,183,134))){g.FillEllipse(live,16,top+13,6,6);g.FillRectangle(live,w-95,top+16,(float)(60*Math.Max(0,Math.Min(1,state.microphoneLevel))),3);}
            }
        }
    }
    public static void RenderPreview(string path){using(var form=new DialogueOverlay(Path.GetDirectoryName(path),"",true)){
        form.state=new DialogueState{actor="Anca_241",text="I have not forgotten what you did for us. Tell me, what brings you here?",active=true};
        form.SetEditing(true);form.input.Text="Tell me more about this place.";
        form.CreateControl();using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);form.input.DrawToBitmap(bitmap,form.input.Bounds);form.send.DrawToBitmap(bitmap,form.send.Bounds);bitmap.Save(path);}
        form.SetEditing(false);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".subtitle.png");}
        form.scale=0.667f;form.Width=form.S(760);form.Height=form.SubtitleHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".720.png");}
        foreach(float next in new[]{1f,.667f})foreach(string mode in new[]{"single","group"}){
            form.ApplyScale(next);form.state=new DialogueState{active=true,gameAlive=true,mode=mode,microphoneRequested=true,microphoneOn=true,microphoneLevel=.65};
            form.Width=form.S(480);form.Height=form.PanelHeight(form.Width);
            using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".voice-"+mode+(next<1?"-720":"-1080")+".png");}
        }
        form.ApplyScale(1f);form.state=new DialogueState{active=true,name="Anca",mode="single",text="Tell me what happened.",microphoneRequested=true,microphoneOn=true,microphoneLevel=.4,microphoneTranscript="What do you remember about Leonica?"};
        form.Width=form.S(760);form.Height=form.PanelHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".voice-subtitle.png");}
        form.state.text="";form.state.microphoneTranscript="I wanted to ask about the people we met on the road, what happened before we arrived in the valley, and whether you remember the promise we made to help them when the fighting was over. Please tell me everything you can remember.";
        form.Width=form.S(480);form.Height=form.PanelHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".voice-long.png");}
        form.state.microphoneOn=false;form.state.microphoneStatus="Microphone unavailable: permission denied";
        form.Width=form.S(480);form.Height=form.PanelHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".voice-error.png");}
    }}
    public static void VerifyInput(string path){
        string dir=Path.Combine(Path.GetTempPath(),"DawnwalkerComposerTest-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
        using(var form=new DialogueOverlay(dir,"",true)){
            form.SetEditing(true);
            form.ComposerKey(Keys.H,"H",true,false);form.ComposerKey(Keys.I,"i",false,false);
            if(form.input.Text!="Hi")throw new Exception("Typing failed");
            form.ComposerKey(Keys.Back,"",false,false);if(form.input.Text!="H")throw new Exception("Backspace failed");
            form.ComposerKey(Keys.A,"",false,true);form.ComposerKey(Keys.W,"World",false,false);
            if(form.input.Text!="World")throw new Exception("Selection replacement failed");
            form.ComposerKey(Keys.Home,"",false,false);form.ComposerKey(Keys.Delete,"",false,false);
            if(form.input.Text!="orld")throw new Exception("Navigation/delete failed");
            form.ComposerKey(Keys.Enter,"",false,false);
            if(!form.error.StartsWith("Waiting for"))throw new Exception("Enter did not reach submit");
            form.ComposerKey(Keys.Escape,"",false,false);if(form.editing)throw new Exception("Escape failed");
            File.WriteAllText(path,"PASS: typing, replacement, backspace, navigation, delete, Enter and Escape; no game input or foreground activation.");
        }
    }
    public static void VerifyFonts(string directory,string output){
        using(var form=new DialogueOverlay(Path.Combine(directory,"runtime"),"",true)){
            if(form.gameFonts.Families.Length==0)throw new Exception("Verification must load the bundled game-style font");
            var original=form.input.Font;
            form.ApplyScale(16f/15f); // 2048x1152: replacement equals the initial font.
            if(!Object.ReferenceEquals(form.input.Font,original))throw new Exception("Equal font should retain the existing instance");
            foreach(float next in new[]{1.1f,1f,16f/15f,.667f,1.25f,1.333333f,2f,.8f,16f/15f}){
                form.ApplyScale(next);form.SetEditing(true);
                // Force the actual HWND path that the fallback-font test missed.
                var inputHandle=form.input.Handle;var sendHandle=form.send.Handle;
                if(inputHandle==IntPtr.Zero||sendHandle==IntPtr.Zero)throw new Exception("Composer HWND unavailable");
                using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);}
                form.SetEditing(false);
            }
            form.Dispose();form.EndCompose(false);form.SetEditing(true);
            if(form.IsHandleCreated)throw new Exception("Disposed composer recreated its HWND");
        }
        CompanionPanel.VerifyFonts(directory);
        File.WriteAllText(output,"PASS: bundled Afacad font; equal-size replacement; real textbox/button HWND creation and drawing at nine scales; companion-panel font resizing; disposed composer stays closed. No game input or microphone capture.");
    }
}
