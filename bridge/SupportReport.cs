using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

// Explicit, bounded diagnostics only. Never enumerate user data or read config,
// conversation history, browser storage, microphone recordings or environment secrets.
public sealed class SupportReport {
    readonly string runtime;
    string handled;
    bool busy;
    public SupportReport(string directory){
        runtime=directory;
        handled=ReadSmall(Path.Combine(runtime,"support-copy.request"));
    }
    static string ReadSmall(string path){try{return Tail(path,256).Trim();}catch{return "";}}
    public static string Tail(string path,int limit){
        using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){
            bool clipped=file.Length>limit;file.Position=Math.Max(0,file.Length-limit);
            var bytes=new byte[limit];int count=0,n;
            while(count<limit&&(n=file.Read(bytes,count,limit-count))>0)count+=n;
            string value=Encoding.UTF8.GetString(bytes,0,count);
            if(clipped){int line=value.IndexOf('\n');value=line>=0?value.Substring(line+1):"[long line omitted]";}
            return value;
        }
    }
    public static string Sanitize(string value){
        value=Regex.Replace(value,@"(?im)^.*\b(transcript|utterance|prompt|authorization|cookie|endUserId|sessionId)\b.*$","[private field omitted]");
        value=Regex.Replace(value,@"(?im)^.*(?:api[_ -]?key|access[_ -]?token|refresh[_ -]?token|bearer)\b.*$","[credential field omitted]");
        value=Regex.Replace(value,@"https?://[^\s<>]+","<url>",RegexOptions.IgnoreCase);
        value=Regex.Replace(value,@"\b[A-Fa-f0-9]{32,}\b","<redacted>");
        value=Regex.Replace(value,@"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+","<redacted>");
        // Paths may contain spaces; removing the rest of the line is safer than
        // retaining a partial local installation path in a public bug report.
        value=Regex.Replace(value,@"(?im)(?:[A-Z]:[\\/]|\\\\)[^\r\n]*","<local path>");
        if(!String.IsNullOrEmpty(Environment.UserName))value=Regex.Replace(value,Regex.Escape(Environment.UserName),"<user>",RegexOptions.IgnoreCase);
        return value.Trim();
    }
    public static string Build(string directory){
        var report=new StringBuilder("LLM NPC Companions System 0.4 development diagnostic report\r\n");
        report.AppendLine("UTC: "+DateTime.UtcNow.ToString("o"));
        report.AppendLine("Windows: "+Environment.OSVersion.Version+"; 64-bit process: "+Environment.Is64BitProcess);
        report.AppendLine("Recent diagnostic tails only. No chat history, configuration or recordings included.");
        foreach(var name in new[]{"reload-status.txt","horde-status.txt","camera-status.txt","background-status.txt","ui-status.txt","input-status.txt","input-last-key.txt","companion-performance.txt","companion-spawn-diagnostic.txt","spatial-status.txt","helper-errors.log","background-errors.log","webview-errors.log"}){
            report.AppendLine("\r\n--- "+name+" ---");
            try{report.AppendLine(Sanitize(Tail(Path.Combine(directory,name),8192)));}
            catch{report.AppendLine("Unavailable (not created yet or currently locked).");}
        }
        // Bootstrap writes this private locator. Its contents are used only to
        // locate the loader log, never copied into the report itself.
        try{
            string mod=ReadSmall(Path.Combine(directory,"mod-directory.txt"));
            if(Path.IsPathRooted(mod)){
                string log=Tail(Path.GetFullPath(Path.Combine(mod,"../../UE4SS.log")),65536);
                report.AppendLine("\r\n--- UE4SS: recent mod messages ---");
                foreach(var line in log.Split('\n'))if(line.Contains("DawnwalkerConvai")||line.Contains("Dawnwalker Companions"))report.AppendLine(Sanitize(line));
            }
        }catch{report.AppendLine("UE4SS log excerpt unavailable.");}
        return report.ToString();
    }
    public async void Poll(){
        if(busy)return;
        string request=ReadSmall(Path.Combine(runtime,"support-copy.request"));
        if(request==handled||!Regex.IsMatch(request,@"^\d+-\d+-\d+$"))return;
        handled=request;busy=true;
        string message;
        try{
            string report=await Task.Run(()=>{
                string result=Build(runtime);
                File.WriteAllText(Path.Combine(runtime,"support-report.txt"),result,new UTF8Encoding(false));
                return result;
            });
            // Back on the host's STA UI thread. Never collect logs on the game thread.
            try{Clipboard.SetText(report);message="Logs copied. You can paste them into your bug report.";}
            catch{message="Report saved to Payload/runtime/support-report.txt; clipboard is busy.";}
        }catch{message="Could not create the report. Check that the mod folder is writable.";}
        HostDiagnostics.TryWrite(Path.Combine(runtime,"support-copy.result"),request+"\t"+message);
        busy=false;
    }
}
