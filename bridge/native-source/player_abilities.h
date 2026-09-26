/* The native cross-form allowance effects are applied only to the local player.
 * Retain exactly our two GAS handles; removal never strips campaign effects. */
static WeakObject abilityAscRef;
static unsigned char abilityHandles[2][8];
static int abilityOwned[2];
static int removeAbilityAllowance(FILE *reply){
 void *asc=abilityAscRef.serial?weakGet(&abilityAscRef):NULL;
 for(int i=0;i<2;i++)if(abilityOwned[i]){
  if(asc){
   Frame f={0};if(!frameOpen(&f,asc,L"RemoveActiveGameplayEffect"))return 0;
   void *h=field(&f,L"Handle",8,1,NULL);int32_t *stacks=field(&f,L"StacksToRemove",4,0,NULL);
   if(!h||!stacks){frameClose(&f);return 0;}
   memcpy(h,abilityHandles[i],8);*stacks=-1;processEvent(asc,f.fn,f.data);frameClose(&f);
  }
  abilityOwned[i]=0;memset(abilityHandles[i],0,8);
 }
 abilityAscRef=(WeakObject){0,0};fprintf(reply,"abilityRemoved\t1\n");return 1;
}
static int applyAbilityAllowance(FILE *reply,const wchar_t *playerPath){
 void *player=resolveObject(playerPath,L"/Script/Dawnwalker.DawnwalkerPlayerCharacter");
 void *lib=protectionLibrary(),*asc=NULL;Frame get={0};int ok=0;
 if(!player||!lib)return fail("Local player unavailable for ability allowance");
 if(!frameOpen(&get,player,L"IsPlayerControlled"))goto done;
 unsigned char *controlled=field(&get,L"ReturnValue",1,0,NULL);if(!controlled)goto done;
 processEvent(player,get.fn,get.data);if(!*controlled){fail("Ability allowance requires a player-controlled pawn");goto done;}frameClose(&get);
 if(!frameOpen(&get,lib,L"GetAbilitySystemComponent"))goto done;
 void *actor=field(&get,L"Actor",8,0,NULL),*out=field(&get,L"ReturnValue",8,0,NULL);
 if(!actor||!out)goto done;memcpy(actor,&player,8);processEvent(lib,get.fn,get.data);memcpy(&asc,out,8);
 if(!asc){fail("Player ability system unavailable");goto done;}
 if(abilityAscRef.serial&&weakGet(&abilityAscRef)==asc&&abilityOwned[0]&&abilityOwned[1]){ok=1;fprintf(reply,"abilityActive\t1\n");goto done;}
 if(!removeAbilityAllowance(reply))goto done;
 if(!captureWeak(&abilityAscRef,asc)||!abilityAscRef.serial){fail("Player ability system has no engine weak identity yet");goto done;}
 const wchar_t *paths[]={L"/Game/_Dawnwalker/Combat/Focus/Spells/GE_AllowHumanAbilities.Default__GE_AllowHumanAbilities_C",L"/Game/_Dawnwalker/Combat/Focus/Spells/GE_AllowVampireAbilities.Default__GE_AllowVampireAbilities_C"};
 for(int i=0;i<2;i++){
  Frame spec={0},apply={0};int applied=0;
  void *effect=resolveObject(paths[i],L"/Script/GameplayAbilities.GameplayEffect");
  if(effect&&frameOpen(&spec,lib,L"MakeSpecHandle")){
   void *e=field(&spec,L"InGameplayEffect",8,0,NULL),*inst=field(&spec,L"InInstigator",8,0,NULL),*cause=field(&spec,L"InEffectCauser",8,0,NULL),*sp=NULL,*result=field(&spec,L"ReturnValue",16,1,&sp);
   float *level=field(&spec,L"InLevel",4,0,NULL);
   if(e&&inst&&cause&&result&&level){
    memcpy(e,&effect,8);memcpy(inst,&player,8);memcpy(cause,&player,8);*level=1;processEvent(lib,spec.fn,spec.data);
    if(frameOpen(&apply,asc,L"BP_ApplyGameplayEffectSpecToSelf")){
     void *ap=NULL,*input=field(&apply,L"SpecHandle",16,1,&ap),*handle=field(&apply,L"ReturnValue",8,1,NULL);
     if(input&&handle){copyValue(ap,input,result);processEvent(asc,apply.fn,apply.data);int32_t value=0;memcpy(&value,handle,4);
      if(value>0){memcpy(abilityHandles[i],handle,8);abilityOwned[i]=1;applied=1;}
     }
    }
   }
  }
  frameClose(&apply);frameClose(&spec);
  if(!applied){removeAbilityAllowance(reply);fail("Could not apply both native ability allowance effects");goto done;}
 }
 fprintf(reply,"abilityActive\t1\n");ok=1;
done:frameClose(&get);return ok;
}
