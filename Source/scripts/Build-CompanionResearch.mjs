// Offline index of the read-only UE4SS catalogue and reflected metadata dump.
// Does not start the game, load assets, connect to Convai, or change game files.
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
const root=resolve(dirname(fileURLToPath(import.meta.url)),'..');
let dumpPath=process.argv[2];
if(!dumpPath){
  const gameBin=process.env.DAWNWALKER_GAME_DIRECTORY
    ? resolve(process.env.DAWNWALKER_GAME_DIRECTORY,'Dawnwalker/Binaries/Win64')
    : JSON.parse((await readFile(resolve(root,'runtime/installation.json'),'utf8')).replace(/^\uFEFF/,'')).gameBin;
  dumpPath=resolve(gameBin,'ue4ss/UE4SS_ObjectDump.txt');
}
const raw=await readFile(resolve(root,'runtime/companion-asset-catalog.tsv'),'utf8');
if(!raw.startsWith('package\tasset\tpath\n')&&!raw.startsWith('package\tasset\tpath\r\n')) throw new Error('A successful asset catalogue is required');
const assets=new Map();
for(const row of raw.trim().split(/\r?\n/).slice(1)){
  const [pkg,name,path,...extra]=row.split('\t');
  if(extra.length||!pkg.startsWith('/Game/_Dawnwalker/')||pkg!==`${path}/${name}`) throw new Error('Invalid catalogue row');
  assets.set(pkg,{package:pkg,asset:name,path});
}
const seeds=[
  ['anca','Anca',[],true,['NPC/MainNPC/NPCDef_Anca']],
  ['lacra','Lacra',[],true,['Combat/Enemies/Bosses/Lacra/NPCDef_Lacra_Base','Quest/q103_lacra/Characters/Humanoid/NPCDef_Lacra']],
  ['bakir','Bakir',[],true,['Combat/Enemies/Bosses/Bakir/NPCDef_Summoned_CoenHelper_Bakir','Combat/Enemies/Bosses/Bakir/NPCDef_Bakir_Base']],
  ['ambrus','Ambrus',['Ambrose'],true,['Combat/Enemies/Bosses/Ambrus/NPCDef_Summoned_CoenHelper_Ambrus','Combat/Enemies/Bosses/Ambrus/NPCDef_Ambrus_Base']],
  ['xanthe','Xanthe',[],true,['Combat/Enemies/Bosses/Xanthe/NPCDef_Summoned_CoenHelper_Xanthe','Combat/Enemies/Bosses/Xanthe/NPCDef_Xanthe_Base']],
  ['brencis','Brencis',[],true,['Combat/Enemies/Bosses/Brencis/NPCDef_Brencis_Base']],
  ['marat','Crake / Marat',['Crake','Marat'],true,['NPC/MainNPC/NPCDef_Marat']],
  ['matriarch','Uriash Matriarch / Bakr-Erga',['Matriarch','Bakr-Erga'],false,['Combat/Enemies/Bosses/UriashMatriarch/NPCDef_UriashMatriarch_Base']],
  ['leonica','Leonica',[],false,['Combat/Enemies/Bosses/Leonica/NPCDef_Leonica_Base']],
  ['ocha','Ocha',['Bakr-Ocha'],false,['Quest/_Side_Quests/sq716_uriash_girl/Characters/NPCDef_Ocha']],
  ['vicho','Vicho',[],false,['Quest/_Side_Quests/sq714_vampireally/Characters/Humanoid/NPCDef_Vicho']],
  ['drogos','Drogos',[],false,['NPC/SecondaryNPC/NPCDef_Drogos','NPC/SecondaryNPC/NPCDef_Drogos_Non_boss']],
  ['sara','Sara',['Sarah'],false,['Quest/q106_rebel_issues/Characters/NPCDef_Sarah']],
  ['catalin','Catalin',[],false,['NPC/MainNPC/NPCDef_Catalin']],
  ['pieter','Pieter',[],false,['NPC/MainNPC/NPCDef_Pieter_armed']],
  ['vladimir','Vladimir',['Vlad'],false,['NPC/MainNPC/NPCDef_Vladimir']],
  ['isbrand','Isbrand',[],false,['Combat/Enemies/Bosses/Isbrand/NPCDef_Isbrand_Base']],
];
const roster=seeds.map(([id,name,aliases,requested,paths])=>({
  id,name,aliases,requested,status:'asset-located; spawning-and-combat-unverified',
  candidates:paths.map(path=>{
    const pkg='/Game/_Dawnwalker/'+path,asset=assets.get(pkg);
    if(!asset)throw new Error(`Missing roster candidate ${pkg}`);
    return {package:pkg,asset:asset.asset,generatedClassPathCandidate:`${pkg}.${asset.asset}_C`,
      reason:asset.asset.includes('CoenHelper')?'Existing CoenHelper-named variant; allegiance, lifespan and encounter dependencies require inspection':'Definition located; combat setup and independent spawning require inspection'};
  }),
}));
const lines=(await readFile(dumpPath,'utf8')).split(/\r?\n/);
const namespaces=/\/(?:Script\/(?:RebelAI|RebelFormation|DogwoodCombat|Dawnwalker|Population)\.)/;
const owners=/(?:RebelAIBoard|RebelAIStub|RebelAICombatBlueprintFunctionLibrary|RebelAISubsystem|RebelAIConfig|RebelAITrait_Aggression|RebelAIAggressionSettings|RebelFormationGroup|CombatComponentBase|SpawnPopulationActorAsyncAction|PopulationSimpleSpawner|RebelAIParams_Attack|RebelAIParams_Defense)/;
const evidence=[];
for(let i=0;i<lines.length;i++){
  const m=lines[i].match(/^\[[A-Fa-f0-9]+\] (\w+) (\S+)/);
  if(!m||!namespaces.test(m[2])||!owners.test(m[2])||!/(?:Class|ScriptStruct|Function|Property)$/.test(m[1]))continue;
  // Keep names, types and source line numbers; native addresses aren't an API.
  evidence.push(`${i+1}\t${m[1]}\t${m[2]}`);
}
await mkdir(resolve(root,'docs'),{recursive:true});
await writeFile(resolve(root,'characters/companion-roster.json'),JSON.stringify({version:1,scope:'Research candidates; not a spawn-ready roster',source:'runtime/companion-asset-catalog.tsv',characters:roster},null,2)+'\n');
await writeFile(resolve(root,'docs/companion-native-evidence.tsv'),'dumpLine\ttype\tname\n'+evidence.join('\n')+'\n');
const index={generatedAt:new Date().toISOString(),catalogueRows:raw.trim().split(/\r?\n/).length-1,uniqueAssets:assets.size,
  npcDefinitions:[...assets.values()].filter(a=>a.asset.startsWith('NPCDef_')).length,
  aiDefinitions:[...assets.values()].filter(a=>a.asset.startsWith('AIDef_')).length,
  aiConfigs:[...assets.values()].filter(a=>a.asset.startsWith('AIConfig_')).length,
  aiAbilities:[...assets.values()].filter(a=>a.asset.startsWith('GA_AI_')).length,
  requestedCharacters:roster.filter(r=>r.requested).length,additionalCandidates:roster.filter(r=>!r.requested).length,
  reflectedEvidenceRows:evidence.length,dumpPath:'<game>/Dawnwalker/Binaries/Win64/ue4ss/UE4SS_ObjectDump.txt'};
await writeFile(resolve(root,'docs/companion-research-index.json'),JSON.stringify(index,null,2)+'\n');
console.log(JSON.stringify(index));
