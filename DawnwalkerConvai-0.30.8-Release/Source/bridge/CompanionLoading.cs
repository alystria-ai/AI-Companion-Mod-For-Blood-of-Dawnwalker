using System;
using System.Collections.Generic;

public sealed class CompanionSummon {public string id,member,phase,message;}
// Request identity + party epoch + menu lifetime bind completion to this click.
// UI time is monotonic and independent of Unreal's game thread / pause clock.
public sealed class CompanionLoading {
 public bool Active {get;private set;}
 public string Member,Name,Epoch,Request,Phase,Message;
 long started,readyAt=-1;
 public void Begin(string member,string name,string epoch,long now){Member=member;Name=name;Epoch=epoch;Request=null;Phase="queued";Message="Sending summon request";started=now;readyAt=-1;Active=true;}
 public void Cancel(){Active=false;Request=null;readyAt=-1;}
 public void Fail(string message){Active=false;Phase="failed";Message=message;readyAt=-1;}
 public bool RetainDuringStall(long now){return Active&&now-started<120000;}
 public bool Advance(CompanionView state,long now){
  if(!Active)return false;
  if(state.epoch!=Epoch){Fail("Party changed. Open the menu again to summon.");return false;}
  if(now-started>=120000){Fail("Still waiting for the game. The summon may finish later; close the menu to continue.");return false;}
  if(Request==null)return false;
  if(state.result!=null&&state.result.id==Request&&!state.result.ok){Fail(state.result.message);return false;}
  CompanionSummon found=null;
  if(state.summons!=null)foreach(var s in state.summons)if(s.id==Request&&s.member==Member)found=s;
  if(found!=null){
   if(found.phase=="failed"){Fail(found.message);return false;}
   Phase=found.phase;Message=found.message;
   if(found.phase=="ready"&&state.gameAlive){
    bool attached=false;if(state.members!=null)foreach(var m in state.members)if(m.id==Member)attached=true;
    if(attached){if(readyAt<0)readyAt=now;return now-readyAt>=500;}
   }
  }else Message=(state.note??"").StartsWith("Paused")?"Unpause the game to begin summoning":"Waiting for the game to accept the request";
  readyAt=-1;return false;
 }
 public int Stage {get{return Phase=="queued"?0:Phase=="character"?1:Phase=="body"?2:Phase=="ai"||Phase=="reactions"?3:Phase=="spawning"?4:Phase=="ready"?5:0;}}
}

// One menu lifetime can own many independent summon requests. An older ready
// response cannot close the window over a newer click or an HTTP request.
public sealed class CompanionLoadBatch {
 public readonly List<CompanionLoading> Items=new List<CompanionLoading>();
 readonly HashSet<CompanionLoading> ready=new HashSet<CompanionLoading>();
 public bool Active {get;private set;}
 public bool Choosing {get;private set;}
 public string Message="";
 long readyAt=-1,lastInteraction;
 public int Ready {get{return ready.Count;}}
 public int Failed {get{int n=0;foreach(var item in Items)if(!item.Active&&!ready.Contains(item))n++;return n;}}
 public int Pending {get{return Items.Count-Ready-Failed;}}
 public int Stage {get{int total=0;foreach(var item in Items)total+=ready.Contains(item)?5:item.Stage;return Items.Count==0?0:total/Items.Count;}}
 public CompanionLoading Add(string member,string name,string epoch,long now){
  if(!Active){Items.Clear();ready.Clear();}
  var item=new CompanionLoading();item.Begin(member,name,epoch,now);Items.Add(item);
  Active=true;Choosing=false;lastInteraction=now;readyAt=-1;Message="";return item;
 }
 public void Browse(long now){if(!Active)return;Choosing=true;lastInteraction=now;}
 public void Cancel(){foreach(var item in Items)item.Cancel();Active=false;Choosing=false;readyAt=-1;}
 public bool RetainDuringStall(long now){foreach(var item in Items)if(!ready.Contains(item)&&item.RetainDuringStall(now))return true;return false;}
 public string Summary(){return Ready+" / "+Items.Count+" ready"+(Pending>0?"  ·  "+Pending+" loading":"")+(Failed>0?"  ·  "+Failed+" failed":"");}
 public string Progress(){
  var lines=new List<string>();
  // Prefer outstanding requests so an arrived first member doesn't obscure
  // the progress of later ones. The current party list shows every instance.
  foreach(var item in Items)if(!ready.Contains(item)&&lines.Count<5)lines.Add(item.Name+"  ·  "+(item.Message??item.Phase));
  if(lines.Count==0)foreach(var item in Items)if(lines.Count<5)lines.Add(item.Name+"  ·  Ready");
  if(Pending>5)lines.Add("+ "+(Pending-5)+" more loading; see YOUR PARTY");
  return String.Join("\n",lines.ToArray());
 }
 public bool Advance(CompanionView state,long now){
  if(!Active)return false;
  foreach(var item in Items){
   if(item.Epoch!=state.epoch){Cancel();Message="Party changed. Choose your companions again.";return false;}
   if(ready.Contains(item)||!item.Active)continue;
   // Failure wins even if the same snapshot still contains a departing actor.
   if(state.result!=null&&state.result.id==item.Request&&!state.result.ok){item.Fail(state.result.message);continue;}
   if(state.summons!=null)foreach(var s in state.summons)if(s.id==item.Request&&s.member==item.Member&&s.phase=="failed")item.Fail(s.message);
   if(!item.Active)continue;
   // SUMMON history is bounded. A current, exact request-ID member with its
   // actual actor also establishes arrival after older history is pruned.
   if(item.Request!=null&&state.gameAlive&&state.members!=null){
    foreach(var member in state.members)if(member.id==item.Request&&!String.IsNullOrEmpty(member.actor)){
     ready.Add(item);item.Phase="ready";item.Message="Ready";break;
    }
   }
   if(!ready.Contains(item)&&item.Advance(state,now))ready.Add(item);
  }
  // Intentional clicks/scrolls buy time to choose; a refresh cannot latch the menu open.
  if(Choosing&&now-lastInteraction>=3000)Choosing=false;
  if(Pending>0||Failed>0||!state.gameAlive){readyAt=-1;return false;}
  if(readyAt<0)readyAt=now;
  return !Choosing&&now-readyAt>=1200&&now-lastInteraction>=1200;
 }
}
