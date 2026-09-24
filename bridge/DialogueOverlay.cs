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
    [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr h,int attribute,ref int value,int size);
    [DllImport("gdi32.dll",CharSet=CharSet.Unicode)] static extern int AddFontResourceEx(string path,uint flags,IntPtr reserved);
    readonly PrivateFontCollection gameFonts=new PrivateFontCollection();
    Font GameFont(float size,FontStyle style=FontStyle.Regular){return gameFonts.Families.Length>0?new Font(gameFonts.Families[0],size*96f/72f,style,GraphicsUnit.Pixel):new Font("Georgia",size*96f/72f,style,GraphicsUnit.Pixel);}
    readonly string runtime,token; readonly bool preview;
    readonly JavaScriptSerializer json=new JavaScriptSerializer();
    readonly TextBox input=new TextBox();
    readonly Timer timer=new Timer();ComposerKeys composerKeys;
    DialogueState state=new DialogueState();IntPtr game;
    readonly ModKeyBindings bindings=new ModKeyBindings();
    ComposerKeys nativeMenuKeys;string nativeMenuSession="";bool menuRegistered;long nativeMenuStamp;
    bool NativeMenuOpen {get{return nativeMenuSession!="";}}
    string inputDiagnostic="";DateTime inputErrorAt;
    readonly System.Collections.Generic.Queue<string> inputHistory=new System.Collections.Generic.Queue<string>();
    void InputDiagnostic(string value){
        if(value==inputDiagnostic)return;inputDiagnostic=value;
        inputHistory.Enqueue(DateTime.UtcNow.ToString("o")+" "+value);while(inputHistory.Count>16)inputHistory.Dequeue();
        HostDiagnostics.TryWrite(Path.Combine(runtime,"input-status.txt"),String.Join(Environment.NewLine,inputHistory));
    }
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
    bool transparentHud=true,hideChatBoxes=false,showNpcSubtitles=true;DateTime hudReadAt;string hudConfig;
    int hudBottomPercent=0;
    readonly Stopwatch hudClock=Stopwatch.StartNew();float voiceMeter;
    readonly Color clearColour=Color.FromArgb(1,2,3);
    bool MinimalVoice {get{return hideChatBoxes;}}
    bool ClearBackground {get{return transparentHud||MinimalVoice;}}
    static bool ReadHudNumber(string source,string key,out double value){
        // Lua/native sliders can serialize a whole number as 28.0. Read using
        // the file's invariant decimal format, independently of Windows locale.
        var row=Regex.Match(source,@"(?m)^[ \t]*"+Regex.Escape(key)+@"[ \t]*=[ \t]*([+-]?\d+(?:\.\d+)?)[ \t]*(?:;[^\r\n]*)?\r?$");
        value=0;
        return row.Success&&double.TryParse(row.Groups[1].Value,System.Globalization.NumberStyles.Float,System.Globalization.CultureInfo.InvariantCulture,out value)&&!double.IsNaN(value)&&!double.IsInfinity(value);
    }
    void ReadHudSettings(bool force=false){
        if(!force&&DateTime.UtcNow<hudReadAt)return;hudReadAt=DateTime.UtcNow.AddSeconds(1);
        try{
            string directory=Path.GetFullPath(Path.Combine(runtime,"../mod"));
            var pointer=Path.Combine(runtime,"mod-directory.txt");if(File.Exists(pointer))directory=ReadShared(pointer).Trim();
            var source=ReadShared(Path.Combine(directory,"config.ini"));if(String.IsNullOrWhiteSpace(source)||source==hudConfig)return;
            double value;
            if(ReadHudNumber(source,"TransparentChatHud",out value)&&(value==0||value==1))transparentHud=value==1;
            if(ReadHudNumber(source,"HideChatBoxes",out value)&&(value==0||value==1))hideChatBoxes=value==1;
            else if(ReadHudNumber(source,"ShowConversationText",out value)&&(value==0||value==1))hideChatBoxes=value==0;
            if(ReadHudNumber(source,"ShowNpcSubtitles",out value)&&(value==0||value==1))showNpcSubtitles=value==1;
            if(ReadHudNumber(source,"ChatHudBottomOffset",out value))hudBottomPercent=(int)Math.Round(Math.Max(0,Math.Min(40,value)));
            hudConfig=source;ApplyHudStyle();
        }catch(IOException){}catch(UnauthorizedAccessException){}
    }
    void ApplyHudStyle(){
        var background=ClearBackground?clearColour:panel;
        // Do not expose an intermediate opaque/background frame while switching
        // the layered-window colour key and native child-control appearance.
        if(Visible&&BackColor!=background)Hide();
        if(BackColor!=background)BackColor=background;
        var key=ClearBackground?clearColour:Color.Empty;if(TransparencyKey!=key)TransparencyKey=key;
        double opacity=ClearBackground?1:.95;if(Opacity!=opacity)Opacity=opacity;
        // Native child controls otherwise paint opaque rectangles even when the
        // parent is transparent. Use the same colour key for their interiors.
        input.BackColor=ClearBackground?clearColour:Color.FromArgb(30,31,27);
    }
    bool VoiceNoticeVisible {get{return voiceNotice!=""&&DateTime.UtcNow<voiceNoticeUntil;}}
    bool VoiceVisible {get{return micBusy||state.microphoneRequested||state.microphoneOn||VoiceNoticeVisible;}}
    bool HordeVisible {get{return !editing&&!opening&&!sending&&!VoiceVisible&&String.IsNullOrWhiteSpace(state.text)&&!String.IsNullOrWhiteSpace(state.hordeText);}}
    string DisplayText {get{return HordeVisible?state.hordeText:!opening&&!editing&&!micBusy&&!hideChatBoxes&&showNpcSubtitles?state.text:"";}}
    string VoiceTranscript {get{return micBusy?"":state.microphoneTranscript??"";}}
    string VoiceKey {get{return (micBusy||VoiceNoticeVisible?voiceGroup:state.mode=="group")?bindings.Label("GroupVoice"):bindings.Label("SingleVoice");}}
    bool VoiceFailed {get{return !state.microphoneOn&&!String.IsNullOrEmpty(state.microphoneStatus)&&(state.microphoneStatus.StartsWith("Microphone unavailable")||state.microphoneStatus.StartsWith("Microphone control failed")||state.microphoneStatus.StartsWith("Microphone disconnected"));}}
    bool Alive {get{return !closing&&!IsDisposed&&!Disposing;}}
    readonly Color ink=Color.FromArgb(236,227,206),gold=Color.FromArgb(173,148,102),panel=Color.FromArgb(19,21,19);
    protected override bool ShowWithoutActivation {get{return true;}}
    protected override void OnHandleCreated(EventArgs e){
        base.OnHandleCreated(e);
        // No desktop fade from a cached rectangular window image when this
        // frequently reused overlay is shown again. Scope this to our HWND.
        try{int disabled=1;DwmSetWindowAttribute(Handle,3,ref disabled,4);}catch(DllNotFoundException){}catch(EntryPointNotFoundException){}
    }
    void Present(){
        if(!Alive)return;
        if(Visible){Refresh();return;}
        // Show/Refresh alone lets the desktop compositor reveal the preceding
        // backing surface before WM_PAINT. Paint parent and child controls at
        // zero opacity, then reveal only the completed current frame.
        double finalOpacity=ClearBackground?1:.95;
        Opacity=0;
        try{Show();Refresh();}finally{if(Alive)Opacity=finalOpacity;}
        if(!preview)HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-presentation.txt"),DateTime.UtcNow.ToString("o")+" transparent="+ClearBackground+" editing="+editing+" minimal="+MinimalVoice+" bounds="+Bounds+" offsetPercent="+hudBottomPercent+" colourKey="+TransparencyKey.ToArgb());
    }
    protected override CreateParams CreateParams {get{var p=base.CreateParams;p.ExStyle|=0x08000000|0x20;return p;}}
    public DialogueOverlay(string directory,string auth,bool renderPreview=false){
        runtime=directory;token=auth;preview=renderPreview;
        try{var fontPath=Path.GetFullPath(Path.Combine(runtime,"../bridge/fonts/Afacad-Regular.ttf"));gameFonts.AddFontFile(fontPath);AddFontResourceEx(fontPath,0x10,IntPtr.Zero);}catch{}
        try{lastOpen=ReadShared(Path.Combine(runtime,"ui-open.txt"));}catch{}
        FormBorderStyle=FormBorderStyle.None;ShowInTaskbar=false;TopMost=true;DoubleBuffered=true;
        AutoScaleMode=AutoScaleMode.None;StartPosition=FormStartPosition.Manual;BackColor=panel;Opacity=0.95;KeyPreview=true;Width=760;Height=90;
        ReadHudSettings();ApplyHudStyle();
        input.BorderStyle=BorderStyle.None;input.BackColor=Color.FromArgb(30,31,27);input.ForeColor=ink;
        input.Font=GameFont(18);input.MaxLength=1200;input.Visible=false;
        Controls.Add(input);
        ApplyHudStyle();
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
            voiceMeter+=(float)((Math.Max(0,Math.Min(1,state.microphoneLevel))-voiceMeter)*.45);
            var foreground=GetForegroundWindow();bool gameFocused=IsGame(foreground),ours=foreground==Handle;
            if(gameFocused)game=foreground;
            if(bindings.Read(runtime))ClearHotkeys();
            ReadHudSettings();
            bool wasMenuOpen=NativeMenuOpen;
            NativeMenuInput(state.gameAlive&&gameFocused);
            if(wasMenuOpen&&!NativeMenuOpen)ReadHudSettings(true);
            bool eligible=state.gameAlive&&(gameFocused||ours)&&!NativeMenuOpen;
            bool shortcuts=eligible&&!editing&&!opening;
            InputDiagnostic("Game="+state.gameAlive+" focus="+gameFocused+" menu="+NativeMenuOpen+" editing="+editing+" opening="+opening+" shortcuts="+shortcuts);
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
                else if(composeGeneration!=state.generation){error="Conversation changed. Close and select her again.";}
            }
            PositionOverlay();
            if(editing||VoiceVisible||HordeVisible||(state.active&&!String.IsNullOrWhiteSpace(DisplayText))){LayoutInput();if(!Visible)Present();else Invalidate();}else Hide();
        }catch(Exception e){InputDiagnostic("Shortcut update failed: "+e.GetType().Name+": "+e.Message);if(DateTime.UtcNow>=inputErrorAt){inputErrorAt=DateTime.UtcNow.AddSeconds(30);HostDiagnostics.Log("Shortcut update",e);}if(!editing)Hide();}
    }
    protected override void WndProc(ref Message m){if(m.Msg==0x21){m.Result=new IntPtr(3);return;}if(m.Msg==0x0312){int k=m.WParam.ToInt32();HostDiagnostics.TryWrite(Path.Combine(runtime,"input-last-key.txt"),DateTime.UtcNow.ToString("o")+" hotkey "+k);if(k==1845){if(editing)EndCompose(false);HostDiagnostics.TryWrite(Path.Combine(runtime,"ui-control.txt"),"native-menu:"+Guid.NewGuid().ToString("N"));return;}if(k==1847||k==1849){ToggleMicrophone(k==1849);return;}if(k==1846||k==1848){if(editing)EndCompose(false);else BeginCompose(k==1848);return;}}base.WndProc(ref m);}
    int S(int value){return (int)Math.Round(value*scale);}
    void PositionOverlay(){
        Rect bounds;var origin=new PointNative();
        if(game==IntPtr.Zero||!GetClientRect(game,out bounds)||!ClientToScreen(game,ref origin))return;
        // Use the visible client area, including when a resolution change leaves
        // the window partly outside the monitor. Never anchor below its edge.
        var client=new Rectangle(origin.X,origin.Y,bounds.Right-bounds.Left,bounds.Bottom-bounds.Top);
        var area=Rectangle.Intersect(client,Screen.FromHandle(game).Bounds);
        LayoutForArea(area);
    }
    void LayoutForArea(Rectangle area){
        if(area.Width<160||area.Height<160)return;
        ApplyScale(Math.Max(.65f,Math.Min(2f,Math.Min(area.Width/1920f,area.Height/1080f))));
        int width=Math.Min(area.Width-S(32),S(!editing&&MinimalVoice&&VoiceVisible?220:!editing&&VoiceVisible&&String.IsNullOrWhiteSpace(DisplayText)?560:760));
        int height=Math.Min(area.Height-S(64),Math.Max(S(1),PanelHeight(width)));
        int bottom=Math.Min((int)Math.Round(area.Height*hudBottomPercent/100.0)+S(40),Math.Max(0,area.Height-height-S(16)));
        SetBounds(area.Left+(area.Width-width)/2,area.Bottom-height-bottom,width,height);
    }
    void ApplyScale(float next){
        if(!Alive||Math.Abs(next-scale)<=0.01f)return;
        scale=next;GameControlFonts.Replace(input,GameFont(18*scale));
    }
    int SubtitleHeight(int width){
        using(var bitmap=new Bitmap(1,1))using(var g=Graphics.FromImage(bitmap))using(var font=GameFont(18)){
            float textHeight=g.MeasureString(DisplayText??"",font,Math.Max(80,(int)(width/scale)-48)).Height;
            return S(42+(int)Math.Ceiling(Math.Max(25,Math.Min(110,textHeight))));
        }
    }
    int VoiceHeight(int width){
        if(!VoiceVisible)return 0;
        if(MinimalVoice)return S(136);
        string transcript=VoiceTranscript;
        if(String.IsNullOrWhiteSpace(transcript))return S(112);
        using(var bitmap=new Bitmap(1,1))using(var g=Graphics.FromImage(bitmap))using(var font=GameFont(12)){
            int lines=(int)Math.Ceiling(g.MeasureString("You: "+transcript,font,Math.Max(80,(int)(width/scale)-48)).Height);
            return S(118+Math.Max(26,lines));
        }
    }
    int PanelHeight(int width){return (editing?S(128):String.IsNullOrWhiteSpace(DisplayText)?0:SubtitleHeight(width))+VoiceHeight(width);}
    protected override bool ProcessCmdKey(ref Message msg,Keys keyData){
        if(editing&&keyData==Keys.Enter){SubmitFromKey();return true;}
        if(editing&&keyData==Keys.Escape){EndCompose(false);return true;}
        return base.ProcessCmdKey(ref msg,keyData);
    }
    async void SubmitFromKey(){await Submit();}
    void LayoutInput(){int bottom=Height-VoiceHeight(Width);input.SetBounds(S(27),bottom-S(70),Math.Max(S(40),Width-S(54)),S(30));}
    void SetEditing(bool value){
        if(!Alive)return;
        if(editing!=value&&Visible)Hide();
        editing=value;input.Visible=value;
        ApplyHudStyle();
        if(!preview){int style=GetWindowLong(Handle,-20);SetWindowLong(Handle,-20,value?(style|0x08000000)&~0x20:style|(0x08000000|0x20));}
        Height=Math.Max(S(67),PanelHeight(Width));LayoutInput();Invalidate();
        if(!preview){PositionOverlay();LayoutInput();}
        if(!value&&!VoiceVisible&&!HordeVisible&&String.IsNullOrWhiteSpace(DisplayText))Hide();
    }
    async void BeginCompose(bool group){
        if(!Alive||sending||opening||editing)return;opening=true;error="";
        Hide();ReadHudSettings(true);
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
            ReadHudSettings(true);SetEditing(true);Present();
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
        Hide();ReadHudSettings(true);
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
            long micGeneration=state.generation;
            using(var client=new WebClient()){
                client.Headers["Content-Type"]="application/json";client.Headers["x-bridge-token"]=token;
                await client.UploadStringTaskAsync("http://127.0.0.1:32123/microphone","POST",json.Serialize(new{generation=micGeneration,enabled=!turnOff}));
            }
            // HTTP acceptance comes before the next overlay snapshot. Keep the
            // pending indicator until that snapshot acknowledges our request;
            // requested-but-not-on then stays Connecting until capture is live.
            bool acknowledged=false;
            for(int i=0;i<20;i++){
                if(!Alive)return;
                try{
                    var next=json.Deserialize<DialogueState>(ReadShared(Path.Combine(runtime,"overlay.json")));
                    if(next.generation!=micGeneration||!next.active){error="Conversation changed. Select a character and try again.";break;}
                    if(next.microphoneRequested==!turnOff){state=next;acknowledged=true;break;}
                }catch(IOException){}catch(ArgumentException){}
                await Task.Delay(100);
            }
            if(!acknowledged&&error=="")error="Microphone request was not confirmed. Press "+VoiceKey+" to try again.";
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
        sending=true;input.Enabled=false;
        try{
            using(var client=new WebClient()){
                client.Encoding=System.Text.Encoding.UTF8;client.Headers["Content-Type"]="application/json";client.Headers["x-bridge-token"]=token;
                await client.UploadStringTaskAsync("http://127.0.0.1:32123/text","POST",json.Serialize(new{id=Guid.NewGuid().ToString("N"),generation=composeGeneration,text=text}));
            }
            if(!Alive)return;
            sending=false;input.Enabled=true;EndCompose(true);
        }catch(WebException e){error="Message could not be sent. Check the conversation and try again.";if(e.Response!=null)using(var r=new StreamReader(e.Response.GetResponseStream()))error=r.ReadToEnd();}
        catch{error="The connection is unavailable. Try again shortly.";}
        finally{sending=false;if(Alive){input.Enabled=true;Invalidate();}}
    }
    string Speaker(){if(!String.IsNullOrEmpty(state.name))return state.name.ToUpperInvariant();if(String.IsNullOrEmpty(state.actor))return "ANCA";var name=state.actor.Substring(state.actor.LastIndexOf('.')+1);return Regex.Replace(name,"_[0-9]+$","").Replace('_',' ').ToUpperInvariant();}
    void HudText(Graphics g,string text,Font font,Brush brush,RectangleF bounds,StringFormat format){
        if(!ClearBackground){g.DrawString(text,font,brush,bounds,format);return;}
        // Keep subtitles legible over bright scenery without covering the game.
        using(var path=new GraphicsPath())using(var outline=new Pen(Color.FromArgb(16,18,16),2.5f){LineJoin=LineJoin.Round}){
            // All HUD fonts use pixel units. SizeInPoints depends on system DPI
            // and shrinks this path on scaled displays if converted using 96.
            float em=font.Unit==GraphicsUnit.Pixel?font.Size:font.SizeInPoints*g.DpiY/72f;
            path.AddString(text,font.FontFamily,(int)font.Style,em,bounds,format);
            g.DrawPath(outline,path);g.FillPath(brush,path);
        }
    }
    string MicrophonePhase {
        get {
            if(micBusy)return micStopping?"finishing":"connecting";
            if(VoiceFailed||VoiceNoticeVisible)return "error";
            if(state.microphoneRequested&&!state.microphoneOn)return "connecting";
            if(state.microphoneOn&&!state.microphoneRequested)return "finishing";
            return state.microphoneSilent?"quiet":"listening";
        }
    }
    string MicrophoneLabel {
        get {switch(MicrophonePhase){case "finishing":return "Sending";case "connecting":return "Connecting";case "error":return "Mic unavailable";case "quiet":return "No input signal";default:return "Listening";}}
    }
    void Diamond(Graphics g,float x,float y,float radius,Color colour){
        using(var brush=new SolidBrush(colour))g.FillPolygon(brush,new[]{new PointF(x,y-radius),new PointF(x+radius,y),new PointF(x,y+radius),new PointF(x-radius,y)});
    }
    void Ornament(Graphics g,float left,float right,float y){
        if(right-left<12)return;
        using(var shadow=new Pen(Color.FromArgb(14,16,14),3))using(var line=new Pen(gold,1)){
            g.DrawLine(shadow,left,y,right,y);g.DrawLine(line,left,y,right,y);
        }
        Diamond(g,left,y,2,gold);Diamond(g,right,y,2,gold);
    }
    void DrawMicRing(Graphics g,float x,float y){
        string phase=MicrophonePhase;bool warning=phase=="error"||phase=="quiet";
        Color accent=warning?Color.FromArgb(232,167,108):phase=="listening"?Color.FromArgb(190,219,188):ink;
        float level=preview?(float)state.microphoneLevel:voiceMeter;
        using(var shadow=new Pen(Color.FromArgb(14,16,14),4.5f))using(var rim=new Pen(gold,1.1f))using(var voice=new Pen(accent,2){StartCap=LineCap.Round,EndCap=LineCap.Round}){
            g.DrawEllipse(shadow,x-29,y-29,58,58);g.DrawEllipse(rim,x-29,y-29,58,58);
            // Broken concentric arcs echo the game's brass ornamentation. Only
            // voice amplitude changes their length; no extra animation timer.
            float sweep=phase=="listening"?25+Math.Max(0,Math.Min(1,level))*110:phase=="finishing"||phase=="connecting"?65:35;
            float angle=phase=="finishing"||phase=="connecting"?(float)(hudClock.Elapsed.TotalSeconds*80%360):-90;
            g.DrawArc(shadow,x-34,y-34,68,68,angle,sweep);g.DrawArc(voice,x-34,y-34,68,68,angle,sweep);
            g.DrawArc(shadow,x-34,y-34,68,68,angle+180,sweep);g.DrawArc(voice,x-34,y-34,68,68,angle+180,sweep);
            using(var capsule=new GraphicsPath()){
                capsule.AddArc(x-5,y-15,10,10,180,180);capsule.AddArc(x-5,y-6,10,10,0,180);capsule.CloseFigure();
                g.DrawPath(shadow,capsule);g.DrawPath(voice,capsule);
            }
            g.DrawArc(shadow,x-10,y-9,20,20,0,180);g.DrawArc(voice,x-10,y-9,20,20,0,180);
            g.DrawLine(shadow,x,y+11,x,y+17);g.DrawLine(voice,x,y+11,x,y+17);
            g.DrawLine(shadow,x-6,y+17,x+6,y+17);g.DrawLine(voice,x-6,y+17,x+6,y+17);
            if(warning){g.DrawLine(shadow,x-17,y+17,x+17,y-17);g.DrawLine(voice,x-17,y+17,x+17,y-17);}
        }
        Diamond(g,x-41,y,2,gold);Diamond(g,x+41,y,2,gold);
    }
    void DrawMicrophone(Graphics g,int width,int top){
        DrawMicRing(g,width/2f,top+45);
        string phase=MicrophonePhase;
        string key=phase=="finishing"||phase=="connecting"?"":VoiceKey+(phase=="error"?" · RETRY":" · FINISH");
        using(var label=GameFont(12))using(var hint=GameFont(10))using(var light=new SolidBrush(ink))using(var brass=new SolidBrush(gold))using(var format=new StringFormat{Alignment=StringAlignment.Center}){
            HudText(g,MicrophoneLabel,label,light,new RectangleF(4,top+85,width-8,24),format);
            HudText(g,key,hint,brass,new RectangleF(4,top+109,width-8,20),format);
        }
    }
    protected override void OnPaint(PaintEventArgs e){
        base.OnPaint(e);var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;g.ScaleTransform(scale,scale);int w=(int)(Width/scale),h=(int)(Height/scale);
        var logical=new Rectangle(0,0,w,h);
        int composerBottom=h-(int)(VoiceHeight(Width)/scale);
        if(!ClearBackground){
            using(var gradient=new LinearGradientBrush(logical,Color.FromArgb(28,29,24),panel,90))g.FillRectangle(gradient,logical);
            using(var pen=new Pen(gold,1))g.DrawRectangle(pen,0,0,w-1,h-1);
        }
        if(editing){
            // Open, lightly ornamented entry line instead of stacked rectangles.
            Ornament(g,25,w-25,composerBottom-39);
            using(var pen=new Pen(gold,1)){g.DrawLine(pen,25,composerBottom-47,25,composerBottom-39);g.DrawLine(pen,w-25,composerBottom-47,w-25,composerBottom-39);}
        }
        using(var title=GameFont(13))using(var body=GameFont(18))using(var hint=GameFont(12))using(var light=new SolidBrush(ink))using(var brass=new SolidBrush(gold))using(var format=new StringFormat{Alignment=StringAlignment.Center,LineAlignment=StringAlignment.Near,Trimming=StringTrimming.EllipsisWord}){
            if(!String.IsNullOrWhiteSpace(DisplayText)||editing){
                string heading=HordeVisible?"HORDE":(state.mode=="group"?"GROUP · ":"")+Speaker();
                float half=Math.Min(w/2-45,g.MeasureString(heading,title).Width/2+18);
                Ornament(g,Math.Max(24,w/2-half-70),w/2-half,18);Ornament(g,w/2+half,Math.Min(w-24,w/2+half+70),18);
                HudText(g,heading,title,brass,new RectangleF(24,8,w-48,22),format);
                if(!editing)HudText(g,DisplayText,body,light,new RectangleF(24,32,w-48,h-39-(int)(VoiceHeight(Width)/scale)),format);
            }
            string footer=editing?(String.IsNullOrEmpty(error)?"ENTER  SEND     ·     ESC  RETURN":error):"";
            if(editing)HudText(g,footer,hint,brass,new RectangleF(28,composerBottom-30,w-56,24),format);
            if(VoiceVisible){
                int voiceHeight=(int)(VoiceHeight(Width)/scale);int top=h-voiceHeight;
                if(MinimalVoice){DrawMicrophone(g,w,top);return;}
                if(top>0)Ornament(g,w/2-40,w/2+40,top+1);
                DrawMicRing(g,53,top+52);
                string phase=MicrophonePhase;
                string instruction=phase=="listening"?"Press "+VoiceKey+" again to send":phase=="quiet"?"Check your microphone · "+VoiceKey+" to finish":phase=="finishing"?"Finishing your message":phase=="connecting"?"Getting your conversation ready":VoiceNoticeVisible?voiceNotice:"Check your Windows microphone";
                using(var left=new StringFormat{Alignment=StringAlignment.Near,Trimming=StringTrimming.EllipsisWord}){
                    HudText(g,MicrophoneLabel,body,light,new RectangleF(108,top+24,w-132,30),left);
                    HudText(g,instruction,hint,brass,new RectangleF(108,top+62,w-132,40),left);
                }
                if(!String.IsNullOrWhiteSpace(VoiceTranscript)){
                    HudText(g,"You: "+VoiceTranscript,hint,light,new RectangleF(24,top+118,w-48,voiceHeight-118),format);
                }
            }
        }
    }
    public static void RenderPreview(string path){using(var form=new DialogueOverlay(Path.GetDirectoryName(path),"",true)){
        form.state=new DialogueState{actor="Anca_241",text="I have not forgotten what you did for us. Tell me, what brings you here?",active=true};
        form.SetEditing(true);form.input.Text="Tell me more about this place.";
        form.CreateControl();using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);form.input.DrawToBitmap(bitmap,form.input.Bounds);bitmap.Save(path);}
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
        form.hideChatBoxes=true;form.ApplyHudStyle();
        form.state=new DialogueState{active=true,text="This subtitle must be hidden.",microphoneTranscript="This transcript must be hidden.",microphoneRequested=true,microphoneOn=true,microphoneLevel=.65};
        form.Width=form.S(220);form.Height=form.PanelHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.MakeTransparent(form.clearColour);bitmap.Save(path+".minimal.png");}
        foreach(string phase in new[]{"quiet","error","finishing","connecting"}){
            form.state.microphoneSilent=phase=="quiet";form.state.microphoneOn=phase!="error";
            form.state.microphoneRequested=phase!="finishing";
            form.state.microphoneStatus=phase=="error"?"Microphone unavailable":"";
            form.micBusy=phase=="connecting";
            using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.MakeTransparent(form.clearColour);bitmap.Save(path+".minimal-"+phase+".png");}
        }
        form.micBusy=false;form.state.microphoneSilent=false;form.state.microphoneStatus="";
        form.state.microphoneRequested=true;form.state.microphoneOn=false;
        if(!form.VoiceVisible||form.MicrophonePhase!="connecting")throw new Exception("Pending microphone disappeared before capture was ready");
        form.state.microphoneOn=true;
        if(!form.VoiceVisible||form.MicrophonePhase!="listening")throw new Exception("Ready microphone did not enter Listening");
        form.state.microphoneOn=false;form.state.microphoneRequested=false;
        if(form.DisplayText!=""||form.VoiceVisible||form.PanelHeight(form.Width)!=0)throw new Exception("Minimal HUD retained conversation text after recording");
        foreach(bool hidden in new[]{false,true})foreach(bool subtitles in new[]{false,true}){
            form.hideChatBoxes=hidden;form.showNpcSubtitles=subtitles;
            if((form.DisplayText!="")!=(!hidden&&subtitles))throw new Exception("Chat/subtitle visibility precedence failed");
            form.state.microphoneOn=true;form.state.microphoneRequested=true;
            if(!form.VoiceVisible||form.MinimalVoice!=hidden)throw new Exception("HUD toggle changed voice availability");
        }
        form.hideChatBoxes=true;form.showNpcSubtitles=true;form.state.microphoneOn=false;form.state.microphoneRequested=false;
        form.state.text="";form.state.hordeText="Next wave in 8 seconds";
        if(!form.HordeVisible||form.DisplayText!=form.state.hordeText)throw new Exception("Minimal HUD hid the Horde countdown");
        form.SetEditing(true);if(!form.editing)throw new Exception("Minimal HUD disabled deliberate text entry");
        form.Width=form.S(760);form.Height=form.PanelHeight(form.Width);form.LayoutInput();
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".minimal-composer.png");}
        form.SetEditing(false);form.hideChatBoxes=false;form.transparentHud=false;form.ApplyHudStyle();
        form.state=new DialogueState{active=true,text="The original panel remains available in Settings.",name="Anca"};form.Height=form.PanelHeight(form.Width);
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.Save(path+".panel.png");}
        form.transparentHud=true;form.ApplyScale(4f/3f);form.SetEditing(true);form.Width=form.S(760);form.Height=form.PanelHeight(form.Width);form.LayoutInput();
        using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.MakeTransparent(form.clearColour);bitmap.Save(path+".1600-composer.png");}
        form.state.microphoneOn=true;form.state.microphoneRequested=true;form.state.microphoneTranscript="Tell me about the people we met on the road and what happened in the valley.";
        foreach(var area in new[]{new Rectangle(0,0,1280,720),new Rectangle(0,0,1920,1080),new Rectangle(0,0,2560,1440),new Rectangle(0,0,2560,1600),new Rectangle(0,0,3440,1440),new Rectangle(0,0,3840,2160),new Rectangle(-2560,0,2560,1600)}){
            form.LayoutForArea(area);form.LayoutInput();
            if(!area.Contains(form.Bounds)||!form.ClientRectangle.Contains(form.input.Bounds))throw new Exception("HUD exceeds viewport or clips input at "+area);
            using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);bitmap.MakeTransparent(form.clearColour);bitmap.Save(path+"."+area.Width+"x"+area.Height+".png");}
            foreach(int offset in new[]{0,40}){
                form.hudBottomPercent=offset;form.LayoutForArea(area);form.LayoutInput();
                if(!area.Contains(form.Bounds)||!form.ClientRectangle.Contains(form.input.Bounds))throw new Exception("HUD bottom offset clips controls at "+area);
            }
            form.hudBottomPercent=0;
        }
    }}
    public static void VerifyInput(string path){
        string dir=Path.Combine(Path.GetTempPath(),"DawnwalkerComposerTest-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(dir);
        using(var form=new DialogueOverlay(dir,"",true)){
            File.WriteAllText(Path.Combine(dir,"mod-directory.txt"),dir);
            var culture=System.Threading.Thread.CurrentThread.CurrentCulture;
            try{
                System.Threading.Thread.CurrentThread.CurrentCulture=new System.Globalization.CultureInfo("fr-FR");
                foreach(string offset in new[]{"28","28.0"}){
                    File.WriteAllText(Path.Combine(dir,"config.ini"),"[Companions]\r\nTransparentChatHud = 1.0\r\nHideChatBoxes = 0.0\r\nShowNpcSubtitles = 1.0\r\nChatHudBottomOffset = "+offset+" ; slider value\r\n");
                    form.ReadHudSettings(true);
                    if(form.hudBottomPercent!=28||!form.transparentHud||form.hideChatBoxes||!form.showNpcSubtitles)throw new Exception("HUD settings did not accept the slider format");
                    form.SetEditing(true);form.LayoutForArea(new Rectangle(0,0,2560,1600));int raised=form.Bottom;
                    File.WriteAllText(Path.Combine(dir,"config.ini"),"[Companions]\nChatHudBottomOffset = 0.0\n");form.ReadHudSettings(true);form.LayoutForArea(new Rectangle(0,0,2560,1600));
                    if(form.Bottom-raised!=448)throw new Exception("HUD offset did not move the window by 28% of screen height");
                }
            }finally{System.Threading.Thread.CurrentThread.CurrentCulture=culture;}
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
            File.WriteAllText(path,"PASS: integer/decimal HUD settings in comma-decimal locale; saved offset moves actual window bounds; typing, replacement, backspace, navigation, delete, Enter and Escape; no game input or foreground activation.");
        }
    }
    public static void VerifyFonts(string directory,string output){
        using(var form=new DialogueOverlay(Path.Combine(directory,"runtime"),"",true)){
            if(form.gameFonts.Families.Length==0)throw new Exception("Verification must load the bundled game-style font");
            var original=form.input.Font;
            GameControlFonts.Replace(form.input,form.GameFont(18));
            if(!Object.ReferenceEquals(form.input.Font,original))throw new Exception("Equal font should retain the existing instance");
            foreach(float next in new[]{1.1f,1f,16f/15f,.667f,1.25f,1.333333f,2f,.8f,16f/15f}){
                form.ApplyScale(next);form.SetEditing(true);
                // Force the actual HWND path that the fallback-font test missed.
                var inputHandle=form.input.Handle;
                if(inputHandle==IntPtr.Zero)throw new Exception("Composer HWND unavailable");
                using(var bitmap=new Bitmap(form.Width,form.Height)){form.DrawToBitmap(bitmap,form.ClientRectangle);}
                form.SetEditing(false);
            }
            form.Dispose();form.EndCompose(false);form.SetEditing(true);
            if(form.IsHandleCreated)throw new Exception("Disposed composer recreated its HWND");
        }
        CompanionPanel.VerifyFonts(directory);
        File.WriteAllText(output,"PASS: bundled Afacad font; equal-size replacement; real textbox HWND creation and drawing at nine scales; companion-panel font resizing; disposed composer stays closed. No game input or microphone capture.");
    }
}
