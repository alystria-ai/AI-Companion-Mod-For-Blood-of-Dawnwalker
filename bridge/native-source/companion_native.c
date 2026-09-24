/* A narrow Lua-loadable C module. Entry points intentionally do not touch the
 * lua_State or link another Lua runtime. Lua writes a fixed request file and
 * calls this function on the game thread; the reply is a separate file.
 *
 * All engine operations are resolved by name through the supplied UE4SS exports.
 * Soft classes stay in game-sized native parameter buffers. In particular, this
 * never constructs UE4SS's incompatible Lua TSoftObjectPtr wrapper.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <wchar.h>
#include <math.h>

typedef struct { wchar_t *data; int count,capacity; } FString;
typedef void *(*FindObjectFn)(void*,void*,const wchar_t*,unsigned char);
typedef void *(*PublicFindObjectFn)(void*,void*,const wchar_t*,unsigned char,void*);
typedef void *(*FindMemberFn)(void*,const wchar_t*);
typedef void (*EventFn)(void*,void*,void*);
typedef const int *(*OffsetFn)(const void*);
typedef int (*SizeFn)(const void*);
typedef const unsigned short *(*ParamsSizeFn)(const void*);
typedef unsigned char (*IsAFn)(const void*,const void*);
typedef void (*InitFn)(const void*,void*);
typedef void (*DestroyFn)(void*,void*);
typedef void (*CopyFn)(const void*,void*,const void*);
typedef void (*ExportFn)(const void*,FString*,const void*,const void*,void*,int,void*);
typedef void (*FreeFn)(void*);
typedef void *(*ObjectValueFn)(const void*,const void*);
typedef void (*RootFn)(void*);
typedef unsigned char (*RootCheckFn)(void*);
/* Borrow only serials already assigned by the ENGINE. UE4SS's weak-pointer
 * constructor calls AllocateSerialNumber, whose serial-zero path crashes
 * on fresh (serial-zero) objects in this build. Never invoke that allocator. */
typedef struct { int32_t index,serial; } WeakObject;
typedef void *(*WeakGetFn)(const WeakObject*);
typedef int (*ObjectIndexFn)(const void*);
typedef void *(*IndexItemFn)(int);
static WeakGetFn weakGet;static ObjectIndexFn objectIndex;
static IndexItemFn indexItem;static OffsetFn itemSerial;
static HMODULE module;
static FindObjectFn findObject; static FindMemberFn findFunction,findProperty;
static PublicFindObjectFn publicFindObject;
static ULONGLONG lookupMilliseconds;static unsigned lookupCalls;
/* Use the loader's public resolver, which selects its indexed/name-based path.
 * Calling InternalSlow directly bypassed it and formatted every object's full
 * name for every lookup. No object pointers are cached across requests here. */
static void *resolveByName(void *cls,void *outer,const wchar_t *name,unsigned char exact){
    ULONGLONG started=GetTickCount64();
    void *result=publicFindObject(cls,outer,name,exact,NULL);
    lookupMilliseconds+=GetTickCount64()-started;lookupCalls++;return result;
}
static EventFn processEvent; static OffsetFn propertyOffset; static SizeFn propertySize;
static ParamsSizeFn paramsSize; static IsAFn isA; static InitFn initialize;
static DestroyFn destroy; static CopyFn copyValue; static ExportFn exportValue;
static FreeFn freeEngine; static ObjectValueFn objectValue;
static RootFn rootObject,unrootObject;static RootCheckFn isRooted;static IsAFn isChildOf;
/* Async actions may call SetReadyToDestroy and clear their own root flag.
 * Keep serial-checked weak handles, never raw UObject pointers across ticks.
 * Path searches scan the entire object array in this build (~1 second per
 * missing action); polling must not search for the expired action by name. */
typedef struct { wchar_t action[2048],spawner[2048]; int addedSpawnerRoot; WeakObject actionRef,spawnerRef; ULONGLONG nextResolve; } Owner;
static Owner *owners;
static int ownerCapacity;
static wchar_t requestPath[32768],replyPath[32768];
static char errorText[256];
typedef struct { void *fn; unsigned char *data; int size; void *owned[12]; int count; } Frame;

