/* Same reflected, engine-owned value buffers as the established class loader.
 * UObject assets use the OBJECT path/ref APIs, never a guessed class cast. */
static int makeObjectReference(Frame *conversion,void *lib,const wchar_t *path,void **value){
    Frame parsed={0};int ok=0;
    if(wcsncmp(path,L"/Game/_Dawnwalker/",18)||wcslen(path)>1800)return fail("Invalid Dawnwalker asset path");
    if(!frameOpen(&parsed,lib,L"MakeSoftObjectPath"))return 0;
    FString *input=field(&parsed,L"PathString",16,0,NULL);
    void *result=field(&parsed,L"ReturnValue",32,1,NULL);
    if(!input||!result)goto cleanup;
    input->data=(wchar_t*)path;input->count=(int)wcslen(path)+1;input->capacity=input->count;
    processEvent(lib,parsed.fn,parsed.data);
    if(!frameOpen(conversion,lib,L"Conv_SoftObjPathToSoftObjRef"))goto cleanup;
    void *p=NULL,*dest=field(conversion,L"SoftObjectPath",32,1,&p);
    *value=field(conversion,L"ReturnValue",40,1,NULL);
    if(!dest||!*value)goto cleanup;
    copyValue(p,dest,result);processEvent(lib,conversion->fn,conversion->data);ok=1;
cleanup: frameClose(&parsed);return ok;
}
static int loadObjectAsync(FILE *reply,const wchar_t *contextPath,const wchar_t *path){
    void *context=resolveObject(contextPath,L"/Script/Engine.Pawn");
    void *lib=resolveObject(L"/Script/Engine.Default__KismetSystemLibrary",L"/Script/Engine.KismetSystemLibrary");
    void *latentType=findObject(NULL,NULL,L"/Script/Engine.LatentActionInfo",0);
    if(!context||!lib||!latentType)return fail("Async asset context unavailable");
    Frame reference={0},load={0};void *soft=NULL;int ok=0;
    if(!makeObjectReference(&reference,lib,path,&soft)||!frameOpen(&load,lib,L"LoadAsset"))goto cleanup;
    void *sp=NULL,*input=field(&load,L"Asset",40,1,&sp);
    void *world=field(&load,L"WorldContextObject",8,0,NULL);
    void *delegate=field(&load,L"OnLoaded",16,1,NULL);
    void *latent=field(&load,L"LatentInfo",24,1,NULL);
    if(!input||!world||!delegate||!latent)goto cleanup;
    void *link=findProperty(latentType,L"Linkage"),*uuid=findProperty(latentType,L"UUID"),*callback=findProperty(latentType,L"CallbackTarget"),*execution=findProperty(latentType,L"ExecutionFunction");
    if(!link||!uuid||!callback||!execution||propertySize(link)!=4||*propertyOffset(link)!=0||propertySize(uuid)!=4||*propertyOffset(uuid)!=4||propertySize(callback)!=8||*propertyOffset(callback)!=16||propertySize(execution)!=8||*propertyOffset(execution)!=8){fail("Unexpected latent asset action layout");goto cleanup;}
    static unsigned sequence=0;int identifier=(int)(0x44000000u+(++sequence)),none=-1;
    memcpy(latent,&none,4);memcpy((unsigned char*)latent+4,&identifier,4);memcpy((unsigned char*)latent+16,&context,8);
    copyValue(sp,input,soft);memcpy(world,&context,8);
    ULONGLONG started=GetTickCount64();processEvent(lib,load.fn,load.data);
    fprintf(reply,"requestMs\t%llu\n",(unsigned long long)(GetTickCount64()-started));ok=1;
cleanup: frameClose(&load);frameClose(&reference);return ok;
}
