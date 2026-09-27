using System;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

// Offline interface strings only. Never translate dialogue or protocol values.
public static class UiLocalization {
    static readonly string[] Codes={"en","zh-CN","zh-TW","es","pt-BR","fr","de","ru","ja","ko"};
    static int index;
    static bool wroteOs;
    public static string Code {get{return Codes[index];}}
    public static bool Cjk {get{return index==1||index==2||index==8||index==9;}}
    public static string Normalize(string raw){
        string value=(raw??"").Replace('_','-').ToLowerInvariant();
        if(value.StartsWith("zh"))return value.Contains("tw")||value.Contains("hk")||value.Contains("hant")?"zh-TW":"zh-CN";
        if(value.StartsWith("pt"))return "pt-BR";
        foreach(string code in Codes)if(value==code.ToLowerInvariant()||value.StartsWith(code.ToLowerInvariant()+"-"))return code;
        return "en";
    }
    static string Read(string path){using(var f=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.ReadWrite))using(var r=new StreamReader(f,Encoding.UTF8))return r.ReadToEnd();}
    public static bool Refresh(string runtime,string source){
        if(!wroteOs){try{File.WriteAllText(Path.Combine(runtime,"os-language.txt"),CultureInfo.CurrentUICulture.Name,new UTF8Encoding(false));wroteOs=true;}catch(IOException){}catch(UnauthorizedAccessException){}}
        int selected=0;double raw;
        var match=Regex.Match(source??"",@"(?m)^\s*UiLanguage\s*=\s*([0-9]+(?:\.0+)?)\s*(?:;[^\r\n]*)?\r?$");
        if(match.Success&&double.TryParse(match.Groups[1].Value,NumberStyles.Float,CultureInfo.InvariantCulture,out raw)&&raw>=0&&raw<=Codes.Length)selected=(int)raw;
        string code=selected>0?Codes[selected-1]:Normalize(CultureInfo.CurrentUICulture.Name);
        if(selected==0){try{code=Normalize(Read(Path.Combine(runtime,"ui-language.txt")).Trim());}catch(IOException){}catch(UnauthorizedAccessException){}}
        int next=Array.IndexOf(Codes,code);if(next<0)next=0;
        if(next==index)return false;index=next;return true;
    }
    public static string Text(string source){
        if(source==null)return "";
        string[] row;return index>0&&UiStrings.Rows.TryGetValue(source,out row)?row[index-1]:source;
    }
    public static string Format(string source,params object[] values){return String.Format(CultureInfo.CurrentCulture,Text(source),values);}
    public static string HordeCountdown(string source){
        var match=Regex.Match(source??"",@"^Level (\d+) / (\d+) begins in (\d+) s$");
        return match.Success?Format("Level {0} / {1} begins in {2} s",match.Groups[1].Value,match.Groups[2].Value,match.Groups[3].Value):source;
    }
    public static Font CjkFont(float pixels,FontStyle style){
        string name=index==1?"Microsoft YaHei UI":index==2?"Microsoft JhengHei UI":index==8?"Yu Gothic UI":"Malgun Gothic";
        return new Font(name,pixels,style,GraphicsUnit.Pixel);
    }
    public static bool NeedsFontFallback(string value){
        if(value==null)return false;
        foreach(char c in value)if(c>0x2ff)return true;
        return false;
    }
}
