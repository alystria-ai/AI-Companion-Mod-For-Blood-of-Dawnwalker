import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readdir,rm,writeFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadJsonFile,parseJsonText} from '../bridge/json-file.mjs';

test('JSON errors name the file, line and offending text',()=>{
 const damaged='{\r\n  "characters": [\r\n    {\r\n      "id": "a"\r\n  ]\r\n}\r\n';
 assert.throws(()=>parseJsonText(damaged,'characters/companion-config.json'),error=>
  error.message.includes('characters/companion-config.json')&&error.message.includes('line 5, column 3')&&error.message.includes('"]"'));
});

test('a UTF-8 byte order mark from an editor is tolerated',()=>{
 assert.deepEqual(parseJsonText('﻿{"a":1}','x'),{a:1});
});

test('a damaged or missing file yields the fallback and one readable report',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'dawnwalker-json-'));
 try{
  const reports=[],path=join(folder,'config.json');
  const report=m=>reports.push(m);
  assert.deepEqual(await loadJsonFile(path,'config.json',{ok:true},{report}),{ok:true});
  assert.equal(reports.length,0);
  await writeFile(path,'{"a":1\n  "b":2}');
  assert.deepEqual(await loadJsonFile(path,'config.json',{ok:true},{report}),{ok:true});
  assert.equal(reports.length,1);assert.match(reports[0],/config\.json is not valid JSON.*line 2, column 3/);
  assert.deepEqual(await readdir(folder),['config.json'],'shipped files are not moved');
  await writeFile(path,'{"a":1}');
  assert.deepEqual(await loadJsonFile(path,'config.json',{ok:true},{report}),{a:1});
 }finally{await rm(folder,{recursive:true,force:true});}
});

test('a damaged player-owned file is set aside once, then defaults apply cleanly',async()=>{
 const folder=await mkdtemp(join(tmpdir(),'dawnwalker-json-'));
 try{
  const reports=[],path=join(folder,'convai-config.json'),report=m=>reports.push(m);
  await writeFile(path,'{"roster": [ {"key":"a"\n  ]\n}');
  assert.deepEqual(await loadJsonFile(path,'runtime/convai-config.json',{},{report,quarantine:true}),{});
  const files=await readdir(folder);
  assert.equal(files.length,1);assert.match(files[0],/^convai-config\.json\.broken-\d{14}$/);
  assert.match(reports[0],/kept as convai-config\.json\.broken-/);
  assert.deepEqual(await loadJsonFile(path,'runtime/convai-config.json',{},{report,quarantine:true}),{});
  assert.equal(reports.length,1,'the second read finds no file and stays quiet');
 }finally{await rm(folder,{recursive:true,force:true});}
});
