import test from 'node:test';
import assert from 'node:assert/strict';
import {parseAddonManifest,AddonRegistry} from '../bridge/addon-registry.mjs';
import {parseTarget} from '../bridge/protocol.mjs';
const id='12345678-1234-1234-1234-123456789abc';
const raw=`COMPANION-AI\t1\tdragon\t100\tr1\ndragon\tPawn World.Dragon\t3\tWorld\tPawn World.Coen\tDragon\t${id}\tFlying companion\nEND\tr1`;
test('add-on registrations reject stale, partial, invalid and duplicate records',()=>{
 assert.equal(parseAddonManifest(raw,'dragon',100000)?.[0].profileId,id);
 for(const invalid of [raw.replace('END\tr1','END\tr2'),raw.replace(id,'invalid'),raw.replace('dragon\t100','dragon\t1'),raw.replace('Flying companion','bad\tfield')])assert.equal(parseAddonManifest(invalid,'dragon',100000),null);
 assert.equal(parseAddonManifest(raw,'another-mod',100000),null);
 const row=raw.split('\n')[1];assert.equal(parseAddonManifest(raw.replace('\nEND',`\n${row}\nEND`),'dragon',100000),null);
});
test('external profiles require matching registered actor and explicit target owner',()=>{
 const registry=new AddonRegistry('.');registry.entries=parseAddonManifest(raw,'dragon',100000);
 const target=parseTarget('7\n1\nPawn World.Dragon\nDragonClass\nReady\nsingle\n0\nDragon\n\n\n\nroom\n\ndragon\ndragon\n3\n');
 assert.equal(registry.profile(target)?.id,id);
 for(const change of [{active:false},{actor:'Pawn OtherWorld.Dragon'},{addon:'unknown'},{addonActor:'unknown'},{addonInstance:'4'}])assert.equal(registry.profile({...target,...change}),null);
 registry.entries=[];assert.equal(registry.profile(target),null);
});
test('mounted camera flag is opt-in and old registration records remain valid',()=>{
 assert.equal(parseAddonManifest(raw,'dragon',100000)[0].cameraLease,false);
 const mounted=raw.replace('Flying companion\n','Flying companion\t1\n');
 assert.equal(parseAddonManifest(mounted,'dragon',100000)[0].cameraLease,true);
 assert.equal(parseAddonManifest(mounted.replace('companion\t1','companion\t0'),'dragon',100000)[0].cameraLease,false);
 for(const value of ['true','2','1\textra'])assert.equal(parseAddonManifest(mounted.replace('companion\t1','companion\t'+value),'dragon',100000),null);
});
test('silent commands and their action list are opt-in, bounded and preserved',()=>{
 const commands=raw.replace('Flying companion\n','Flying companion\t0\t1\tCome Here,Leave\n');
 const registry=new AddonRegistry('.');registry.entries=parseAddonManifest(commands,'dragon',100000);
 const profile=registry.profile({active:true,addon:'dragon',addonActor:'dragon',actor:'Pawn World.Dragon',addonInstance:'3'});
 assert.equal(profile.silentReplies,true);assert.deepEqual(profile.actions,['Come Here','Leave']);
 assert.equal(parseAddonManifest(raw,'dragon',100000)[0].silentReplies,false);
 for(const bad of ['Teleport','Come Here,Come Here','Come Here\textra'])assert.equal(parseAddonManifest(commands.replace('Come Here,Leave',bad),'dragon',100000),null);
});
