/* Source-aware GameplayEffect immunity support. All compound values are built
 * and copied in reflected native frames; Lua never marshals a TArray here. */
typedef struct { void *data; int32_t count,capacity; } ScriptArray;
static const wchar_t protectionTag[]=L"DawnwalkerConvai.Source.OwnedCompanion";
static wchar_t preparedEffect[2048],activeEffect[2048],activeAsc[2048];
static unsigned char activeHandle[8];
static int preparedAddedRoot,hasActive;
static int captureWeak(WeakObject *ref,void *object);
static WeakObject preparedRef,activeAscRef;

static void *protectionLibrary(void){
    return resolveObject(L"/Script/GameplayAbilities.Default__AbilitySystemBlueprintLibrary",L"/Script/GameplayAbilities.AbilitySystemBlueprintLibrary");
}
static void *tagLibrary(void){
    return resolveObject(L"/Script/GameplayTags.Default__BlueprintGameplayTagLibrary",L"/Script/GameplayTags.BlueprintGameplayTagLibrary");
}
static int makeName(Frame *f,void **value,const wchar_t *text){
    void *lib=resolveObject(L"/Script/Engine.Default__KismetStringLibrary",L"/Script/Engine.KismetStringLibrary");
    if(!lib||!frameOpen(f,lib,L"Conv_StringToName"))return 0;
    FString *input=field(f,L"InString",16,0,NULL);
    *value=field(f,L"ReturnValue",8,0,NULL);
    if(!input||!*value)return 0;
    input->data=(wchar_t*)text;input->count=(int)wcslen(text)+1;input->capacity=input->count;
    processEvent(lib,f->fn,f->data);return 1;
}
static int makeTagContainer(Frame *f,void **value,const wchar_t *name){
    Frame n={0};void *tagName=NULL;void *lib=tagLibrary();int ok=0;
    if(!lib||!makeName(&n,&tagName,name)||!frameOpen(f,lib,L"MakeGameplayTagContainerFromTag"))goto cleanup;
    void *tag=field(f,L"SingleTag",8,0,NULL);
    *value=field(f,L"ReturnValue",32,1,NULL);
    if(!tag||!*value)goto cleanup;
    /* FGameplayTag contains exactly one reflected FName in this build. */
    memcpy(tag,tagName,8);processEvent(lib,f->fn,f->data);ok=1;
cleanup: frameClose(&n);return ok;
}
static int makeSourceQuery(Frame *query,void **value,Frame *container,void **tags){
    void *lib=tagLibrary();void *source=NULL,*dest=NULL;
    if(!lib||!makeTagContainer(container,tags,protectionTag)||!frameOpen(query,lib,L"MakeGameplayTagQuery_MatchAnyTags"))return 0;
    dest=field(query,L"InTags",32,1,&source);
    *value=field(query,L"ReturnValue",72,1,NULL);
    if(!dest||!*value)return 0;
    copyValue(source,dest,*tags);processEvent(lib,query->fn,query->data);return 1;
}
static int queryMatches(void *container,void *query,int *result){
    void *lib=tagLibrary();Frame check={0};int ok=0;void *cp=NULL,*qp=NULL;
    if(!lib||!frameOpen(&check,lib,L"DoesContainerMatchTagQuery"))return 0;
    void *c=field(&check,L"TagContainer",32,1,&cp),*q=field(&check,L"TagQuery",72,1,&qp);
    unsigned char *r=field(&check,L"ReturnValue",1,0,NULL);
    if(!c||!q||!r)goto cleanup;
    copyValue(cp,c,container);copyValue(qp,q,query);processEvent(lib,check.fn,check.data);
    *result=*r!=0;ok=1;
cleanup:frameClose(&check);return ok;
}
static int prepareProtection(FILE *reply,const wchar_t *effectPath,const wchar_t *componentPath){
    if(*preparedEffect&&wcscmp(preparedEffect,effectPath))return fail("A different protection effect is already prepared");
    void *effect=resolveObject(effectPath,L"/Script/GameplayAbilities.GameplayEffect");
    void *component=resolveObject(componentPath,L"/Script/GameplayAbilities.ImmunityGameplayEffectComponent");
    void *queryType=findObject(NULL,NULL,L"/Script/GameplayAbilities.GameplayEffectQuery",0);
    if(!effect||!component||!queryType)return 0;
    Frame query={0},yes={0},no={0};void *built=NULL,*yesTags=NULL,*noTags=NULL;int ok=0,positive=0,negative=1;
    if(!makeSourceQuery(&query,&built,&yes,&yesTags)||!makeTagContainer(&no,&noTags,L"RebelAI.Flag.DealFollowerDamage"))goto cleanup;
    if(!queryMatches(yesTags,built,&positive)||!queryMatches(noTags,built,&negative))goto cleanup;
    if(!positive||negative){fail("Native source query did not discriminate its marker");goto cleanup;}
    void *sourceQuery=findProperty(queryType,L"SourceAggregateTagQuery");
    void *immunityArray=findProperty(component,L"ImmunityQueries");
    void *legacy=findProperty(effect,L"GrantedApplicationImmunityQuery");
    void *components=findProperty(effect,L"GEComponents");
    int so=sourceQuery?*propertyOffset(sourceQuery):-1;
    if(!sourceQuery||!immunityArray||!legacy||!components||propertySize(sourceQuery)!=72||propertySize(immunityArray)!=16||propertySize(legacy)<so+72||propertySize(components)!=16){fail("Protection property layout mismatch");goto cleanup;}
    int io=*propertyOffset(immunityArray),lo=*propertyOffset(legacy),co=*propertyOffset(components);
    if(io<0||io>4096||lo<0||lo>4096||so<0||so>2048||co<0||co>4096){fail("Protection property offset out of range");goto cleanup;}
    ScriptArray *queries=(ScriptArray*)((unsigned char*)component+io);
    ScriptArray *parts=(ScriptArray*)((unsigned char*)effect+co);
    if(!queries->data||queries->count!=1||queries->capacity<1){fail("ImmunityQueries must be imported with exactly one element");goto cleanup;}
    if(!parts->data||parts->count!=1||parts->capacity<1||*(void**)parts->data!=component){fail("GEComponents must contain exactly the supplied component");goto cleanup;}
    copyValue(sourceQuery,(unsigned char*)queries->data+so,built);
    copyValue(sourceQuery,(unsigned char*)effect+lo+so,built);
    if(!queryMatches(yesTags,(unsigned char*)queries->data+so,&positive)||!queryMatches(noTags,(unsigned char*)queries->data+so,&negative))goto cleanup;
    if(!positive||negative){fail("Copied component query failed validation");goto cleanup;}
    if(!*preparedEffect){
        if(!isRooted(effect)){rootObject(effect);preparedAddedRoot=1;}
        wcsncpy(preparedEffect,effectPath,2047);preparedEffect[2047]=0;
        captureWeak(&preparedRef,effect);
    }
    fprintf(reply,"positive\t1\nnegative\t0\n");ok=1;
cleanup:frameClose(&no);frameClose(&query);frameClose(&yes);return ok;
}
static int tagProtectionSource(FILE *reply,const wchar_t *actorPath,const wchar_t *ascPath,int add){
    void *actorClass=findObject(NULL,NULL,L"/Script/Engine.Actor",0),*ascClass=findObject(NULL,NULL,L"/Script/GameplayAbilities.AbilitySystemComponent",0);
    void *actor=findObject(NULL,NULL,actorPath,0),*expected=findObject(NULL,NULL,ascPath,0);void *lib=protectionLibrary();
    Frame tags={0},asc={0},change={0};void *container=NULL;int ok=0;
    if(!actorClass||!ascClass||!lib)return 0;
    if(!actor||!expected||!isA(actor,actorClass)||!isA(expected,ascClass)){
        if(!add){fprintf(reply,"changed\t0\nexpired\t1\n");return 1;}
        return fail("Source actor or expected ability system is unavailable");
    }
    if(!makeTagContainer(&tags,&container,protectionTag)||!frameOpen(&asc,lib,L"GetAbilitySystemComponent"))goto cleanup;
    void *a=field(&asc,L"Actor",8,0,NULL),*ar=field(&asc,L"ReturnValue",8,0,NULL);if(!a||!ar)goto cleanup;
    memcpy(a,&actor,8);processEvent(lib,asc.fn,asc.data);void *actorAsc=NULL;memcpy(&actorAsc,ar,8);
    if(!actorAsc||actorAsc!=expected){fail("Source actor resolved a different ability system component");goto cleanup;}
    if(!frameOpen(&change,lib,add?L"AddLooseGameplayTags":L"RemoveLooseGameplayTags"))goto cleanup;
    void *cp=NULL,*ca=field(&change,L"Actor",8,0,NULL),*ct=field(&change,L"GameplayTags",32,1,&cp);
    unsigned char *rep=field(&change,L"bShouldReplicate",1,0,NULL),*result=field(&change,L"ReturnValue",1,0,NULL);
    if(!ca||!ct||!rep||!result)goto cleanup;
    memcpy(ca,&actor,8);copyValue(cp,ct,container);*rep=0;processEvent(lib,change.fn,change.data);
    if(!*result){fail(add?"Adding source marker failed":"Removing source marker failed");goto cleanup;}
    fprintf(reply,"changed\t1\n");ok=1;
cleanup:frameClose(&change);frameClose(&asc);frameClose(&tags);return ok;
}
static int applyProtection(FILE *reply,const wchar_t *ascPath,const wchar_t *effectPath,const wchar_t *playerPath){
    if(!*preparedEffect||wcscmp(preparedEffect,effectPath))return fail("Effect is not the prepared protection effect");
    if(hasActive)return fail("Protection effect is already active");
    void *asc=resolveObject(ascPath,L"/Script/GameplayAbilities.AbilitySystemComponent");
    void *effect=resolveObject(effectPath,L"/Script/GameplayAbilities.GameplayEffect");
    void *player=resolveObject(playerPath,L"/Script/Engine.Actor");void *lib=protectionLibrary();
    Frame spec={0},apply={0};int ok=0;
    if(!asc||!effect||!player||!lib||!frameOpen(&spec,lib,L"MakeSpecHandle"))goto cleanup;
    void *se=field(&spec,L"InGameplayEffect",8,0,NULL),*si=field(&spec,L"InInstigator",8,0,NULL),*sc=field(&spec,L"InEffectCauser",8,0,NULL);
    float *level=field(&spec,L"InLevel",4,0,NULL);void *sp=NULL,*sr=field(&spec,L"ReturnValue",16,1,&sp);
    if(!se||!si||!sc||!level||!sr)goto cleanup;
    memcpy(se,&effect,8);memcpy(si,&player,8);memcpy(sc,&player,8);*level=1.0f;processEvent(lib,spec.fn,spec.data);
    if(!frameOpen(&apply,asc,L"BP_ApplyGameplayEffectSpecToSelf"))goto cleanup;
    void *ap=NULL,*in=field(&apply,L"SpecHandle",16,1,&ap),*out=field(&apply,L"ReturnValue",8,1,NULL);
    if(!in||!out)goto cleanup;copyValue(ap,in,sr);processEvent(asc,apply.fn,apply.data);
    int32_t handle=0;memcpy(&handle,out,4);if(handle<=0){fail("Protection effect application returned an invalid handle");goto cleanup;}
    memcpy(activeHandle,out,8);wcsncpy(activeEffect,effectPath,2047);activeEffect[2047]=0;wcsncpy(activeAsc,ascPath,2047);activeAsc[2047]=0;hasActive=1;
    captureWeak(&activeAscRef,asc);
    fprintf(reply,"handle\t%d\n",handle);ok=1;
cleanup:frameClose(&apply);frameClose(&spec);return ok;
}
static int removeProtection(FILE *reply,const wchar_t *ascPath,int32_t handle,const wchar_t *effectPath){
    int32_t stored=0;memcpy(&stored,activeHandle,4);
    if(!hasActive||handle!=stored||wcscmp(activeAsc,ascPath)||wcscmp(activeEffect,effectPath)||wcscmp(preparedEffect,effectPath))return fail("Removal does not match the active protection effect");
    void *ascClass=findObject(NULL,NULL,L"/Script/GameplayAbilities.AbilitySystemComponent",0);
    void *asc=activeAscRef.serial?weakGet(&activeAscRef):findObject(NULL,NULL,ascPath,0);Frame remove={0};int ok=0;
    /* World teardown can destroy the effect before its owner. Removing the
     * exact saved handle needs only the ASC, not the old effect UObject. */
    if(!ascClass)goto cleanup;
    if(!asc||!isA(asc,ascClass)){
        memset(activeHandle,0,sizeof(activeHandle));activeEffect[0]=0;activeAsc[0]=0;hasActive=0;
        fprintf(reply,"removed\t0\nexpired\t1\n");return 1;
    }
    if(!frameOpen(&remove,asc,L"RemoveActiveGameplayEffect"))goto cleanup;
    void *h=field(&remove,L"Handle",8,1,NULL);int32_t *stacks=field(&remove,L"StacksToRemove",4,0,NULL);unsigned char *result=field(&remove,L"ReturnValue",1,0,NULL);
    if(!h||!stacks||!result)goto cleanup;memcpy(h,activeHandle,8);*stacks=-1;processEvent(asc,remove.fn,remove.data);
    /* GAS may already have removed this handle during save/world teardown.
     * An absent handle is a completed cleanup, not a reason to retry forever. */
    fprintf(reply,"removed\t%d\nexpired\t%d\n",*result?1:0,*result?0:1);
    memset(activeHandle,0,sizeof(activeHandle));activeEffect[0]=0;activeAsc[0]=0;hasActive=0;ok=1;
cleanup:frameClose(&remove);return ok;
}
static int releaseProtection(FILE *reply,const wchar_t *effectPath){
    if(hasActive)return fail("Remove the active protection effect before release");
    if(!*preparedEffect||wcscmp(preparedEffect,effectPath))return fail("Effect is not the prepared protection effect");
    void *effectClass=findObject(NULL,NULL,L"/Script/GameplayAbilities.GameplayEffect",0);
    if(!effectClass)return fail("GameplayEffect class unavailable during release");
    void *effect=preparedRef.serial?weakGet(&preparedRef):findObject(NULL,NULL,effectPath,0);
    /* A saved path is allowed to expire when loading a save. There is no root
     * left to release when its object has already gone away. */
    if(effect&&!isA(effect,effectClass))return fail("Protection effect class mismatch");
    if(effect&&preparedAddedRoot&&isRooted(effect))unrootObject(effect);
    preparedEffect[0]=0;preparedAddedRoot=0;preparedRef=(WeakObject){0,0};activeAscRef=(WeakObject){0,0};fprintf(reply,"released\t1\n");return 1;
}
