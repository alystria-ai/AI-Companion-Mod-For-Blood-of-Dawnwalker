import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';

// Execute the actual native cleanup functions against a small engine model.
// This covers teardown order and handle expiry without needing a running game.
const compiler=resolve('vendor/zig/zig-x86_64-windows-0.14.1/zig.exe');
test('native protection survives save teardown, expired handles and reused object names', {skip:!existsSync(compiler)},()=>{
 const source=readFileSync('bridge/native-source/companion_protection.h','utf8');
 const cleanup=source.slice(source.indexOf('static int removeProtection('));
 const dir=mkdtempSync(join(tmpdir(),'dawnwalker-protection-test-'));
 const harness=String.raw`
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>
#include <assert.h>
typedef struct {int32_t index,serial;} WeakObject;
typedef struct {void *fn,*data;} Frame;
static wchar_t preparedEffect[2048],activeEffect[2048],activeAsc[2048];
static unsigned char activeHandle[8],returned,handleField[8];
static int preparedAddedRoot,hasActive,stacks,events,unroots,ascLive,effectLive,weakAlive;
static int ascObject,effectObject,ascClass,effectClass;
static WeakObject preparedRef,activeAscRef;
static int fail(const char *s){(void)s;return 0;}
static void *findObject(void *a,void *b,const wchar_t *p,int e){
 (void)a;(void)b;(void)e;
 if(!wcscmp(p,L"/Script/GameplayAbilities.AbilitySystemComponent"))return &ascClass;
 if(!wcscmp(p,L"/Script/GameplayAbilities.GameplayEffect"))return &effectClass;
 if(!wcscmp(p,L"asc"))return ascLive?&ascObject:NULL;
 if(!wcscmp(p,L"effect"))return effectLive?&effectObject:NULL;
 assert(0);return NULL;
}
static void *weakGet(const WeakObject *ref){return weakAlive?(ref->index==1?(void*)&ascObject:(void*)&effectObject):NULL;}
static int isA(void *o,void *c){return (o==&ascObject&&c==&ascClass)||(o==&effectObject&&c==&effectClass);}
static int isRooted(void *o){assert(o==&effectObject);return 1;}
static void unrootObject(void *o){assert(o==&effectObject);unroots++;}
static int frameOpen(Frame *f,void *o,const wchar_t *n){assert(o==&ascObject);(void)f;(void)n;return 1;}
static void frameClose(Frame *f){(void)f;}
static void *field(Frame *f,const wchar_t *n,int size,int compound,void *prop){
 (void)f;(void)size;(void)compound;(void)prop;
 if(!wcscmp(n,L"Handle"))return handleField;
 if(!wcscmp(n,L"StacksToRemove"))return &stacks;
 if(!wcscmp(n,L"ReturnValue"))return &returned;
 assert(0);return NULL;
}
static void processEvent(void *o,void *fn,void *data){
 (void)fn;(void)data;assert(o==&ascObject&&stacks==-1);
 int h=0;memcpy(&h,handleField,4);assert(h==42);events++;
}
`+cleanup+String.raw`
static void setup(void){
 wcscpy(preparedEffect,L"effect");wcscpy(activeEffect,L"effect");wcscpy(activeAsc,L"asc");
 int h=42;memset(activeHandle,0,8);memcpy(activeHandle,&h,4);
 preparedAddedRoot=hasActive=ascLive=effectLive=weakAlive=returned=1;
 events=unroots=0;preparedRef=(WeakObject){0,0};activeAscRef=(WeakObject){0,0};
}
int main(void){
 FILE *reply=tmpfile();assert(reply);
 // Both objects gone: the reported reload after dismissing the entire party.
 setup();ascLive=effectLive=0;
 assert(removeProtection(reply,L"asc",42,L"effect"));assert(!hasActive&&events==0);
 assert(releaseProtection(reply,L"effect"));assert(!*preparedEffect&&unroots==0);
 // Effect gone first; GAS already removed the exact handle.
 setup();effectLive=returned=0;
 assert(removeProtection(reply,L"asc",42,L"effect"));assert(events==1&&!hasActive);
 assert(releaseProtection(reply,L"effect"));assert(!*preparedEffect);
 // Normal live cleanup removes only our handle and our root.
 setup();assert(removeProtection(reply,L"asc",42,L"effect"));
 assert(releaseProtection(reply,L"effect"));assert(events==1&&unroots==1);
 // A reload reused the paths. Expired serials must not target new objects.
 setup();activeAscRef=(WeakObject){1,7};preparedRef=(WeakObject){2,8};weakAlive=0;
 assert(removeProtection(reply,L"asc",42,L"effect"));assert(releaseProtection(reply,L"effect"));
 assert(events==0&&unroots==0);
 // Ownership mismatch remains an error; no unrelated handle or root is touched.
 setup();assert(!removeProtection(reply,L"asc",99,L"effect"));assert(hasActive&&events==0);
 assert(!releaseProtection(reply,L"effect"));assert(!unroots);
 assert(removeProtection(reply,L"asc",42,L"effect"));assert(!releaseProtection(reply,L"other"));
 assert(releaseProtection(reply,L"effect"));
 // The registry is reusable for the next player's protection.
 setup();assert(removeProtection(reply,L"asc",42,L"effect"));assert(releaseProtection(reply,L"effect"));
 fclose(reply);return 0;
}
`;
 try{
  const input=join(dir,'cleanup.c'),exe=join(dir,'cleanup.exe');writeFileSync(input,harness);
  const built=spawnSync(compiler,['cc',input,'-o',exe],{encoding:'utf8',timeout:120000});
  assert.equal(built.status,0,built.stderr||built.error?.message);
  const run=spawnSync(exe,[],{encoding:'utf8',timeout:10000});assert.equal(run.status,0,run.stderr||run.error?.message);
 }finally{rmSync(dir,{recursive:true,force:true});}
});
