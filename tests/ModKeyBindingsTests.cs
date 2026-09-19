using System;using System.IO;using System.Threading;using System.Windows.Forms;
class ModKeyBindingsTests {
 static void Check(bool value,string why){if(!value)throw new Exception(why);}
 static void Main(){
  var temp=Path.Combine(Path.GetTempPath(),"DawnwalkerKeys-"+Guid.NewGuid().ToString("N"));var runtime=Path.Combine(temp,"runtime");var mod=Path.Combine(temp,"mod");Directory.CreateDirectory(runtime);Directory.CreateDirectory(mod);
  try{
   var path=Path.Combine(mod,"keybindings.ini");var original="[Keybindings]\nMenu = F10\nSingleText = K\nSingleVoice = 9\nGroupText = PageUp\nGroupVoice = End\n";File.WriteAllText(path,original);
   var keys=new ModKeyBindings();Check(keys.Read(runtime),"read edited mapping");Check(keys["Menu"]==Keys.F10&&keys.Label("SingleVoice")=="9","canonical mapping");Check(ModKeyBindings.Name(Keys.Return)=="Enter","Enter route");
   foreach(var name in new[]{"Escape","Enter","Up","Ctrl+K","None","F12","F13"}){Keys k;Check(!ModKeyBindings.Parse(name,out k),"reserved "+name);}
   File.WriteAllText(path,original.Replace("GroupVoice = End","GroupVoice = F10"));Thread.Sleep(520);Check(!keys.Read(runtime)&&keys["GroupVoice"]==Keys.End&&keys.Error!=null,"duplicate retains last known good mapping");
   File.WriteAllText(path,"[Keybindings]\nMenu = F2\n");Thread.Sleep(520);Check(!keys.Read(runtime)&&keys["Menu"]==Keys.F10,"partial write retains mapping");
   File.WriteAllText(path,original.Replace("Menu = F10","Menu = Home"));Thread.Sleep(520);Check(keys.Read(runtime)&&keys["Menu"]==Keys.Home&&keys.Error==null,"valid edit recovers");
   Console.WriteLine("PASS: helper binding persistence, canonical keys, reserved keys, duplicate/partial edits and recovery.");
  }finally{foreach(var file in Directory.GetFiles(mod))File.Delete(file);Directory.Delete(mod);Directory.Delete(runtime);Directory.Delete(temp);}
 }
}
