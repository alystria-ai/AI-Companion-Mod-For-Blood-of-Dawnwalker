import fs from 'node:fs';
import path from 'node:path';
const meta=JSON.parse(fs.readFileSync('runtime/bundle-meta.json','utf8'));
const packages=new Set();
for(const file of Object.keys(meta.inputs)){
 const match=file.replaceAll('\\','/').match(/^(.*node_modules\/(?:@[^/]+\/)?[^/]+)\//);
 if(match)packages.add(match[1]);
}
const output='vendor/release-licenses/browser';fs.mkdirSync(output,{recursive:true});
// The SDK itself ships bundled dependencies that do not appear individually in
// esbuild's input map. Preserve their upstream notices with each release.
if(fs.existsSync('licenses/browser'))for(const file of fs.readdirSync('licenses/browser')){
 fs.copyFileSync(path.join('licenses/browser',file),path.join(output,file));
}
for(const directory of packages){
 const pkg=JSON.parse(fs.readFileSync(path.join(directory,'package.json'),'utf8'));
 const licenses=fs.readdirSync(directory).filter(name=>/^(licen[cs]e|notice|copying)(\.|$|-)/i.test(name)&&fs.statSync(path.join(directory,name)).isFile());
 if(!licenses.length)throw Error(`Missing upstream license for ${pkg.name}`);
 for(const file of licenses)fs.copyFileSync(path.join(directory,file),path.join(output,pkg.name.replaceAll('/','_')+'-'+file));
}
console.log(`Collected upstream licenses for ${packages.size} bundled packages.`);