static int fail(const char *s){snprintf(errorText,sizeof(errorText),"%s",s);return 0;}
static int bindApi(void){
    HMODULE ue=GetModuleHandleW(L"UE4SS.dll"); if(!ue)return fail("UE4SS.dll is not loaded");
#define BIND(var,type,name) var=(type)GetProcAddress(ue,name);if(!var)return fail("Missing export: " #var)
    BIND(publicFindObject,PublicFindObjectFn,"?FindObject@UObjectGlobals@Unreal@RC@@YAPEAVUObject@23@PEAVUClass@23@PEAV423@PEB_W_NPEAUObjectSearcher@23@@Z");
    findObject=resolveByName;
    BIND(findFunction,FindMemberFn,"?GetFunctionByNameInChain@UObject@Unreal@RC@@QEAAPEAVUFunction@23@PEB_W@Z");
    BIND(findProperty,FindMemberFn,"?GetPropertyByNameInChain@UObject@Unreal@RC@@QEAAPEAVFProperty@23@PEB_W@Z");
    BIND(processEvent,EventFn,"?ProcessEvent@UObject@Unreal@RC@@QEAAXPEAVUFunction@23@PEAX@Z");
    BIND(propertyOffset,OffsetFn,"?GetOffset_Internal@FProperty@Unreal@RC@@QEBAAEBHXZ");
    BIND(propertySize,SizeFn,"?GetSize@FProperty@Unreal@RC@@QEBAHXZ");
    BIND(paramsSize,ParamsSizeFn,"?GetParmsSize@UFunction@Unreal@RC@@QEBAAEBGXZ");
    BIND(isA,IsAFn,"?IsA@UObjectBase@Unreal@RC@@QEBA_NPEBVUClass@23@@Z");
    BIND(initialize,InitFn,"?InitializeValue_InContainer@FProperty@Unreal@RC@@QEBAXPEAX@Z");
    BIND(destroy,DestroyFn,"?DestroyValue_InContainer@FProperty@Unreal@RC@@QEAAXPEAX@Z");
    BIND(copyValue,CopyFn,"?CopyCompleteValue@FProperty@Unreal@RC@@QEBAXPEAXPEBX@Z");
    BIND(exportValue,ExportFn,"?ExportTextItem_Direct@FProperty@Unreal@RC@@QEBAXAEAVFString@23@PEBX1PEAVUObject@23@H2@Z");
    BIND(freeEngine,FreeFn,"?Free@FMemory@Unreal@RC@@SAXPEAX@Z");
    BIND(objectValue,ObjectValueFn,"?GetObjectPropertyValue@FObjectPropertyBase@Unreal@RC@@QEBAPEAVUObject@23@PEBX@Z");
    BIND(rootObject,RootFn,"?SetRootSet@UObject@Unreal@RC@@QEAAXXZ");
    BIND(unrootObject,RootFn,"?ClearRootSet@UObject@Unreal@RC@@QEAAXXZ");
    BIND(isRooted,RootCheckFn,"?IsRootSet@UObject@Unreal@RC@@QEAA_NXZ");
    BIND(isChildOf,IsAFn,"?IsChildOf@UStruct@Unreal@RC@@QEBA_NPEBV123@@Z");
    BIND(weakGet,WeakGetFn,"?Get@FWeakObjectPtr@Unreal@RC@@QEBAPEAVUObject@23@XZ");
    BIND(objectIndex,ObjectIndexFn,"?GetInternalIndex@UObjectBase@Unreal@RC@@QEBA?BHXZ");
    BIND(indexItem,IndexItemFn,"?IndexToObject@FUObjectArray@Unreal@RC@@SAPEAUFUObjectItem@23@H@Z");
    BIND(itemSerial,OffsetFn,"?GetSerialNumber@FUObjectItem@Unreal@RC@@QEBAAEBHXZ");
#undef BIND
    return 1;
}
static void *resolveObject(const wchar_t *path,const wchar_t *classPath){
    void *cls=findObject(NULL,NULL,classPath,0);
    if(!cls){fail("Required class not loaded");return NULL;}
    void *o=findObject(NULL,NULL,path,0);
    if(!o||!isA(o,cls)){fail("Object unavailable or wrong class");return NULL;}return o;
}
static int frameOpen(Frame *f,void *object,const wchar_t *name){
    memset(f,0,sizeof(*f));f->fn=findFunction(object,name);
    if(!f->fn)return fail("Required native function unavailable");
    f->size=*paramsSize(f->fn);if(f->size<1||f->size>8192)return fail("Unexpected native parameter size");
    f->data=calloc(1,f->size);return f->data!=NULL||fail("Parameter allocation failed");
}
static void frameClose(Frame *f){
    for(int i=f->count-1;i>=0;i--)destroy(f->owned[i],f->data);
    free(f->data);memset(f,0,sizeof(*f));
}
static void *field(Frame *f,const wchar_t *name,int size,int owned,void **outProp){
    void *p=findProperty(f->fn,name);if(!p){fail("Missing native parameter");return NULL;}
    int offset=*propertyOffset(p),actual=propertySize(p);
    if(actual!=size||offset<0||offset>f->size-size){fail("Native parameter layout mismatch");return NULL;}
    if(owned){if(f->count>=12){fail("Too many owned parameters");return NULL;}initialize(p,f->data);f->owned[f->count++]=p;}
    if(outProp)*outProp=p;return f->data+offset;
}
static int textValue(FILE *reply,const char *label,void *p,const void *value,void *owner){
    FString text={0};exportValue(p,&text,value,NULL,owner,0,NULL);
    int ok=text.count>=0&&text.count<=
#ifdef COMPANION_READ_ONLY_AUDIT
        2097152
#else
        65536
#endif
        &&(!text.count||text.data);
    if(ok){
        fprintf(reply,"%s\t",label);
        if(text.data&&text.count>0){
            int len=text.count-1;int size=WideCharToMultiByte(CP_UTF8,0,text.data,len,NULL,0,NULL,NULL);
            if(size>0){char *bytes=malloc(size);if(!bytes)ok=0;else{WideCharToMultiByte(CP_UTF8,0,text.data,len,bytes,size,NULL,NULL);fwrite(bytes,1,size,reply);free(bytes);}}
        }
        fputc('\n',reply);
    }
    if(text.data)freeEngine(text.data);
    return ok||fail("Unexpected exported value");
}
static int exportField(FILE *reply,void *object,const wchar_t *name,const char *label){
    void *p=findProperty(object,name);if(!p)return fail("Required exported property unavailable");
    int offset=*propertyOffset(p);if(offset<0||offset>65536)return fail("Invalid property offset");
    return textValue(reply,label,p,(unsigned char*)object+offset,object);
}
static int inspectDefinition(FILE *reply,const wchar_t *path){
    void *def=resolveObject(path,L"/Script/Population.CommunityNPCDefinitionBase");if(!def)return 0;
    return exportField(reply,def,L"PawnClass","pawnClass")&&exportField(reply,def,L"AIDefinition","aiClass")&&exportField(reply,def,L"AIReactions","reactionsClass");
}
#ifdef COMPANION_READ_ONLY_AUDIT
/* Separate diagnostic DLL: only typed, read-only exports are reachable. It
 * never replaces the v5 DLL that owns the live population registry. */
