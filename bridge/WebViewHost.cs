using System;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Web.Script.Serialization;
using System.Collections.Generic;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

public sealed class ConvaiHost : Form {
    [System.Runtime.InteropServices.DllImport("user32.dll")] static extern bool SetProcessDPIAware();
    readonly string root=Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"..",".."));
    WebView2 view; Process server;HostServerJob serverJob; System.Windows.Forms.Timer timer;DialogueOverlay dialogue;CompanionPanel companions;
    DateTime started=DateTime.UtcNow,revision;SupportReport supportReport;
    string Runtime(string name){return Path.Combine(root,"runtime",name);}
    static void NoLinks(string path){
        for(var dir=new DirectoryInfo(path);dir!=null;dir=dir.Parent)
            if(dir.Exists&&(dir.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Browser profile path contains a directory link");
    }
    static void CopyProfile(string source,string destination){
        NoLinks(source);Directory.CreateDirectory(destination);NoLinks(destination);
        foreach(var file in Directory.GetFiles(source)){
            if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new IOException("Browser profile contains a file link");
            File.Copy(file,Path.Combine(destination,Path.GetFileName(file)),true);
        }
        foreach(var dir in Directory.GetDirectories(source))CopyProfile(dir,Path.Combine(destination,Path.GetFileName(dir)));
    }
    static void CheckProfileTree(string path){
        NoLinks(path);
        foreach(var file in Directory.GetFiles(path))
            if((File.GetAttributes(file)&FileAttributes.ReparsePoint)!=0)throw new IOException("Browser profile contains a file link");
        foreach(var dir in Directory.GetDirectories(path))CheckProfileTree(dir);
    }
    async Task<string> ProfileDirectory(){
        string key;
        using(var hash=System.Security.Cryptography.SHA256.Create())
            key=BitConverter.ToString(hash.ComputeHash(System.Text.Encoding.UTF8.GetBytes(root.ToUpperInvariant()))).Replace("-","").Substring(0,24);
        var parent=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"LLMNPCCompanions","WebView");
        var destination=Path.Combine(parent,key);
        var old=Path.GetFullPath(Runtime("webview-profile"));
        // Keep browser identity/session storage outside UE4SS's recursive mod scan.
        // Copy then promote on the destination volume, so cross-drive installs
        // work and a failed migration cannot start with half a profile.
        var expected=Path.GetFullPath(Path.Combine(root,"runtime"))+Path.DirectorySeparatorChar;
        if(!old.StartsWith(expected,StringComparison.OrdinalIgnoreCase)||Path.GetFileName(old)!="webview-profile")throw new IOException("Invalid legacy browser profile location");
        NoLinks(parent);Directory.CreateDirectory(parent);
        for(int attempt=0;attempt<6;attempt++){
            try{
                if(Directory.Exists(old)){
                    NoLinks(old);NoLinks(destination);
                    if(!Directory.Exists(destination)){
                        var staging=destination+".migrating";
                        CopyProfile(old,staging);
                        Directory.Move(staging,destination);
                    }
                    // A completed destination is authoritative on retry. Never
                    // overwrite it from a partially removed legacy directory.
                    CheckProfileTree(old);Directory.Delete(old,true);
                }
                Directory.CreateDirectory(destination);NoLinks(destination);
                return destination;
            }catch(IOException){if(attempt==5)throw;}
            await Task.Delay(1000);
        }
        throw new IOException("Browser profile migration did not finish");
    }
    protected override bool ShowWithoutActivation {get{return true;}}
    public ConvaiHost(){
        ShowInTaskbar=false;Opacity=0;Width=8;Height=8;FormBorderStyle=FormBorderStyle.None;
        StartPosition=FormStartPosition.Manual;Left=-32000;Top=-32000;
        Shown+=async (s,e)=>await Initialize();
        FormClosed+=(s,e)=>{
            HostDiagnostics.ReleaseInput();
            if(timer!=null)timer.Dispose();if(serverJob!=null)serverJob.Dispose();
            try{if(server!=null&&!server.HasExited)server.Kill();}catch(Exception error){HostDiagnostics.Log("Server cleanup",error);}
            foreach(var form in new Form[]{companions,dialogue})try{if(form!=null)form.Close();}catch(Exception error){HostDiagnostics.Log("Overlay cleanup",error);}
            try{if(view!=null)view.Dispose();}catch(Exception error){HostDiagnostics.Log("WebView cleanup",error);}
        };
    }
    async Task Initialize(){
        try{
            var node=File.ReadAllText(Runtime("node-path.txt")).Trim();
            var start=new ProcessStartInfo(node,"\""+Path.Combine(root,"bridge","server.mjs")+"\"");
            using(var defaults=System.Reflection.Assembly.GetExecutingAssembly().GetManifestResourceStream("DawnwalkerConvai.SharedDefaults.json")){
                if(defaults!=null)using(var reader=new StreamReader(defaults))start.EnvironmentVariables["DAWNWALKER_DEFAULT_CONFIG"]=reader.ReadToEnd();
            }
            start.UseShellExecute=false;start.CreateNoWindow=true;start.WorkingDirectory=root;
            start.RedirectStandardOutput=true;start.RedirectStandardError=true;
            serverJob=new HostServerJob();server=Process.Start(start);serverJob.Own(server);
            server.OutputDataReceived+=(s,e)=>{};
            server.ErrorDataReceived+=(s,e)=>{if(e.Data!=null)try{File.AppendAllText(Runtime("webview-errors.log"),e.Data+Environment.NewLine);}catch(Exception error){HostDiagnostics.Log("Bridge log write",error);}};
            server.BeginOutputReadLine();server.BeginErrorReadLine();
            bool ready=false;string sessionJson="";
            for(int i=0;i<40;i++){
                if(server.HasExited)throw new Exception("Local bridge exited");
                try{using(var client=new WebClient()){sessionJson=await client.DownloadStringTaskAsync("http://127.0.0.1:32123/session");}ready=true;break;}catch{}
                await Task.Delay(100);
            }
            if(!ready)throw new Exception("Local bridge unavailable");
            var options=new CoreWebView2EnvironmentOptions();
            options.AdditionalBrowserArguments="--autoplay-policy=no-user-gesture-required --disable-background-timer-throttling --disable-renderer-backgrounding";
            var profile=await ProfileDirectory();
            var environment=await CoreWebView2Environment.CreateAsync(null,profile,options);
            view=new WebView2();view.Dock=DockStyle.Fill;Controls.Add(view);
            await view.EnsureCoreWebView2Async(environment);
            view.CoreWebView2.PermissionRequested+=(s,e)=>{
                // Capture is requested only by an explicit F7/F9 command. Camera and
                // other permission kinds remain denied; startup never opens a mic.
                e.State=e.PermissionKind==CoreWebView2PermissionKind.Microphone&&e.Uri.StartsWith("http://127.0.0.1:32123/",StringComparison.Ordinal)?CoreWebView2PermissionState.Allow:CoreWebView2PermissionState.Deny;
            };
            view.CoreWebView2.NewWindowRequested+=(s,e)=>{e.Handled=true;};
            view.CoreWebView2.NavigationStarting+=(s,e)=>{if(!e.Uri.StartsWith("http://127.0.0.1:32123/",StringComparison.Ordinal))e.Cancel=true;};
            view.CoreWebView2.ProcessFailed+=(s,e)=>{File.WriteAllText(Runtime("background-status.txt"),"WebView runtime failed; automatic restart pending");Close();};
            view.CoreWebView2.Navigate("http://127.0.0.1:32123/?auto=1");
            var auth=new JavaScriptSerializer().Deserialize<Dictionary<string,string>>(sessionJson)["token"];
            dialogue=new DialogueOverlay(Path.Combine(root,"runtime"),auth);
            companions=new CompanionPanel(Path.Combine(root,"runtime"),auth,dialogue.CloseForCompanions);
            Hide();
            File.WriteAllText(Runtime("background-host.pid"),Process.GetCurrentProcess().Id.ToString());
            File.WriteAllText(Runtime("background-status.txt"),"WebView2 v0.30.7 ready: native companion menu, configurable shortcuts and support report.");
            supportReport=new SupportReport(Path.Combine(root,"runtime"));
            revision=File.GetLastWriteTimeUtc(Path.Combine(root,"bridge","public","client.js"));
            timer=new System.Windows.Forms.Timer();timer.Interval=1000;
            timer.Tick+=(s,e)=>{
                try{
                    if(HostGamePermissions.NeedsGameLaunch()){
                        HostDiagnostics.TryWrite(Runtime("background-status.txt"),"Matching game permissions: waiting for the in-game launcher.");
                        HostDiagnostics.TryWrite(Runtime("background-restart.request"),"game-permissions");
                        HostDiagnostics.ReleaseInput();Close();return;
                    }
                    supportReport.Poll();
                    File.WriteAllText(Runtime("background-heartbeat.txt"),DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
                    long heartbeat=0;long.TryParse(File.ReadAllText(Runtime("game-heartbeat.txt")),out heartbeat);
                    if(server.HasExited||(DateTime.UtcNow-started).TotalSeconds>60&&DateTimeOffset.UtcNow.ToUnixTimeSeconds()-heartbeat>60){Close();return;}
                    var next=File.GetLastWriteTimeUtc(Path.Combine(root,"bridge","public","client.js"));
                    if(next!=revision){revision=next;view.CoreWebView2.Reload();}
                }catch{}
            };timer.Start();
        }catch(Exception e){HostDiagnostics.Log("Helper startup",e);try{File.WriteAllText(Runtime("background-status.txt"),"WebView2 startup failed: "+e.Message);}catch{}Close();}
    }
    [STAThread] public static void Main(string[] args){
        SetProcessDPIAware();
        if(args.Length==2&&args[0]=="--verify-fonts"){
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);Application.EnableVisualStyles();
            DialogueOverlay.VerifyFonts(Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../..")),args[1]);return;
        }
        Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
        Application.ThreadException+=(s,e)=>{HostDiagnostics.Log("UI thread exception; restarting helper",e.Exception);HostDiagnostics.ReleaseInput();Application.Exit();};
        AppDomain.CurrentDomain.UnhandledException+=(s,e)=>{HostDiagnostics.Log("Unhandled helper exception",e.ExceptionObject as Exception??new Exception(Convert.ToString(e.ExceptionObject)));HostDiagnostics.ReleaseInput();};
        if(args.Length==2&&args[0]=="--verify-input"){Application.EnableVisualStyles();DialogueOverlay.VerifyInput(args[1]);return;}
        if(args.Length==2&&args[0]=="--preview-ui"){Application.EnableVisualStyles();DialogueOverlay.RenderPreview(args[1]);return;}
        if(args.Length==2&&args[0]=="--preview-companions"){Application.EnableVisualStyles();CompanionPanel.RenderPreview(Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../..")),args[1]);return;}
        bool created;using(var mutex=new Mutex(true,"Local\\DawnwalkerConvaiWebView",out created)){
            if(!created)return;Application.EnableVisualStyles();Application.Run(new ConvaiHost());
        }
    }
}
