// Some game/overlay mailboxes use truncate-and-write. An empty intermediate
// read is not a focus-loss command. Keep the last complete sample until its
// normal deadline; an explicit zero still releases capture immediately.
export function heartbeatMs(raw,previous=0,now=Date.now()){
 const text=String(raw??'').trim();if(!/^\d+$/.test(text))return previous;
 const value=Number(text),stamp=value<1e12?value*1000:value;
 return Number.isSafeInteger(value)&&stamp<=now+5000?stamp:previous;
}