static int auditObject(FILE *reply,const wchar_t *path,const wchar_t *kind){
    if(!wcscmp(kind,L"gaze")){
        void *o=resolveObject(path,L"/Script/Dawnwalker.DawnwalkerCommonCharacterBase");
        return o&&exportField(reply,o,L"LookAtTargets","targets");
    }
    if(!wcscmp(kind,L"face")){
        void *o=resolveObject(path,L"/Script/Engine.AnimInstance");if(!o)return 0;
        const wchar_t *keys[]={L"AnimGraphNode_ModifyCurve_5",L"AnimGraphNode_ModifyCurve_6",L"AnimGraphNode_ModifyCurve_7",L"AnimGraphNode_FaceIdle",L"AnimGraphNode_FaceIdle_1",L"AnimGraphNode_CinematicIdle",L"CustomControlValues",L"ParamsByType"};
        for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++)if(findProperty(o,keys[i])){
            char label[96];WideCharToMultiByte(CP_UTF8,0,keys[i],-1,label,sizeof(label),NULL,NULL);
            if(!exportField(reply,o,keys[i],label))return 0;
        }
        return 1;
    }
    if(!wcscmp(kind,L"animationbudget")){
        void *o=resolveObject(path,L"/Script/AnimationBudgetAllocator.SkeletalMeshComponentBudgeted");if(!o)return 0;
        void *prop=findProperty(o,L"bAutoRegisterWithBudgetAllocator");
        if(!prop||*propertyOffset(prop)!=0xf90)return fail("Unexpected animation budget layout");
        uintptr_t base=(uintptr_t)GetModuleHandleW(NULL),*vt=*(uintptr_t**)o;
        fprintf(reply,"tickRva\t%llx\n",(unsigned long long)(vt[0x460/8]-base));
        void *allocator=NULL;memcpy(&allocator,(char*)o+0xf80,8);
        int handle=0;memcpy(&handle,(char*)o+0xf88,4);fprintf(reply,"handle\t%d\n",handle);
        MEMORY_BASIC_INFORMATION region;
        if(allocator&&VirtualQuery(allocator,&region,sizeof(region))&&region.State==MEM_COMMIT){
            uintptr_t *av=*(uintptr_t**)allocator;
            for(int slot=0;slot<0x80;slot+=8)fprintf(reply,"allocator%x\t%llx\n",slot,(unsigned long long)(av[slot/8]-base));
        }
        return 1;
    }
    if(!wcscmp(kind,L"cinematic")){
        void *o=resolveObject(path,L"/Script/CoreUObject.Object");if(!o)return 0;
        const wchar_t *keys[]={L"Nodes",L"LevelSequences",L"CachedData",L"DialogueMovieSet",L"StreamingMarkers",L"PlaybackRootOverride",L"Sequence",L"PlaybackRange",L"TickResolution",L"SectionRange"};
        for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++)if(findProperty(o,keys[i])){
            char label[96];WideCharToMultiByte(CP_UTF8,0,keys[i],-1,label,sizeof(label),NULL,NULL);
            if(!exportField(reply,o,keys[i],label))return 0;
        }
        return 1;
    }
    if(!wcscmp(kind,L"snapshot")){
        void *o=resolveObject(path,L"/Script/CoreUObject.Object");if(!o)return 0;
        /* Fixed read-only fields; missing fields are normal across actor types. */
        const wchar_t *keys[]={L"RecentEvents",L"AIStub",L"CombatComponent",L"CombatSubsystem",L"Capsule",L"Hitboxes",L"Follower",L"Positioning",L"Aggression",L"TicketUser",L"TicketBoard",L"Tags",L"Weapon",L"CurrentCharacterState",L"CombatMode",L"bCanFight",L"bUseTicketUser",L"bUseTicketBoard",L"CharacterStates",L"AssetTreeGeneric",L"LogicTreeGeneric",L"ServiceTree",L"bAlwaysKeepStandardTicket",L"bCanGetTicketWithoutPath",L"ChanceToPassStandardTicketToHelper",L"MinHelperTicketCooldown",L"MaxHelperTicketCooldown",L"EnemyConfig",L"EquipmentSlots",L"CombatAnimationConfigs",L"HandToHandWeapons",L"FistfightWeapons",L"DayStats",L"NightStats",L"bOverrideAttributes",L"CharacterAbilityConfig",L"EquippedWeapon",L"EquippedWeaponOffHand",L"SpawnedWeapons",L"CurrentAttack",L"AttackAbilities",L"NPCAttacks",L"CurrentState",L"Damage",L"DamageAIvsAI",L"MaxHealth",L"Health",L"MeleeDamageMultiplier",L"ClawsDamageMultiplier",L"MagicDamageMultiplier",L"SpawnedAttributes",L"bUseRVOAvoidance",L"AvoidanceConsiderationRadius",L"MaxWalkSpeed",L"DesiredMovementSpeedMultiplier",L"DamageMultiplier",L"FollowerDamageTag",L"Invert",L"MinNPCTimeBetweenAttacks",L"BaseMinimalTimeBetweenAttacks",L"AttackTargetFilterClass"};
        for(unsigned i=0;i<sizeof(keys)/sizeof(keys[0]);i++)if(findProperty(o,keys[i])){
            char label[96];WideCharToMultiByte(CP_UTF8,0,keys[i],-1,label,sizeof(label),NULL,NULL);
            if(!exportField(reply,o,keys[i],label))return 0;
        }
        return 1;
    }
    if(!wcscmp(kind,L"tree")){
        void *o=resolveObject(path,L"/Script/RebelGenericTreeModule.RebelGenericTree");if(!o)return 0;
        return exportField(reply,o,L"RootNodes","roots")&&exportField(reply,o,L"InstanceDataTemplates","instances");
    }
    if(!wcscmp(kind,L"def")){
        void *o=resolveObject(path,L"/Script/RebelAI.RebelAIDef");if(!o)return 0;
        return exportField(reply,o,L"CharacterStates","states")&&exportField(reply,o,L"TicketBoard","ticketBoard")&&exportField(reply,o,L"TicketUser","ticketUser");
    }
    if(!wcscmp(kind,L"attacks")){
        void *o=resolveObject(path,L"/Script/DogwoodCombat.NPCAttacks");if(!o)return 0;
        return exportField(reply,o,L"AttackPatterns","attacks");
    }
    return fail("Unsupported audit kind");
}
#endif
static int probe(FILE *reply){
    void *lib=resolveObject(L"/Script/Engine.Default__KismetSystemLibrary",L"/Script/Engine.KismetSystemLibrary");
    void *factory=resolveObject(L"/Script/Dawnwalker.Default__SpawnPopulationActorAsyncAction",L"/Script/Dawnwalker.SpawnPopulationActorAsyncAction");
    if(!lib||!factory)return 0;
    Frame a={0},b={0};int ok=frameOpen(&a,lib,L"Conv_ClassToSoftClassReference")&&frameOpen(&b,factory,L"RunAsyncAction");
    if(ok){
        void *ap=findProperty(a.fn,L"ReturnValue"),*bp=findProperty(b.fn,L"NPCDefinitionClass");
        if(!ap||!bp)ok=fail("Soft-class parameters missing");
        else fprintf(reply,"softClassBytes\t%d\nspawnSoftClassBytes\t%d\nconverterParams\t%d\nspawnParams\t%d\n",propertySize(ap),propertySize(bp),a.size,b.size);
    }
    frameClose(&b);frameClose(&a);return ok;
}
static int makeSoftClass(Frame *conversion,void *lib,void *cls,void **value){
    if(!frameOpen(conversion,lib,L"Conv_ClassToSoftClassReference"))return 0;
    void *input=field(conversion,L"Class",8,0,NULL);
    void *p=findProperty(conversion->fn,L"ReturnValue");
    if(!input||!p)return 0;
    int size=propertySize(p);if(size!=40)return fail("Unsupported soft-class layout; adapter needs review");
    *value=field(conversion,L"ReturnValue",size,1,NULL);if(!*value)return 0;
    memcpy(input,&cls,8);processEvent(lib,conversion->fn,conversion->data);return 1;
}
static int makeSoftPath(Frame *conversion,void *lib,const wchar_t *path,void **value){
    Frame parsed={0};int ok=0;
    if(wcsncmp(path,L"/Game/_Dawnwalker/",18)||wcslen(path)>1800)return fail("Invalid Dawnwalker class path");
    if(!frameOpen(&parsed,lib,L"MakeSoftClassPath"))return 0;
    FString *input=field(&parsed,L"PathString",16,0,NULL);
    void *result=field(&parsed,L"ReturnValue",32,1,NULL);
    if(!input||!result)goto cleanup;
    /* Borrowed read-only FString input; only game-created outputs are destroyed. */
    input->data=(wchar_t*)path;input->count=(int)wcslen(path)+1;input->capacity=input->count;
    processEvent(lib,parsed.fn,parsed.data);
    if(!frameOpen(conversion,lib,L"Conv_SoftClassPathToSoftClassRef"))goto cleanup;
    void *p=NULL,*dest=field(conversion,L"SoftClassPath",32,1,&p);
    *value=field(conversion,L"ReturnValue",40,1,NULL);
    if(!dest||!*value)goto cleanup;
    copyValue(p,dest,result);processEvent(lib,conversion->fn,conversion->data);ok=1;
cleanup: frameClose(&parsed);return ok;
}
static int loadClass(FILE *reply,const wchar_t *path){
    void *lib=resolveObject(L"/Script/Engine.Default__KismetSystemLibrary",L"/Script/Engine.KismetSystemLibrary");if(!lib)return 0;
    Frame reference={0},load={0};void *soft=NULL;int ok=0;
    if(!makeSoftPath(&reference,lib,path,&soft)||!frameOpen(&load,lib,L"LoadClassAsset_Blocking"))goto cleanup;
    void *p=NULL,*rp=NULL,*input=field(&load,L"AssetClass",40,1,&p),*result=field(&load,L"ReturnValue",8,0,&rp);
    if(!input||!result)goto cleanup;
    copyValue(p,input,soft);processEvent(lib,load.fn,load.data);
    void *cls=NULL;memcpy(&cls,result,8);if(!cls){fail("Native class loader returned no class");goto cleanup;}
    ok=textValue(reply,"class",rp,result,lib);
cleanup: frameClose(&load);frameClose(&reference);return ok;
}
/* Use the engine's latent asynchronous loader. An unbound completion delegate
 * and INDEX_NONE linkage need no custom UObject callback. Lua polls the loaded
 * class by its known path, without calling a blocking loader on the game thread. */
