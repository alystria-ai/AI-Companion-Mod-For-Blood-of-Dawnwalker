using System;
using System.IO;
class SupportReportTests {
 static void Check(bool ok,string why){if(!ok)throw new Exception(why);}
 static void Main(){
  string root=Path.Combine(Path.GetTempPath(),"DawnwalkerReport-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(root);
  try{
   File.WriteAllText(Path.Combine(root,"convai-config.json"),"CONFIG_MUST_NOT_APPEAR");
   File.WriteAllText(Path.Combine(root,"overlay.json"),"CHAT_MUST_NOT_APPEAR");
   File.WriteAllText(Path.Combine(root,"helper-errors.log"),"Native callback failed\napiKey=short-test-secret\nAuthorization: Bearer abc\ntranscript: PRIVATE_WORDS\nC:\\Users\\Example Person\\Game Files\\broken.lua\nhttps://test.invalid/?token=abc\nabcdefabcdefabcdefabcdefabcdefab\n");
   string result=SupportReport.Build(root);
   Check(result.Contains("Native callback failed"),"keeps useful diagnostics");
   foreach(string secret in new[]{"CONFIG_MUST_NOT_APPEAR","CHAT_MUST_NOT_APPEAR","short-test-secret","PRIVATE_WORDS","Example Person","broken.lua","test.invalid","abcdefabcdefabcdefabcdefabcdefab"})Check(!result.Contains(secret),"excludes "+secret);
   File.WriteAllText(Path.Combine(root,"reload-status.txt"),new string('x',100000)+"\nlast line\n");
   Check(SupportReport.Tail(Path.Combine(root,"reload-status.txt"),256)=="last line\n","tail discards partial lines");
   result=SupportReport.Build(root);Check(result.Length<10000,"bounded report even with long log");
   Check(result.Contains("Unavailable"),"missing files do not prevent report");
   Console.WriteLine("PASS: diagnostic allowlist, credential/path/transcript redaction, bounded tails and missing-file handling.");
  }finally{foreach(string file in Directory.GetFiles(root))File.Delete(file);Directory.Delete(root);}
 }
}
