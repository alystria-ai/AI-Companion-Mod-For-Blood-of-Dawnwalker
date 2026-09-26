/* Query the game's spatial index, including pickups without physics collision.
 * UObject and FGameplayTagContainer parameters stay in engine-sized buffers. */
static WeakObject lootPlayerRef,lootLibraryRef;
static wchar_t lootPlayerPath[2048];
static int queryNearbyLoot(FILE *reply,const wchar_t *path){
 void *player=!wcscmp(path,lootPlayerPath)?weakGet(&lootPlayerRef):NULL;
 if(!player){player=resolveObject(path,L"/Script/Dawnwalker.DawnwalkerPlayerCharacter");if(!player)return 0;captureWeak(&lootPlayerRef,player);wcsncpy(lootPlayerPath,path,2047);}
 void *lib=weakGet(&lootLibraryRef);
 if(!lib){lib=resolveObject(L"/Script/RebelSpatialSystem.Default__RebelSpatialSystemBlueprintFunctionLibrary",L"/Script/RebelSpatialSystem.RebelSpatialSystemBlueprintFunctionLibrary");if(!lib)return 0;captureWeak(&lootLibraryRef,lib);}
 typedef const wchar_t *(*ImportFn)(const void*,const wchar_t*,void*,void*,int,void*);
 ImportFn importText=(ImportFn)GetProcAddress(GetModuleHandleW(L"UE4SS.dll"),"?ImportText_Direct@FProperty@Unreal@RC@@QEBAPEB_WPEB_WPEAXPEAVUObject@23@HPEAVFOutputDevice@23@@Z");
 Frame location={0},query={0},actors={0};int ok=0;
 if(!importText||!frameOpen(&location,player,L"K2_GetActorLocation"))goto done;
 void *position=field(&location,L"ReturnValue",24,1,NULL);if(!position)goto done;processEvent(player,location.fn,location.data);
 /* GetElementsFromLayersInDistance discards its result and returns nullptr in
  * game 1.05. RunQuery retains the same spatial result instead. */
 if(!frameOpen(&query,lib,L"RunQuery"))goto done;
 void *qp=NULL,*request=field(&query,L"Query",88,1,&qp),*result=field(&query,L"ReturnValue",8,0,NULL);
 if(!request||!result)goto done;
 double xyz[3];memcpy(xyz,position,24);wchar_t text[512];
 swprintf(text,512,L"(InLayers=(GameplayTags=((TagName=\"RebelSpatialSystem.Layers.FocusDetectors\"))),Center=(X=%.9f,Y=%.9f,Z=%.9f),Distance=350.0,bIsAsync=False)",xyz[0],xyz[1],xyz[2]);
 if(!importText(qp,text,request,lib,0,NULL)){fail("Could not construct nearby loot query");goto done;}
 processEvent(lib,query.fn,query.data);void *container=NULL;memcpy(&container,result,8);if(!container){fail("Nearby loot query returned no result container");goto done;}
 if(!frameOpen(&actors,container,L"GetResultsAsActors"))goto done;
 void *ap=NULL,*output=field(&actors,L"Actors",16,1,&ap);if(!output)goto done;
 processEvent(container,actors.fn,actors.data);ok=textValue(reply,"lootActors",ap,output,container);
done:frameClose(&actors);frameClose(&query);frameClose(&location);return ok;
}
