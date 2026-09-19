using System;
public static class CompanionLoadingTests {
 static void Check(bool ok,string message){if(!ok)throw new Exception(message);}
 static CompanionLoading Start(){var l=new CompanionLoading();l.Begin("ambrus","Ambrus","123",0);l.Request="pabc";return l;}
 static CompanionView View(string phase="ready"){return new CompanionView{epoch="123",gameAlive=true,members=new[]{new CompanionMember{id="ambrus"}},summons=new[]{new CompanionSummon{id="pabc",member="ambrus",phase=phase,message="Progress"}}};}
 public static void Main(){
  var l=Start();var s=View();Check(!l.Advance(s,100),"Wait for ready presentation");Check(l.Advance(s,600),"Close after actual ready");
  l=Start();s=View("body");Check(!l.Advance(s,600)&&l.Stage==2,"Asset loading is not readiness");
  s=View();s.result=new CompanionReply{id="pabc",ok=true,message="Spawn requested"};s.summons=null;Check(!l.Advance(s,1000),"ACK and existing member cannot close");
  s=View();s.summons[0].id="pold";Check(!l.Advance(s,2000),"Old request ignored");
  s=View();s.summons[0].member="anca";Check(!l.Advance(s,2000),"Wrong companion ignored");
  s=View();s.members=new CompanionMember[0];Check(!l.Advance(s,2000),"Missing member cannot close");
  l=Start();s=View();s.epoch="124";Check(!l.Advance(s,100)&&!l.Active,"Reload cancels pending close");
  l=Start();l.Cancel();Check(!l.Advance(View(),1000),"Manual close disarms completion");
  l=Start();s=View("failed");Check(!l.Advance(s,1000)&&!l.Active,"Failed load stays in menu");
  l=Start();s=View();s.result=new CompanionReply{id="pabc",ok=false,message="Rejected"};Check(!l.Advance(s,1000)&&!l.Active,"Rejected command cancels loading");
  l=Start();s=View("body");s.gameAlive=false;Check(l.RetainDuringStall(10000)&&!l.Advance(s,10000)&&l.Active,"Game-thread stall does not hide UI");
  s=View();s.gameAlive=false;Check(!l.Advance(s,11000)&&!l.Advance(s,12000),"Stale ready snapshot cannot close");
  Check(!l.Advance(s,120000)&&!l.Active&&!l.RetainDuringStall(120000),"Stall grace is bounded");
  l=Start();s=View("body");s.note="Paused. Queued commands execute after unpausing.";s.summons=null;l.Advance(s,100);Check(l.Message.Contains("Unpause"),"Pause instruction visible");
  BatchChecks();
  Console.WriteLine("Companion loading lifecycle: 14 original + 14 batch scenarios passed");
 }

 static CompanionLoadBatch Batch(out CompanionLoading a,out CompanionLoading b){
  var batch=new CompanionLoadBatch();a=batch.Add("anca","Anca","123",0);a.Request=a.Member="pa";
  b=batch.Add("ambrus","Ambrus","123",10);b.Request=b.Member="pb";return batch;
 }
 static CompanionView Arrived(params string[] ids){
  var members=new CompanionMember[ids.Length];for(int i=0;i<ids.Length;i++)members[i]=new CompanionMember{id=ids[i],actor="Actor_"+ids[i]};
  return new CompanionView{epoch="123",gameAlive=true,members=members};
 }
 static void BatchChecks(){
  CompanionLoading a,b;var batch=Batch(out a,out b);
  Check(!batch.Advance(Arrived("pb"),100)&&batch.Ready==1&&batch.Pending==1,"Second arrival cannot close over the first");
  Check(!batch.Advance(Arrived("pa","pb"),1000)&&batch.Advance(Arrived("pa","pb"),2200),"Entire batch ready and quiet before close");
  batch=Batch(out a,out b);b.Request=null;
  Check(!batch.Advance(Arrived("pa","pb"),10000)&&batch.Pending==1,"Outstanding HTTP cannot be mistaken for ready");
  batch=Batch(out a,out b);batch.Advance(Arrived("pa","pb"),1000);batch.Browse(1100);
  Check(!batch.Advance(Arrived("pa","pb"),2300)&&batch.Choosing,"Selecting another character delays auto-close");
  batch.Browse(3500);Check(!batch.Advance(Arrived("pa","pb"),6400),"Continued browsing extends grace");
  Check(batch.Advance(Arrived("pa","pb"),6500)&&!batch.Choosing,"Browsing never permanently latches the completed menu open");
  var c=batch.Add("lacra","Lacra","123",11000);c.Request=c.Member="pc";
  Check(!batch.Advance(Arrived("pa","pb"),13000)&&batch.Pending==1&&!batch.Choosing,"New summon rearms only after that request completes");
  Check(!batch.Advance(Arrived("pa","pb","pc"),14000)&&batch.Advance(Arrived("pa","pb","pc"),15200),"Latest arrival closes full batch");
  batch=Batch(out a,out b);var s=Arrived("pa","pb");s.summons=new[]{new CompanionSummon{id="pb",member="pb",phase="failed",message="Dismissed"}};
  Check(!batch.Advance(s,1000)&&batch.Failed==1&&!batch.Advance(s,10000),"Failure wins over a still-present actor");
  batch=Batch(out a,out b);s=Arrived("pa","pb");s.result=new CompanionReply{id="pa",ok=false,message="Rejected"};
  Check(!batch.Advance(s,1000)&&batch.Failed==1,"HTTP command rejection cannot close");
  batch=Batch(out a,out b);s=Arrived("pa","pb");s.gameAlive=false;
  Check(!batch.Advance(s,10000)&&batch.Ready==0&&batch.RetainDuringStall(10000),"Frozen snapshot does not finish batch");
  Check(!batch.Advance(s,120100)&&batch.Failed==2&&!batch.RetainDuringStall(120100),"Stall timeout leaves failure visible");
  batch=Batch(out a,out b);s=Arrived("pa","pb");s.epoch="124";
  Check(!batch.Advance(s,1000)&&!batch.Active,"World change cancels old batch");
  batch=Batch(out a,out b);batch.Cancel();Check(!batch.Advance(Arrived("pa","pb"),5000),"Manual close stays closed");
 }
}
