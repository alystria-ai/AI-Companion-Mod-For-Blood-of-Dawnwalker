export type Profile={key:string;id:string;romanceId?:string;name:string;kind:'main'|'generic';gender:string;aliases:string[]};
export type Relationships=Record<string,{story:boolean;completed:number;unlocked:boolean}>;
export function profileId(profile:Profile|undefined,relationships?:Relationships){
 return profile&&(['anca','lacra'].includes(profile.key)&&relationships?.[profile.key]?.unlocked&&profile.romanceId||profile.id);
}
export function profileForId(profiles:Profile[],id:string){return profiles.find(p=>p.id===id||p.romanceId===id);}
export type Identity={actor:string;actorClass:string;name?:string;definition?:string;bodyType?:string;voiceTag?:string};
export function matchProfile(target:Identity,profiles:Profile[],assignments:Record<string,string>,random= Math.random):Profile|undefined{
  const tokens=[target.name||'',(target.voiceTag||'').split('.').at(-1)||'',
    target.actor.split('.').at(-1)?.replace(/_\d+$/,'')||'',
    (target.definition||'').split('.').at(-1)?.replace(/^Default__NPCDef_/,'').replace(/_C$/,'')||''].map(x=>x.toLowerCase());
  const named=profiles.find(p=>p.kind==='main'&&p.key!=='coen'&&p.aliases.some(a=>tokens.includes(a.toLowerCase())));
  if(named)return named;
  const gender=({man:'MALE',woman:'FEMALE'} as Record<string,string>)[(target.bodyType||'').toLowerCase()];
  // BodyType alone also says Man on rabbits: require a humanoid NPC definition.
  if(!gender||!/BP_NonPlayerCharacter_C/.test(target.actorClass)||!/NPCDef_/.test(target.definition||'')||/\/Animals\//i.test(target.definition||''))return undefined;
  const pool=profiles.filter(p=>p.kind==='generic'&&p.gender===gender);
  const previous=pool.find(p=>p.id===assignments[target.actor]);if(previous)return previous;
  if(!pool.length)return undefined;
  const chosen=pool[Math.min(pool.length-1,Math.floor(Math.max(0,random())*pool.length))];
  assignments[target.actor]=chosen.id;return chosen;
}
