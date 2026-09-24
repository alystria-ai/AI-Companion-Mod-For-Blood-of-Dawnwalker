/* Reacquiring idle attention must not repeat full object-name scans and text
 * import. Cache only borrowed engine weak identities, never raw actor pointers. */
static int captureWeak(WeakObject *ref,void *object);
typedef struct { wchar_t path[2048]; WeakObject ref; } GazeObject;
static GazeObject gazeObjects[64];static unsigned gazeCursor;
static Frame gazeFrame;static WeakObject gazeCameraRef,gazeFunctionRef;
static void *gazeObject(const wchar_t *path,const wchar_t *type){
    for(unsigned i=0;i<64;i++)if(!wcscmp(path,gazeObjects[i].path)){
        void *o=weakGet(&gazeObjects[i].ref);if(o)return o;
        gazeObjects[i].path[0]=0;break;
    }
    void *o=resolveObject(path,type);if(!o)return NULL;
    WeakObject ref;if(captureWeak(&ref,o)){
        GazeObject *entry=&gazeObjects[gazeCursor++%64];
        wcsncpy(entry->path,path,2047);entry->path[2047]=0;entry->ref=ref;
    }
    return o;
}
static int inspectGaze(FILE *reply,const wchar_t *path){
    void *actor=resolveObject(path,L"/Script/Dawnwalker.DawnwalkerCommonCharacterBase");
    return actor&&exportField(reply,actor,L"LookAtTargets","targets");
}
/* Import through the engine's reflected struct property: the engine allocates,
 * copies and destroys FInstancedStruct and its weak actor reference. Do not
 * construct weak-object serials or guess an instanced-struct memory layout. */
static int addCameraGaze(FILE *reply,const wchar_t *path,const wchar_t *cameraPath){
    if(wcslen(cameraPath)>1400||wcspbrk(cameraPath,L"\"'\r\n"))return fail("Invalid camera path");
    void *actor=gazeObject(path,L"/Script/Dawnwalker.DawnwalkerCommonCharacterBase");
    void *camera=gazeObject(cameraPath,L"/Script/Engine.CameraActor");
    if(!actor||!camera)return 0;
    if(gazeFrame.data){
        if(weakGet(&gazeCameraRef)==camera&&weakGet(&gazeFunctionRef)==gazeFrame.fn
            &&findFunction(actor,L"AddLookAtTarget")==gazeFrame.fn){
            int32_t *handle=field(&gazeFrame,L"ReturnValue",4,0,NULL);if(!handle)return 0;
            *handle=-1;processEvent(actor,gazeFrame.fn,gazeFrame.data);
            if(*handle<0)return fail("Cached camera look target rejected");
            fprintf(reply,"handle\t%d\nreusedTemplate\t1\n",*handle);return 1;
        }
        frameClose(&gazeFrame);gazeCameraRef=(WeakObject){0,0};gazeFunctionRef=(WeakObject){0,0};
    }
    typedef const wchar_t *(*ImportFn)(const void*,const wchar_t*,void*,void*,int,void*);
    ImportFn importText=(ImportFn)GetProcAddress(GetModuleHandleW(L"UE4SS.dll"),"?ImportText_Direct@FProperty@Unreal@RC@@QEBAPEB_WPEB_WPEAXPEAVUObject@23@HPEAVFOutputDevice@23@@Z");
    if(!importText)return fail("Reflected look-target import unavailable");
    Frame frame;if(!frameOpen(&frame,actor,L"AddLookAtTarget"))return 0;
    void *property=NULL,*data=field(&frame,L"LookAtTargetData",16,1,&property);
    int32_t *handle=field(&frame,L"ReturnValue",4,0,NULL);int ok=0;
    if(data&&handle){
        wchar_t text[2048];
        int n=swprintf(text,2048,L"/Script/Dawnwalker.DawnwalkerActorLookAtTarget(Actor=\"/Script/Engine.CameraActor'%ls'\",Priority=50,ExpiryTime=0.000000,Tracking=/Script/Dawnwalker.DawnwalkerLookAtTargetPermanentTracking(),Turning=/Script/Dawnwalker.DawnwalkerLookAtInstantTurning())",cameraPath);
        if(n>0&&n<2048){
            const wchar_t *end=importText(property,text,data,actor,0,NULL);
            if(end&&!*end){
                processEvent(actor,frame.fn,frame.data);
                if(*handle>=0){fprintf(reply,"handle\t%d\n",*handle);ok=1;}
                else fail("Camera look target rejected");
            }else fail("Camera look target could not be constructed");
        }else fail("Camera look target text too long");
    }
    if(ok&&captureWeak(&gazeCameraRef,camera)&&captureWeak(&gazeFunctionRef,frame.fn)){
        gazeFrame=frame;memset(&frame,0,sizeof(frame));
    }
    frameClose(&frame);return ok;
}
