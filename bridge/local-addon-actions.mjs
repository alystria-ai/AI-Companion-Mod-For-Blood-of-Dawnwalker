// Deliberately exact commands: no AI, negation guessing or substring matching.
const aliases=new Map([
 ['follow','Follow'],['follow me','Follow'],['stop','Stop Walking'],['stop walking','Stop Walking'],['stay','Stop Walking'],['wait','Stop Walking'],
 ['come','Come Here'],['come here','Come Here'],['look at me','Look At Player'],['look at player','Look At Player'],
 ['attack','Attack Nearby Enemies'],['attack nearby enemies','Attack Nearby Enemies'],['leave','Leave'],
]);
export function localAddonAction(value,target,profile){
 if(!target.active||value.generation!==target.generation)throw Error('The selected creature changed. Select it again.');
 if(typeof value.id!=='string'||!/^[a-zA-Z0-9-]{1,80}$/.test(value.id))throw Error('Invalid message ID');
 if(typeof value.text!=='string'||value.text.length>1200)throw Error('Type a creature command.');
 const name=aliases.get(value.text.trim().toLowerCase().replace(/[.!]+$/,'').trim().replace(/\s+/g,' '));
 if(!name)throw Error('Use Follow, Stop, Come here, Look at me, Attack or Leave.');
 if(!profile?.localActionsOnly||!profile.actions.includes(name))throw Error('That order is unavailable. Dismount before giving movement orders.');
 return {generation:target.generation,id:value.id,name};
}
