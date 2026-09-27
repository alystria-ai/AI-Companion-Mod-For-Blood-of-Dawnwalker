import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';
import fengari from 'fengari';
const {lua,lauxlib,lualib,to_luastring,to_jsstring}=fengari;
const read=name=>fs.readFileSync(`mod/Scripts/${name}.lua`,'utf8');
test('offline UI catalogue preserves every format token in all ten languages',()=>{
 const data=JSON.parse(fs.readFileSync('localization/ui.json','utf8'));
 assert.equal(data.languages.length,10);
 for(const [key,translations] of Object.entries(data.strings)){
  assert.equal(translations.length,9,key);
  for(const value of translations){assert.ok(value.trim(),key);assert.deepEqual([...value.matchAll(/\{\d+\}/g)].map(m=>m[0]).sort(),[...key.matchAll(/\{\d+\}/g)].map(m=>m[0]).sort(),key);}
 }
});
test('UI language resolves game, OS and explicit choices without touching keys or dialogue',()=>{
 const L=lauxlib.luaL_newstate();lualib.luaL_openlibs(L);
 const source=`
local game,nativeCalls='zh-Hans',0
local files={['root/os-language.txt']='ja-JP'}
io.open=function(path,mode)
 if mode=='w'then return {write=function(_,v)files[path]=v end,close=function()end}end
 if not files[path]then return nil end
 return {read=function()return files[path]end,close=function()end}
end
os.time=function()return 100 end
local modules={runtime_path='root',ai_state={find=function()return {IsValid=function()return true end,GetCurrentLanguage=function()nativeCalls=nativeCalls+1;return game end}end}}
require=function(name)return modules[name]end
modules.ui_translations=assert(load(${JSON.stringify(read('ui_translations'))}))()
local ui=assert(load(${JSON.stringify(read('ui_localization'))}))();modules.ui_localization=ui
ui.poll(0,true);assert(ui.code=='zh-CN');assert(ui.text('Summon')=='召唤')
assert(ui.format('{0} in party · {1} loading',2,0)=='队伍 2 人 · 0 正在加载')
assert(ui.text('F7')=='F7');assert(ui.text('Anca')=='Anca');assert(ui.text('A completely new diagnostic')=='A completely new diagnostic')
game='unsupported';ui.poll(0,true);assert(ui.code=='ja')
local before=nativeCalls;ui.poll(8,true);assert(ui.code=='ru'and nativeCalls==before)
assert(ui.normalize('zh-HK')=='zh-TW');assert(ui.normalize('pt-PT')=='pt-BR');assert(ui.normalize('de-DE')=='de')
local settings=assert(load(${JSON.stringify(read('companion_settings'))}))()
local repaired,values=settings.repairConfig('[Companions]\\nDamagePercent=250\\nBattleComments=0\\n')
assert(values.UiLanguage==0 and values.BattleComments==0)
for _,s in ipairs(settings.schema)do
 for index=2,10 do ui.index=index;assert(ui.text(s.label)~=s.label,'Missing label '..s.id);assert(ui.help(s)~=''and ui.help(s)~=s.help,'Missing help '..s.id)end
end
assert(settings.bindings.Menu=='F5'and settings.bindings.SingleVoice=='F7')
`;
 const code=lauxlib.luaL_dostring(L,to_luastring(source));if(code!==lua.LUA_OK)throw Error(to_jsstring(lua.lua_tostring(L,-1)));
});
