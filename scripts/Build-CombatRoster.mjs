import {readFileSync,writeFileSync} from 'node:fs';
const root=new URL('../',import.meta.url);
const catalogue=readFileSync(new URL('runtime/companion-asset-catalog.tsv',root),'utf8').trim().split(/\r?\n/).slice(1).map(line=>line.split('\t'));
const named=JSON.parse(readFileSync(new URL('characters/companion-config.json',root),'utf8')).characters.filter(c=>c.category!=='combat');
// Reviewed ordinary variants omitted by the base-definition naming filter.
// Scripted arena phases, summoned spell actors and development fixtures stay out.
const variants={
 NPCDef_Kobold_Forest_Combat:'Forest kobold',NPCDef_Kobold_Imp_Combat:'Imp kobold',NPCDef_Kobold_Pooka_Combat:'Pooka kobold',
 NPCDef_Tatzelwurm_Albino:'Albino tatzelwurm',NPCDef_Witch_FallenPriest:'Fallen priest',
 NPCDef_Wolf_Brown:'Brown wolf',NPCDef_Wolf_White:'White wolf',NPCDef_Astral_Wolf_Dark:'Dark astral wolf',
 NPCDef_Zombie_Ancient:'Ancient zombie',NPCDef_Zombie_AstralNest:'Astral nest zombie',
 NPCDef_AstralHumanDualWield_ZombieRoman:'Ancient astral dual wielder',
 NPCDef_AstralHumanHeavy_ZombieRomanVer:'Ancient astral heavy fighter',
 NPCDef_AstralHumanSword_ZombieRomanVer:'Ancient astral swordsman',
 NPCDef_NewLocomotion_AstralHumanRouge_ZombieRomanVer:'Ancient astral rogue',
 NPCDef_Undead_LeonicaNun:'Undead nun'
};
const rows=[];
for(const [pkg,asset]of catalogue){
 if(!asset.startsWith('NPCDef_')||!(/\/Combat\/Enemies\//.test(pkg)||/\/NPC\/Animals\//.test(pkg)))continue;
 if(/Summoned|Clone|_AoHmusic|_Easy|_Hard|q[0-9]|sq[0-9]|AdditionalDefinitions|\/NewAI\//.test(pkg))continue;
 if(pkg.includes('/Combat/Enemies/')&&!variants[asset]&&!(/_(Base|Normal)$/.test(asset)||pkg.includes('/_MiniBosses/')))continue;
 if(pkg.includes('/NPC/Animals/')&&!(/\/(SimpleCharacter|QuadrupedNPC)\//.test(pkg)))continue;
 const path=pkg+'.'+asset+'_C';const original=named.find(c=>c.path===path);
 const name=variants[asset]||original?.name||asset.replace(/^NPCDef_(NewLocomotion_)?/,'').replace(/_(Base|Normal)$/,'').replace(/([a-z])([A-Z])/g,'$1 $2').replaceAll('_',' ').replace('Rouge','Rogue').trim();
 if(rows.some(c=>c.name===name))continue;
 rows.push({id:'combat_'+name.toLowerCase().replace(/[^a-z0-9]+/g,'_').replace(/^_|_$/g,''),name,path,category:'combat',chat:false,archetype:original?.id||'',note:pkg.includes('/NPC/Animals/')?'Some ambient animals have no native combat AI.':'Native definition; individual gameplay validation pending.'});
}
rows.sort((a,b)=>a.name.localeCompare(b.name));
writeFileSync(new URL('characters/combat-roster.json',root),JSON.stringify(rows,null,2)+'\n');
console.log('Combat-only definitions: '+rows.length);