static int loadClassAsync(FILE *reply,const wchar_t *contextPath,const wchar_t *path){
    void *context=resolveObject(contextPath,L"/Script/Engine.Pawn");
    void *lib=resolveObject(L"/Script/Engine.Default__KismetSystemLibrary",L"/Script/Engine.KismetSystemLibrary");
    void *latentType=findObject(NULL,NULL,L"/Script/Engine.LatentActionInfo",0);
    if(!context||!lib||!latentType)return fail("Async loading context unavailable");
    Frame reference={0},load={0};void *soft=NULL;int ok=0;
    if(!makeSoftPath(&reference,lib,path,&soft)||!frameOpen(&load,lib,L"LoadAssetClass"))goto cleanup;
    void *sp=NULL,*input=field(&load,L"AssetClass",40,1,&sp);
    void *world=field(&load,L"WorldContextObject",8,0,NULL);
    void *delegate=field(&load,L"OnLoaded",16,1,NULL);
    void *latent=field(&load,L"LatentInfo",24,1,NULL);
    if(!input||!world||!delegate||!latent)goto cleanup;
    void *link=findProperty(latentType,L"Linkage"),*uuid=findProperty(latentType,L"UUID"),*callback=findProperty(latentType,L"CallbackTarget"),*execution=findProperty(latentType,L"ExecutionFunction");
    if(!link||!uuid||!callback||!execution||propertySize(link)!=4||*propertyOffset(link)!=0||propertySize(uuid)!=4||*propertyOffset(uuid)!=4||propertySize(callback)!=8||*propertyOffset(callback)!=16||propertySize(execution)!=8||*propertyOffset(execution)!=8){fail("Unexpected latent action layout");goto cleanup;}
    static int sequence=0;int identifier=0x43000000+(++sequence),none=-1;
    memcpy(latent,&none,4);memcpy((unsigned char*)latent+4,&identifier,4);memcpy((unsigned char*)latent+16,&context,8);
    copyValue(sp,input,soft);memcpy(world,&context,8);
    ULONGLONG started=GetTickCount64();processEvent(lib,load.fn,load.data);
    fprintf(reply,"requestMs\t%llu\n",(unsigned long long)(GetTickCount64()-started));ok=1;
cleanup: frameClose(&load);frameClose(&reference);return ok;
}
#ifdef COMPANION_ASSET_LOADER
#include "companion_asset_loader.h"
#endif
#ifdef COMPANION_PROTECTION
#include "companion_protection.h"
#endif
#ifdef COMPANION_SIMULATION
#include "companion_simulation.h"
#endif
#ifdef COMPANION_GAZE
#include "companion_gaze.h"
#endif
static int objectPath(void *p,const void *value,void *parent,wchar_t *destination){
    FString text={0};exportValue(p,&text,value,NULL,parent,0,NULL);int ok=0;
    if(text.data&&text.count>1&&text.count<=4096){
        wchar_t *first=wcschr(text.data,L'\'');wchar_t *last=first?wcschr(first+1,L'\''):NULL;
        if(first&&last&&first[1]==L'/'&&last-first<2048){wmemcpy(destination,first+1,last-first-1);destination[last-first-1]=0;ok=1;}
    }
    if(text.data)freeEngine(text.data);return ok||fail("Object path export unavailable");
}
static int ownedSlot(const wchar_t *path){
    for(int i=0;i<ownerCapacity;i++)if(!wcscmp(owners[i].action,path))return i;
    if(*path)return -1;
    if(ownerCapacity>INT_MAX/2){fail("Companion registry allocation overflow");return -1;}
  int next=ownerCapacity?ownerCapacity*2:8;
    if(next<=ownerCapacity||(size_t)next>SIZE_MAX/sizeof(Owner)){fail("Population registry allocation overflow");return -1;}
    Owner *grown=realloc(owners,(size_t)next*sizeof(Owner));
    if(!grown){fail("Population registry allocation failed");return -1;}
    memset(grown+ownerCapacity,0,(size_t)(next-ownerCapacity)*sizeof(Owner));
    int slot=ownerCapacity;owners=grown;ownerCapacity=next;return slot;
}
static int captureWeak(WeakObject *ref,void *object){
    *ref=(WeakObject){0,0};if(!object)return 0;
    int index=objectIndex(object);if(index<0)return 0;
    void *item=indexItem(index);if(!item)return 0;
    int serial=*itemSerial(item);if(serial<=0)return 0;
    WeakObject candidate={index,serial};if(weakGet(&candidate)!=object)return 0;
    *ref=candidate;return 1;
}
static void *liveObject(const wchar_t *path,const wchar_t *classPath){
    if(!*path)return NULL;
    void *cls=findObject(NULL,NULL,classPath,0),*object=findObject(NULL,NULL,path,0);
    return cls&&object&&isA(object,cls)?object:NULL;
}
static int captureSpawner(int slot,void *action){
    void *p=findProperty(action,L"Spawner");if(!p||propertySize(p)!=8)return fail("Spawner property missing");
    int offset=*propertyOffset(p);if(offset<0||offset>1024)return fail("Invalid spawner offset");
    void *spawner=objectValue(p,(unsigned char*)action+offset);
    if(!spawner)return 1;
    wchar_t path[2048]={0};if(!objectPath(p,(unsigned char*)action+offset,action,path))return 0;
    if(*owners[slot].spawner&&wcscmp(owners[slot].spawner,path))return fail("Population owner changed unexpectedly");
    if(!*owners[slot].spawner){
        wcscpy(owners[slot].spawner,path);
        captureWeak(&owners[slot].spawnerRef,spawner);
        /* The async action is temporary; the actual population owner must
         * remain referenced while its companion is in the party. */
        if(!isRooted(spawner)){rootObject(spawner);owners[slot].addedSpawnerRoot=1;}
    }
    return 1;
}
static int stopSlot(int slot){
    if(slot<0||slot>=ownerCapacity)return fail("Invalid population owner slot");
    void *action=weakGet(&owners[slot].actionRef);
    /* A never-serialized action may have no borrowable handle. Cleanup alone
     * may resolve its recorded path; recurring polls never search it once the
     * durable spawner has been captured. */
    if(!action&&!owners[slot].actionRef.serial)action=liveObject(owners[slot].action,L"/Script/Dawnwalker.SpawnPopulationActorAsyncAction");
    if(!*owners[slot].spawner&&action&&!captureSpawner(slot,action))return 0;
    void *spawner=weakGet(&owners[slot].spawnerRef);
    if(!spawner&&!owners[slot].spawnerRef.serial)spawner=liveObject(owners[slot].spawner,L"/Script/Dawnwalker.DogwoodPopulationSimpleSpawner");
    if(spawner&&!owners[slot].spawnerRef.serial)captureWeak(&owners[slot].spawnerRef,spawner);
    /* Clear our action root while the resolved pointer is known live, before
     * Stop can dispatch callbacks. The durable spawner owns the population. */
    if(action)unrootObject(action);
    if(spawner){void *stop=findFunction(spawner,L"Stop");if(!stop||*paramsSize(stop)!=0)return fail("Spawner stop function unavailable");processEvent(spawner,stop,NULL);}
    /* Stop can dispatch destruction callbacks. Revalidate after that boundary. */
    spawner=weakGet(&owners[slot].spawnerRef);
    if(!spawner&&!owners[slot].spawnerRef.serial)spawner=liveObject(owners[slot].spawner,L"/Script/Dawnwalker.DogwoodPopulationSimpleSpawner");
    if(spawner&&owners[slot].addedSpawnerRoot)unrootObject(spawner);
    memset(&owners[slot],0,sizeof(Owner));return 1;
}
static int spawn(FILE *reply,wchar_t lines[][2048]){
    void *player=resolveObject(lines[2],L"/Script/Engine.Pawn");
    void *npc=resolveObject(lines[3],L"/Script/CoreUObject.Class");
    void *ai=wcscmp(lines[4],L"None")==0?NULL:resolveObject(lines[4],L"/Script/CoreUObject.Class");
    void *lib=resolveObject(L"/Script/Engine.Default__KismetSystemLibrary",L"/Script/Engine.KismetSystemLibrary");
    void *factory=resolveObject(L"/Script/Dawnwalker.Default__SpawnPopulationActorAsyncAction",L"/Script/Dawnwalker.SpawnPopulationActorAsyncAction");
    double xyz[3];float yaw; wchar_t extra;
    if(!player||!npc||(!ai&&wcscmp(lines[4],L"None"))||!lib||!factory)return 0;
    void *npcBase=findObject(NULL,NULL,L"/Script/Population.CommunityNPCDefinitionBase",0);
    void *aiBase=findObject(NULL,NULL,L"/Script/Population.AIDefinition",0);
    if(!npcBase||!isChildOf(npc,npcBase)|| (ai&&(!aiBase||!isChildOf(ai,aiBase))))return fail("Definition class is incompatible with the population factory");
    int freeSlot=ownedSlot(L"");if(freeSlot<0)return 0;
    if(wcsncmp(lines[3],L"/Game/_Dawnwalker/",18)||(!ai?0:wcsncmp(lines[4],L"/Game/_Dawnwalker/",18)))return fail("Definition outside Dawnwalker content");
    if(swscanf(lines[5],L"%lf %lf %lf %lc",&xyz[0],&xyz[1],&xyz[2],&extra)!=3||swscanf(lines[6],L"%f %lc",&yaw,&extra)!=1)return fail("Invalid spawn transform");
    for(int i=0;i<3;i++)if(!isfinite(xyz[i])||fabs(xyz[i])>10000000)return fail("Invalid spawn location");
    if(!isfinite(yaw))return fail("Invalid rotation");
    Frame n={0},a={0},s={0};void *nv=NULL,*av=NULL;int ok=0;
    if(!makeSoftClass(&n,lib,npc,&nv)||!makeSoftClass(&a,lib,ai,&av)||!frameOpen(&s,factory,L"RunAsyncAction"))goto cleanup;
    void *np=NULL,*ap=NULL,*rp=NULL;
    void *context=field(&s,L"WorldContext",8,0,NULL),*destN=field(&s,L"NPCDefinitionClass",40,1,&np),*destA=field(&s,L"AIDefinitionClass",40,1,&ap);
    void *loc=field(&s,L"Location",24,0,NULL),*rot=field(&s,L"Rotation",4,0,NULL),*result=field(&s,L"ReturnValue",8,0,&rp);
    if(!context||!destN||!destA||!loc||!rot||!result)goto cleanup;
    memcpy(context,&player,8);copyValue(np,destN,nv);copyValue(ap,destA,av);memcpy(loc,xyz,24);memcpy(rot,&yaw,4);
    fprintf(reply,"stage\tpopulation-factory\n");fflush(reply);
    ULONGLONG requested=GetTickCount64();processEvent(factory,s.fn,s.data);
    fprintf(reply,"factoryMs\t%llu\n",(unsigned long long)(GetTickCount64()-requested));
    void *action=NULL;memcpy(&action,result,8);if(!action){fail("Population factory returned no action");goto cleanup;}
    if(!objectPath(rp,result,factory,owners[freeSlot].action))goto cleanup;
    rootObject(action);
    void *activate=findFunction(action,L"Activate");
    if(!activate||*paramsSize(activate)!=0){stopSlot(freeSlot);fail("Async action activation unavailable");goto cleanup;}
    fprintf(reply,"stage\tactivate-population\n");fflush(reply);
    requested=GetTickCount64();processEvent(action,activate,NULL);
    fprintf(reply,"activateMs\t%llu\n",(unsigned long long)(GetTickCount64()-requested));
    fprintf(reply,"stage\tborrow-existing-identities\n");fflush(reply);
    captureWeak(&owners[freeSlot].actionRef,action);
    ok=captureSpawner(freeSlot,action)&&textValue(reply,"action",rp,result,factory);
    if(!ok)stopSlot(freeSlot);
cleanup: frameClose(&s);frameClose(&a);frameClose(&n);return ok;
}
static int pollSpawner(FILE *reply,const wchar_t *path){
    int slot=ownedSlot(path);if(slot<0)return fail("Action is not owned by the companion bridge");
    if(!*owners[slot].spawner){
        void *action=weakGet(&owners[slot].actionRef);
        if(!action&&!owners[slot].actionRef.serial&&GetTickCount64()>=owners[slot].nextResolve){
            owners[slot].nextResolve=GetTickCount64()+5000;
            action=liveObject(path,L"/Script/Dawnwalker.SpawnPopulationActorAsyncAction");
            if(action)captureWeak(&owners[slot].actionRef,action);
        }
        if(action&&!captureSpawner(slot,action))return 0;
    }
    void *spawner=weakGet(&owners[slot].spawnerRef);
    if(!spawner&&*owners[slot].spawner&&!owners[slot].spawnerRef.serial&&GetTickCount64()>=owners[slot].nextResolve){
        owners[slot].nextResolve=GetTickCount64()+5000;
        spawner=liveObject(owners[slot].spawner,L"/Script/Dawnwalker.DogwoodPopulationSimpleSpawner");
        if(spawner)captureWeak(&owners[slot].spawnerRef,spawner);
    }
    if(!spawner)return fail("Spawner not ready or world unloaded");
    fprintf(reply,"spawner\t%ls\n",owners[slot].spawner);
    fprintf(reply,"handleMode\t%s\n",owners[slot].spawnerRef.serial?"borrowed-engine-serial":"bounded-path-fallback");
    return exportField(reply,spawner,L"SpawnedPawns","pawns");
}
__declspec(dllexport) int companion_native_run(void *unusedLuaState){
    (void)unusedLuaState;errorText[0]=0;
    lookupMilliseconds=0;lookupCalls=0;ULONGLONG operationStarted=GetTickCount64();
    DWORD n=GetModuleFileNameW(module,requestPath,32768);if(!n||n>32000)return 0;
    wchar_t *slash=wcsrchr(requestPath,L'\\');if(!slash)return 0;*slash=0;
    wcscat(requestPath,L"\\..\\..\\runtime\\companion-native-request.txt");
    wcscpy(replyPath,requestPath);slash=wcsrchr(replyPath,L'\\');wcscpy(slash+1,L"companion-native-reply.txt");
    FILE *input=_wfopen(requestPath,L"rb");if(!input)return 0;
    char bytes[16384];size_t size=fread(bytes,1,sizeof(bytes)-1,input);int oversized=!feof(input);fclose(input);bytes[size]=0;
    FILE *reply=_wfopen(replyPath,L"wb");if(!reply)return 0;
    wchar_t lines[8][2048];memset(lines,0,sizeof(lines));int count=0,valid=1;
    char *cursor=bytes;
    while(*cursor&&count<8){char *end=strchr(cursor,'\n');if(end)*end=0;size_t len=strlen(cursor);if(len&&cursor[len-1]=='\r')cursor[len-1]=0;
        if(!MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,cursor,-1,lines[count++],2048)){valid=0;break;}if(!end)break;cursor=end+1;}
    if(oversized||!valid||count<2){fprintf(reply,"invalid\nERROR\tInvalid request\n");fclose(reply);return 0;}
    for(wchar_t *c=lines[0];*c;c++)if(!((*c>='a'&&*c<='z')||(*c>='A'&&*c<='Z')||(*c>='0'&&*c<='9')||*c=='_'||*c=='-'))valid=0;
    if(!valid||wcslen(lines[0])>80){fclose(reply);return 0;}
    fprintf(reply,"%ls\n",lines[0]);int ok=0;
    if(bindApi()){
#ifdef COMPANION_READ_ONLY_AUDIT
        if(!wcscmp(lines[1],L"audit")&&count==4)ok=auditObject(reply,lines[2],lines[3]);
        else fail("Read-only diagnostic DLL");
#elif defined(COMPANION_GAZE)
        if(!wcscmp(lines[1],L"gazeinspect")&&count==3)ok=inspectGaze(reply,lines[2]);
        else if(!wcscmp(lines[1],L"gazeadd")&&count==4)ok=addCameraGaze(reply,lines[2],lines[3]);
        else fail("Unsupported gaze operation");
#elif defined(COMPANION_SIMULATION)
        if(!wcscmp(lines[1],L"animationbudget")&&count==4)ok=simulationBudget(reply,lines[2],lines[3]);
        else fail("Simulation helper accepts only animationbudget");
#elif defined(COMPANION_ASSET_LOADER)
        if(!wcscmp(lines[1],L"loadassetasync")&&count==4)ok=loadObjectAsync(reply,lines[2],lines[3]);
        else fail("Asset-loading DLL accepts only loadassetasync");
#elif defined(COMPANION_PROTECTION)
        if(!wcscmp(lines[1],L"protectprepare")&&count==4)ok=prepareProtection(reply,lines[2],lines[3]);
        else if(!wcscmp(lines[1],L"protecttag")&&count==5){if(wcscmp(lines[4],L"0")&&wcscmp(lines[4],L"1"))fail("Invalid protection tag action");else ok=tagProtectionSource(reply,lines[2],lines[3],!wcscmp(lines[4],L"1"));}
        else if(!wcscmp(lines[1],L"protectapply")&&count==5)ok=applyProtection(reply,lines[2],lines[3],lines[4]);
        else if(!wcscmp(lines[1],L"protectremove")&&count==5){wchar_t tail=0;long v=0;if(swscanf(lines[3],L"%ld%lc",&v,&tail)!=1||v<=0||v>INT_MAX)fail("Invalid protection handle");else ok=removeProtection(reply,lines[2],(int32_t)v,lines[4]);}
        else if(!wcscmp(lines[1],L"protectrelease")&&count==3)ok=releaseProtection(reply,lines[2]);
        else fail("Protection DLL accepts only protect operations");
#else
        if(!wcscmp(lines[1],L"probe"))ok=probe(reply);
        else if(!wcscmp(lines[1],L"inspect")&&count==3)ok=inspectDefinition(reply,lines[2]);
        else if(!wcscmp(lines[1],L"loadclass")&&count==3)ok=loadClass(reply,lines[2]);
        else if(!wcscmp(lines[1],L"loadclassasync")&&count==4)ok=loadClassAsync(reply,lines[2],lines[3]);
        else if(!wcscmp(lines[1],L"spawn")&&count==7)ok=spawn(reply,lines);
        else if(!wcscmp(lines[1],L"poll")&&count==3)ok=pollSpawner(reply,lines[2]);
        else if(!wcscmp(lines[1],L"stop")&&count==3){int slot=ownedSlot(lines[2]);ok=slot>=0?stopSlot(slot):fail("Action is not owned by the companion bridge");}
        else if(!wcscmp(lines[1],L"stopall")&&count==2){ok=1;for(int i=0;i<ownerCapacity;i++)if(*owners[i].action&&!stopSlot(i))ok=0;}
        else fail("Unsupported native operation");
#endif
    }
    fprintf(reply,"lookupMs\t%llu\nlookupCalls\t%u\nnativeMs\t%llu\n",(unsigned long long)lookupMilliseconds,lookupCalls,(unsigned long long)(GetTickCount64()-operationStarted));
    fprintf(reply,"%s\t%s\n",ok?"OK":"ERROR",ok?"Completed":errorText);fclose(reply);return 0;
}
BOOL WINAPI DllMain(HINSTANCE handle,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){module=handle;DisableThreadLibraryCalls(handle);}return TRUE;}
