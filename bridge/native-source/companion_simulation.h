/* UE 5.6 / Dawnwalker 1.05: this API is native-only, not a UFunction.
 * Validate both the reflected layout and implementation bytes before using
 * its vtable. Never call a guessed function on an unknown game build. */
static int simulationReadable(const void *p,size_t length){
    MEMORY_BASIC_INFORMATION r;
    return p&&VirtualQuery(p,&r,sizeof(r))&&r.State==MEM_COMMIT
        &&!(r.Protect&(PAGE_NOACCESS|PAGE_GUARD))
        &&(uintptr_t)p+length>=(uintptr_t)p
        &&(uintptr_t)p+length<=(uintptr_t)r.BaseAddress+r.RegionSize;
}
static int simulationBudget(FILE *reply,const wchar_t *path,const wchar_t *action){
    void *mesh=resolveObject(path,L"/Script/AnimationBudgetAllocator.SkeletalMeshComponentBudgeted");if(!mesh)return 0;
    void *property=findProperty(mesh,L"bAutoRegisterWithBudgetAllocator");
    if(!property||*propertyOffset(property)!=0xf90||!simulationReadable(mesh,0xf98))return fail("Unsupported animation mesh layout");
    void **vtable=*(void***)mesh;
    const unsigned char tickPrefix[]={0x4c,0x8b,0x89,0x80,0x0f,0x00,0x00};
    if(!simulationReadable(vtable,0x468)||!simulationReadable(vtable[0x460/8],sizeof(tickPrefix))||memcmp(vtable[0x460/8],tickPrefix,sizeof(tickPrefix)))return fail("Unsupported animation tick implementation");
    void *allocator=NULL;int handle=-1;memcpy(&allocator,(char*)mesh+0xf80,8);memcpy(&handle,(char*)mesh+0xf88,4);
    if(!allocator||handle<0){fprintf(reply,"registered\t0\n");return 1;}
    if(!simulationReadable(allocator,0x88))return fail("Animation allocator unavailable");
    void **av=*(void***)allocator;
    const unsigned char significancePrefix[]={0x48,0x63,0x82,0x88,0x0f,0x00,0x00,0x83,0xf8,0xff};
    if(!simulationReadable(av,0x20)||!simulationReadable(av[3],sizeof(significancePrefix))||memcmp(av[3],significancePrefix,sizeof(significancePrefix)))return fail("Unsupported animation significance implementation");
    unsigned char *entries=NULL;int count=0;memcpy(&entries,(char*)allocator+0x78,8);memcpy(&count,(char*)allocator+0x80,4);
    if(count<0||count>100000||handle>=count||!simulationReadable(entries,(size_t)count*48))return fail("Invalid animation registration");
    unsigned char *entry=entries+(size_t)handle*48;void *owner=NULL;memcpy(&owner,entry,8);
    if(owner!=mesh)return fail("Animation registration belongs to another mesh");
    unsigned before=(entry[0x28]&0x26)|((entry[0x29]&1)<<8),desired=6;
    if(wcscmp(action,L"enable")){
        wchar_t tail;unsigned parsed=0;
        if(swscanf(action,L"%u%lc",&parsed,&tail)!=1||(parsed&~0x126u))return fail("Invalid animation restore flags");
        if(before!=6){fprintf(reply,"registered\t1\nchanged\t0\n");return 1;}
        desired=parsed;
    }
    float significance=0;memcpy(&significance,entry+0x10,4);
    if(!isfinite(significance))return fail("Invalid animation significance");
    typedef void (*SetSignificance)(void*,void*,float,unsigned char,unsigned char,unsigned char,unsigned char);
    ((SetSignificance)av[3])(allocator,mesh,significance,(desired&2)!=0,(desired&4)!=0,(desired&0x20)!=0,(desired&0x100)!=0);
    fprintf(reply,"registered\t1\nprevious\t%u\nflags\t%u\n",before,(entry[0x28]&0x26)|((entry[0x29]&1)<<8));return 1;
}
