using System;
using System.Collections.Generic;
using System.IO;
using System.Windows.Forms;

// The native Controls page and this input router read the same portable file.
public sealed class ModKeyBindings {
    public static readonly string[] Actions={"Camera","Menu","SingleText","SingleVoice","GroupText","GroupVoice"};
    readonly Dictionary<string,Keys> keys=new Dictionary<string,Keys>{{"Camera",Keys.F4},{"Menu",Keys.F5},{"SingleText",Keys.F6},{"SingleVoice",Keys.F7},{"GroupText",Keys.F8},{"GroupVoice",Keys.F9}};
    string previous;DateTime nextRead;
    public string Error {get;private set;}
    public Keys this[string action] {get{return keys[action];}}
    public string Label(string action){return Name(keys[action]);}
    public static string Name(Keys key){if(key>=Keys.D0&&key<=Keys.D9)return ((int)key-(int)Keys.D0).ToString();if(key==Keys.Enter)return "Enter";if(key==Keys.Prior)return "PageUp";if(key==Keys.Next)return "PageDown";return key.ToString();}
    public static bool Parse(string name,out Keys key){
        key=Keys.None;
        if(name.Length==1&&name[0]>='0'&&name[0]<='9'){key=(Keys)((int)Keys.D0+name[0]-'0');return true;}
        // F12 is reserved by Windows for debuggers (RegisterHotKey documentation).
        if(!Enum.TryParse<Keys>(name,false,out key))return false;
        return (key>=Keys.A&&key<=Keys.Z)||(key>=Keys.F1&&key<=Keys.F11)||key==Keys.Home||key==Keys.End||key==Keys.PageUp||key==Keys.PageDown||key==Keys.Insert||key==Keys.Delete;
    }
    public bool Read(string runtime){
        if(DateTime.UtcNow<nextRead)return false;nextRead=DateTime.UtcNow.AddMilliseconds(500);
        try{
            var directory=Path.GetFullPath(Path.Combine(runtime,"../mod"));
            var pointer=Path.Combine(runtime,"mod-directory.txt");if(File.Exists(pointer))directory=File.ReadAllText(pointer).Trim();
            var path=Path.Combine(directory,"keybindings.ini");if(!File.Exists(path))return false;
            string source;using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var r=new StreamReader(f))source=r.ReadToEnd();
            if(source==previous)return false;
            var candidate=new Dictionary<string,Keys>();var seen=new HashSet<Keys>();
            foreach(var line in source.Split('\n')){var split=line.Trim().Split('=');if(split.Length!=2||!keys.ContainsKey(split[0].Trim()))continue;Keys key;if(!Parse(split[1].Trim(),out key))throw new FormatException("Unsupported key");candidate[split[0].Trim()]=key;}
            if(!candidate.ContainsKey("Camera"))foreach(var fallback in new[]{Keys.F4,Keys.F10,Keys.F11,Keys.F3,Keys.F2,Keys.F1})if(!candidate.ContainsValue(fallback)){candidate["Camera"]=fallback;break;}
            foreach(var action in Actions)if(!candidate.ContainsKey(action)||!seen.Add(candidate[action]))throw new FormatException("Missing or duplicate key");
            bool changed=false;foreach(var action in Actions){changed|=keys[action]!=candidate[action];keys[action]=candidate[action];}previous=source;Error=null;return changed;
        }catch(Exception e){Error="Key bindings unchanged: "+e.Message;return false;}
    }
}
