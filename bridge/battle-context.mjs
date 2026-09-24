import {createHash} from 'node:crypto';

// Session-local game observations, not lore, quest completion or invented kills.
export function battleContext(raw, npc, now=Date.now()) {
  const empty={revision:'no-recent-battle',text:''};
  if(!String(raw).endsWith('\n'))return empty;
  const [header,...rows]=String(raw).trimEnd().split('\n');
  const [magic,version,stamp]=header.split('\t');
  if(magic!=='BATTLES'||version!=='1'||!Number.isFinite(Number(stamp))||Math.abs(now/1000-Number(stamp))>12)return empty;
  const facts=[];
  for(const row of rows.slice(-3)) {
    const [id,kind,state,level,title,enemies,witnesses,kills,updated]=row.split('\t');
    if(!id||!['battle','horde'].includes(kind)||!['combat-ended','cleared','complete','ended'].includes(state)||!Number.isFinite(Number(updated))||now/1000-Number(updated)>1800||Number(updated)>now/1000+5)continue;
    const witnessed=(witnesses||'').split(',').includes(npc);
    const status=state==='cleared'?'wave cleared':state==='complete'?'final wave cleared; horde completed':state==='combat-ended'?'combat ended; victory or retreat was not established':'horde stopped; do not assume victory';
    const encounter=kind==='horde'?`Horde wave ${Number(level)} (${title}): ${status}.`:`Recent battle: ${status}.`;
    facts.push(`${encounter} Observed opponents: ${enemies||'types not identified'}. ${kind==='horde'?`Confirmed enemies defeated in this wave: ${Number(kills)||0}. `:''}${witnessed?'You were nearby during this encounter and can remember witnessing it.':'You were not confirmed present. Treat this as a report about Coen, not something you personally fought in.'}`);
  }
  if(!facts.length)return empty;
  const text='RECENT BATTLE CONTEXT (oldest to newest)\n'+facts.join('\n')+'\nUse these observations when discussing the fight, including during a horde rest. Refer to opponents by the recorded character names or creature types. Do not replace their names with "a boss", "the boss", "a miniboss", or other game-difficulty labels. Wave numbers and encounter titles are bookkeeping, not enemy identities. If no personal name was observed, use the recorded enemy type without inventing a name. A number after x counts distinct observed opponents, not your personal kills. Do not invent particular attacks, injuries, finishing blows, quest outcomes or participation. These are recent gameplay events, not permanent campaign facts.';
  return {revision:createHash('sha256').update(text).digest('hex'),text};
}
