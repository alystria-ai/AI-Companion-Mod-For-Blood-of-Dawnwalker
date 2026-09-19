/* Offline mock test. No game is opened, attached to, or called. */
#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../bridge/native-source/companion_native.c"
#include <assert.h>
static int actionClass,spawnerClass,spawnerObject,stopFunction;
static int spawnerAlive=1,stopAvailable=1,stops,unroots;
static int lookups;
static int observedIndex=42,observedSerial=17,weakReads;
static int fakeObjectIndex(const void *o){assert(o==&spawnerObject);return observedIndex;}
static void *fakeItem(int index){return index==42?&spawnerObject:NULL;}
static const int *fakeSerial(const void *item){assert(item==&spawnerObject);return &observedSerial;}
static unsigned short zeroParams;
static int mapProperty,mapOffset;
static void *fakeProperty(void *o,const wchar_t *name){assert(o==&spawnerObject);return !wcscmp(name,L"SpawnedPawns")?&mapProperty:NULL;}
static const int *fakeOffset(const void *p){assert(p==&mapProperty);return &mapOffset;}
static void fakeExport(const void *p,FString *s,const void *v,const void *d,void *o,int flags,void *root){
 (void)d;(void)flags;(void)root;assert(p==&mapProperty&&v==&spawnerObject&&o==&spawnerObject);s->data=NULL;s->count=0;
}
static void *fakeFind(void *cls,void *outer,const wchar_t *path,unsigned char exact){
 (void)cls;(void)outer;(void)exact;
 lookups++;
 if(!wcscmp(path,L"/Script/Dawnwalker.SpawnPopulationActorAsyncAction"))return &actionClass;
 if(!wcscmp(path,L"/Script/Dawnwalker.DogwoodPopulationSimpleSpawner"))return &spawnerClass;
 if(!wcscmp(path,L"/World/OwnedSpawner")&&spawnerAlive)return &spawnerObject;
 return NULL; /* Async action is already collected, as in the live failure. */
}
static unsigned char fakeIsA(const void *object,const void *cls){return object==&spawnerObject&&cls==&spawnerClass;}
static void *fakeFunction(void *object,const wchar_t *name){assert(object==&spawnerObject);return stopAvailable&&!wcscmp(name,L"Stop")?&stopFunction:NULL;}
static const unsigned short *fakeParams(const void *fn){assert(fn==&stopFunction);return &zeroParams;}
static void fakeEvent(void *object,void *fn,void *args){assert(object==&spawnerObject&&fn==&stopFunction&&args==NULL);stops++;}
static void fakeUnroot(void *object){assert(object==&spawnerObject);unroots++;}
static void *fakeWeakGet(const WeakObject *ref){weakReads++;return ref->index==42&&ref->serial==17&&spawnerAlive?&spawnerObject:NULL;}
static void setup(void){assert(ownedSlot(L"")==0);wcscpy(owners[0].action,L"/World/RetiredAction");wcscpy(owners[0].spawner,L"/World/OwnedSpawner");owners[0].spawnerRef=(WeakObject){42,17};owners[0].actionRef=(WeakObject){43,19};}
int main(void){
 findObject=fakeFind;isA=fakeIsA;findFunction=fakeFunction;paramsSize=fakeParams;processEvent=fakeEvent;unrootObject=fakeUnroot;
 weakGet=fakeWeakGet;
 objectIndex=fakeObjectIndex;indexItem=fakeItem;itemSerial=fakeSerial;
 WeakObject ref={99,99};observedSerial=0;
 assert(!captureWeak(&ref,&spawnerObject)&&ref.serial==0&&weakReads==0); /* Fresh engine object: NO allocator and NO Get. */
 observedSerial=17;assert(captureWeak(&ref,&spawnerObject)&&ref.serial==17&&ref.index==42);
 observedSerial=18;assert(!captureWeak(&ref,&spawnerObject)&&ref.serial==0); /* Serial changed before resolution. */
 observedIndex=-1;assert(!captureWeak(&ref,&spawnerObject));observedIndex=42;observedSerial=17;
 findProperty=fakeProperty;propertyOffset=fakeOffset;exportValue=fakeExport;
 setup();owners[0].spawnerRef=(WeakObject){0,0};observedSerial=0;
 FILE *fallback=tmpfile();assert(fallback);
 assert(pollSpawner(fallback,L"/World/RetiredAction"));assert(lookups==2&&owners[0].spawnerRef.serial==0);
 assert(!pollSpawner(fallback,L"/World/RetiredAction")&&lookups==2); /* Five-second fallback throttle. */
 owners[0].nextResolve=0;observedSerial=17;
 assert(pollSpawner(fallback,L"/World/RetiredAction")&&owners[0].spawnerRef.serial==17);assert(lookups==4);
 assert(pollSpawner(fallback,L"/World/RetiredAction")&&lookups==4); /* Engine assigned identity: now constant-time. */
 fclose(fallback);memset(owners,0,(size_t)ownerCapacity*sizeof(Owner));lookups=0;
 setup();FILE *reply=tmpfile();assert(reply);
 for(int i=0;i<250;i++)assert(pollSpawner(reply,L"/World/RetiredAction"));
 spawnerAlive=0;assert(!pollSpawner(reply,L"/World/RetiredAction"));spawnerAlive=1;
 assert(!pollSpawner(reply,L"/World/SomeoneElsesAction")&&lookups==0);fclose(reply);
 memset(owners,0,(size_t)ownerCapacity*sizeof(Owner));
 setup();assert(stopSlot(0));assert(stops==1&&!*owners[0].action);
 assert(stopSlot(0)&&stops==1); /* Idempotent cleanup. */
 setup();spawnerAlive=0;assert(stopSlot(0)&&stops==1&&!*owners[0].action);
 setup();spawnerAlive=1;stopAvailable=0;assert(!stopSlot(0)&&*owners[0].action); /* Keep ownership on failure. */
 stopAvailable=1;assert(stopSlot(0)&&stops==2);
 setup();owners[0].addedSpawnerRoot=1;assert(stopSlot(0)&&unroots==1);
 setup();assert(stopSlot(0)&&unroots==1); /* Do not remove a pre-existing root. */
 setup();owners[0].spawnerRef.serial=18;assert(stopSlot(0)&&stops==4); /* Reused object-array slot is not our owner. */
 assert(lookups==0); /* Cleanup cannot rescan a missing async action. */
 for(int i=0;i<40;i++){int slot=ownedSlot(L"");assert(slot==i);swprintf(owners[slot].action,2048,L"/World/Clone%d",i);owners[slot].actionRef=(WeakObject){43,19};}
 assert(ownerCapacity>=40&&ownedSlot(L"/World/Clone33")==33);
 assert(stopSlot(17)&&ownedSlot(L"")==17);
 for(int i=0;i<ownerCapacity;i++)assert(stopSlot(i));free(owners);
 assert(lookups==0);
 puts("PASS: serial-checked owner lifetime, zero path searches during cleanup, growth beyond eight and freed-slot reuse.");return 0;
}
