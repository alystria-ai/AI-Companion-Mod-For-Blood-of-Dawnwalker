import {readFile,rename} from 'node:fs/promises';

// Node's JSON errors carry a character offset but no file name, so a damaged
// configuration reads as an anonymous crash. Name the file and show the line.
function locate(text,error){
 const offset=/position (\d+)/.exec(error.message)?.[1];
 if(offset===undefined)return '';
 const at=Number(offset),before=text.slice(0,at).split(/\r?\n/);
 const line=before.length,column=before[before.length-1].length+1;
 const source=text.split(/\r?\n/)[line-1]??'';
 return ` (line ${line}, column ${column}: ${JSON.stringify(source.trim().slice(0,80))})`;
}

export function parseJsonText(text,label){
 try{return JSON.parse(text.charCodeAt(0)===0xFEFF?text.slice(1):text);}
 catch(error){throw new Error(`${label} is not valid JSON: ${error.message}${locate(text,error)}`,{cause:error});}
}

// A damaged file should cost its own feature, not the whole bridge. The caller
// receives the fallback and a readable reason. Files the player owns (for
// example runtime/convai-config.json, which reinstalling does not replace) can
// be set aside with `quarantine`, so the next start finds a clean default
// instead of failing on the same bytes again. Shipped files are left alone:
// installing the update replaces them.
export async function loadJsonFile(path,label,fallback,{report=message=>console.error(message),quarantine=false}={}){
 let text;
 try{text=await readFile(path,'utf8');}
 catch(error){if(error.code==='ENOENT')return fallback;report(`${label} could not be read: ${error.message}`);return fallback;}
 try{return parseJsonText(text,label);}
 catch(error){
  let outcome='Continuing without it until the file is repaired or the mod is reinstalled.';
  if(quarantine){
   const moved=`${path}.broken-${new Date().toISOString().replace(/[-:.TZ]/g,'').slice(0,14)}`;
   try{await rename(path,moved);outcome=`The damaged copy was kept as ${moved.replace(/^.*[\\/]/,'')} and defaults are in use.`;}
   catch(renameError){outcome=`It could not be set aside (${renameError.code}); defaults are in use for now.`;}
  }
  report(`${error.message}. ${outcome}`);return fallback;
 }
}
