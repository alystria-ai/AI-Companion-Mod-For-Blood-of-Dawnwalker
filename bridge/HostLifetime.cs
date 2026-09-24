using System;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Windows.Forms;

public static class GameControlFonts {
    // WinForms ignores an equal Font value and keeps the old object. Disposing
    // that old object then breaks ToHfont when a hidden textbox gets its HWND.
    // Callers here own both fonts; never use this for an inherited/shared font.
    public static void Replace(Control control,Font next){
        if(control.IsDisposed||control.Disposing){next.Dispose();return;}
        var old=control.Font;
        if(Object.ReferenceEquals(old,next))return;
        if(old.Equals(next)){next.Dispose();return;}
        control.Font=next;
        if(Object.ReferenceEquals(control.Font,old))next.Dispose();else old.Dispose();
    }
}

public static class HostDiagnostics {
    static readonly object sync=new object();
    static string Runtime {get{return Path.GetFullPath(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"../../runtime"));}}
    public static void Log(string operation,Exception error){
        try{lock(sync){File.AppendAllText(Path.Combine(Runtime,"helper-errors.log"),DateTime.UtcNow.ToString("o")+" "+operation+Environment.NewLine+error+Environment.NewLine);}}catch{}
    }
    public static void ReleaseInput(){
        foreach(var name in new[]{"mic-focus.txt","ui-active.txt","background-heartbeat.txt"})try{File.WriteAllText(Path.Combine(Runtime,name),"0");}catch{}
    }
    public static void TryWrite(string path,string value){try{File.WriteAllText(path,value);}catch(Exception e){Log("UI mailbox write: "+Path.GetFileName(path),e);}}
}
// A helper manually restarted outside an elevated game can have a lower token.
// Windows then withholds keyboard input. Ask the existing in-game launcher to
// recreate the helper; never request elevation or change system/UAC settings.
public static class HostGamePermissions {
    static DateTime nextCheck;
    static bool? ownElevation;
    [DllImport("kernel32.dll")] static extern IntPtr OpenProcess(uint access,bool inherit,int pid);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    [DllImport("advapi32.dll")] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
    [DllImport("advapi32.dll")] static extern bool GetTokenInformation(IntPtr token,int kind,out int value,int length,out int needed);
    static bool? Elevated(int pid){
        IntPtr process=OpenProcess(0x1000,false,pid),token=IntPtr.Zero;
        try{if(process==IntPtr.Zero||!OpenProcessToken(process,8,out token))return null;int value,needed;return GetTokenInformation(token,20,out value,4,out needed)?(bool?)(value!=0):null;}
        finally{if(token!=IntPtr.Zero)CloseHandle(token);if(process!=IntPtr.Zero)CloseHandle(process);}
    }
    public static bool NeedsGameLaunch(){
        if(ownElevation==true)return false;
        if(DateTime.UtcNow<nextCheck)return false;nextCheck=DateTime.UtcNow.AddSeconds(5);
        using(var self=Process.GetCurrentProcess()){
            ownElevation=ownElevation??Elevated(self.Id);
            if(ownElevation!=false)return false;
            foreach(var game in Process.GetProcessesByName("Dawnwalker"))using(game){
                try{if(game.SessionId==self.SessionId&&Elevated(game.Id)==true)return true;}catch{}
            }
        }
        return false;
    }
}
// Closing the host's job handle (including process termination) kills its Node
// child. A dead WinForms/WebView host must not leave the bridge port occupied.
public sealed class HostServerJob : IDisposable {
    [StructLayout(LayoutKind.Sequential)] struct BasicLimit {
        public long ProcessTime,JobTime;public uint Flags;public UIntPtr MinWorkingSet,MaxWorkingSet;
        public uint ActiveProcesses;public UIntPtr Affinity;public uint Priority,Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters {public ulong ReadOperations,WriteOperations,OtherOperations,ReadBytes,WriteBytes,OtherBytes;}
    [StructLayout(LayoutKind.Sequential)] struct ExtendedLimit {
        public BasicLimit Basic;public IoCounters Io;public UIntPtr ProcessMemory,JobMemory,PeakProcessMemory,PeakJobMemory;
    }
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref ExtendedLimit info,uint length);
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    IntPtr handle;
    public HostServerJob(){
        handle=CreateJobObject(IntPtr.Zero,null);if(handle==IntPtr.Zero)throw new Win32Exception();
        var info=new ExtendedLimit();info.Basic.Flags=0x2000;
        if(!SetInformationJobObject(handle,9,ref info,(uint)Marshal.SizeOf(typeof(ExtendedLimit)))){var e=new Win32Exception();Dispose();throw e;}
    }
    public void Own(Process process){if(!AssignProcessToJobObject(handle,process.Handle))throw new Win32Exception();}
    public void Dispose(){if(handle!=IntPtr.Zero){CloseHandle(handle);handle=IntPtr.Zero;}}
}
