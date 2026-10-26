/* Build-specific, game-thread appearance transactions. No disk-save editing.
 * Use only with the accompanying Lua controller. BEGIN before opening the
 * game's editor; END only after its closing callbacks have finished.
 * The player appearance writer is blocked for the full transaction, including
 * Cancel/Apply teardown. All UObject pointers remain owned by the game.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
#include "appearance_guards.h"

typedef struct { wchar_t *data; int32_t count, capacity; } Str;
typedef union { uint64_t align; unsigned char b[0xf8]; } Custom;
_Static_assert(sizeof(Custom)==0xf8,"FCatCustomData ABI");
_Static_assert(sizeof(Str)==16,"FString ABI");
static HMODULE self;
static unsigned char *base;
static DWORD owner_thread;
static int active, applied, bound, have_pending, cancelled, have_editor_baseline;
static unsigned char role, expected_clan;
static void *manager, *save_game, *actor;
static int32_t slot, profile_index, actor_index;
static void *flow_manager;
static wchar_t gamer_id[1024];
static wchar_t profile_id[1024];
static Custom original, pending, preview_original, editor_baseline;
static int cosmetic_force_all;
static int writer_installed;
static unsigned suppressed;
static void *(*read_npc)(void*,Custom*,uint8_t,int32_t);
static void (*write_npc)(uint8_t,const Custom*);
static void *(*copy_custom)(Custom*,const Custom*);
static void *(*assign_custom)(Custom*,const Custom*);
static void (*destroy_custom)(Custom*);
static void (*free_engine)(void*);
static void (*apply_preview)(void*,const Custom*,uint8_t);
static void *(*assign_string)(Str*,const wchar_t*,int32_t);
static unsigned char patch[15];
static unsigned char editor_save_patch[14];
static unsigned char tutorial_patch[1]={0xc3};
static int editor_save_guard,tutorial_guard,native_intent;
static void *screen;
static int32_t screen_index;
static void **screen_original_vtable,**screen_clone;
static void *camera_helper,*camera_old_actor,*camera_screen;
static int32_t camera_index,camera_actor_index;
typedef struct { void *data; int32_t count,capacity; } EngineArray;
typedef struct { unsigned char bytes[0x70]; } CameraTarget;
static unsigned char camera_runtime_state[0x38]; /* queue, timers, target, 3 weakrefs */
static EngineArray camera_original_targets;
static CameraTarget *camera_owned_targets;
static unsigned camera_target_mask;
static unsigned char camera_filter;

static int readable(const void *p,size_t n,const void *allocation,int executable) {
    uintptr_t x=(uintptr_t)p,end=x+n;
    if(!x || end<x) return 0;
    while(x<end) {
        MEMORY_BASIC_INFORMATION m;
        if(!VirtualQuery((void*)x,&m,sizeof(m)) || m.State!=MEM_COMMIT ||
           (allocation && m.AllocationBase!=allocation) || (m.Protect&(PAGE_GUARD|PAGE_NOACCESS))) return 0;
        DWORD q=m.Protect&255;
        if(q!=PAGE_READONLY&&q!=PAGE_READWRITE&&q!=PAGE_WRITECOPY&&q!=PAGE_EXECUTE_READ&&q!=PAGE_EXECUTE_READWRITE&&q!=PAGE_EXECUTE_WRITECOPY) return 0;
        if(executable&&q!=PAGE_EXECUTE_READ&&q!=PAGE_EXECUTE_READWRITE&&q!=PAGE_EXECUTE_WRITECOPY) return 0;
        uintptr_t next=(uintptr_t)m.BaseAddress+m.RegionSize;
        if(next<=x) return 0;
        x=next;
    }
    return 1;
}
static int string_ok(const Str *s) {
    return s->count>=0 && s->count<=1024 && s->capacity>=s->count &&
      ((!s->count) || (readable(s->data,(size_t)s->count*2,NULL,0)&&s->data[s->count-1]==0));
}
static int custom_ok(const Custom *c) {
    static const unsigned offsets[]={0x70,0x80,0x98,0xa8,0xb8,0xc8};
    if(!readable(c,sizeof(*c),NULL,0)) return 0;
    for(unsigned i=0;i<6;i++) if(!string_ok((const Str*)(c->b+offsets[i]))) return 0;
    float size; memcpy(&size,c->b+0x94,4);
    return isfinite(size)&&size>=0&&size<=100;
}
static int str_equal(const Str *a,const Str *b) {
    int na=a->count?a->count-1:0,nb=b->count?b->count-1:0;
    return na==nb && (!na || !memcmp(a->data,b->data,(size_t)na*2));
}
static int custom_equal(const Custom *a,const Custom *b) {
    static const unsigned offsets[]={0x70,0x80,0x98,0xa8,0xb8,0xc8};
    /* Compare meaningful scalar fields; ignore FString pointers and padding. */
    if(memcmp(a->b,b->b,2)||memcmp(a->b+4,b->b+4,0x60)||a->b[0x64]!=b->b[0x64]||
       memcmp(a->b+0x68,b->b+0x68,4)||a->b[0x90]!=b->b[0x90]||
       memcmp(a->b+0x94,b->b+0x94,4)||memcmp(a->b+0xd8,b->b+0xd8,0x20)) return 0;
    for(unsigned i=0;i<6;i++) if(!str_equal((const Str*)(a->b+offsets[i]),(const Str*)(b->b+offsets[i]))) return 0;
    return 1;
}
static int object_ok(void *p,size_t n) {
    if(!readable(p,n,NULL,0)||(*(uint32_t*)((char*)p+8)&0x60018000u))return 0;
    /* Our single guarded editor intentionally has a private vtable. Accept
       only that exact live transaction/index/clone, never an arbitrary heap
       vtable. Teardown must still unbind input before restoring this clone. */
    if(active&&p==screen&&screen_clone&&*(void***)p==screen_clone&&
       *(int32_t*)((char*)p+0xc)==screen_index)
        return readable(screen_clone,0x6d0,screen_clone-1,0);
    return readable(*(void**)p,sizeof(void*),base,0);
}
static FILE *local_file(const wchar_t *name,const wchar_t *mode) {
    wchar_t path[32768]; DWORD n=GetModuleFileNameW(self,path,32768);
    if(!n||n>=32768) return NULL;
    wchar_t *s=wcsrchr(path,L'\\'); if(!s) return NULL; s[1]=0;
    if(wcslen(path)+wcslen(name)>=32768) return NULL;
    wcscat(path,name);return _wfopen(path,mode);
}
static void report(unsigned id,const char *result) {
    FILE *f=local_file(L"appearance-response.txt",L"w");
    if(f){fprintf(f,"%u %s\nactive=%d applied=%d bound=%d pending=%d suppressed=%u role=%u slot=%d intent=%d screen=%p\n",id,result,active,applied,bound,have_pending,suppressed,role,slot,native_intent,screen);fclose(f);}
}
static int initialize(void) {
    if(base) return 1;
    unsigned char *b=(unsigned char*)GetModuleHandleW(NULL);
    if(!readable(b,sizeof(IMAGE_DOS_HEADER),b,0)) return 0;
    IMAGE_DOS_HEADER *d=(IMAGE_DOS_HEADER*)b;
    if(d->e_magic!=IMAGE_DOS_SIGNATURE||d->e_lfanew<64||d->e_lfanew>0x100000) return 0;
    IMAGE_NT_HEADERS64 *n=(IMAGE_NT_HEADERS64*)(b+d->e_lfanew);
    if(!readable(n,sizeof(*n),b,0)||n->Signature!=IMAGE_NT_SIGNATURE||
       n->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||n->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||
       n->FileHeader.SizeOfOptionalHeader<sizeof(IMAGE_OPTIONAL_HEADER64)||
       n->OptionalHeader.SizeOfImage!=187576320u||n->FileHeader.TimeDateStamp!=141614920u) return 0;
    for(unsigned i=0;i<sizeof(appearance_guards)/sizeof(appearance_guards[0]);i++) {
        const AppearanceGuard *g=&appearance_guards[i];
        if(g->rva>n->OptionalHeader.SizeOfImage-16||!readable(b+g->rva,16,b,1)||memcmp(b+g->rva,g->bytes,16)) return 0;
    }
    if(!readable(b+0xa8a6e30,8,b,0)||!readable(b+0xa8a6e08,8,b,0)) return 0;
    base=b;
    read_npc=(void*(*)(void*,Custom*,uint8_t,int32_t))(b+0x194a600);
    write_npc=(void(*)(uint8_t,const Custom*))(b+0x1949ee0);
    copy_custom=(void*(*)(Custom*,const Custom*))(b+0x1708c40);
    assign_custom=(void*(*)(Custom*,const Custom*))(b+0x1708a90);
    destroy_custom=(void(*)(Custom*))(b+0x17088f0);
    free_engine=(void(*)(void*))(b+0x19db970);
    apply_preview=(void(*)(void*,const Custom*,uint8_t))(b+0x17b0d20);
    assign_string=(void*(*)(Str*,const wchar_t*,int32_t))(b+0x1981e50);
    return 1;
}
static int class_is(void *object,uint32_t class_rva);
static int current_character_slot(void **flow,int32_t *selected) {
    void *f=*(void**)(base+0xa8a6e08);
    if(!object_ok(f,0x158)||!class_is(f,0x1613480))return 0;
    int32_t value=*(int32_t*)((char*)f+0x154);
    if(value<0)return 0;
    *flow=f;*selected=value;return 1;
}
static int same_context(void) {
    void *flow;int32_t selected;
    if(!active||GetCurrentThreadId()!=owner_thread||!object_ok(manager,0x170)||
       *(void**)(base+0xa8a6e30)!=manager||*(void**)((char*)manager+0x168)!=save_game||
       !object_ok(save_game,0xa0)||*(int32_t*)((char*)save_game+0x78)!=profile_index||
       !current_character_slot(&flow,&selected)||flow!=flow_manager||selected!=slot) return 0;
    Str *g=(Str*)((char*)save_game+0x30);
    Str *slots=*(Str**)((char*)save_game+0x68);
    int count=*(int*)((char*)save_game+0x70);
    if(profile_index<0||profile_index>=count||count>128||!readable(slots,(size_t)count*sizeof(Str),NULL,0)) return 0;
    Str *profile=&slots[profile_index];
    return string_ok(g)&&g->count>1&&!wcscmp(gamer_id,g->data)&&
      string_ok(profile)&&profile->count>1&&!wcscmp(profile_id,profile->data);
}
static void capture(const Custom *data) {
    if(!cancelled && !applied && same_context() && custom_ok(data)) {
        assign_custom(&pending,data);have_pending=1;
    }
}
static void player_save_blocked(const Custom *data,Str *owned_key,int32_t requested_slot) {
    (void)requested_slot;
    ++suppressed;
    capture(data);
    /* SaveCatCustomData takes the key by value and frees it, including failures. */
    if(owned_key&&readable(owned_key,sizeof(*owned_key),NULL,0)&&string_ok(owned_key)) {
        if(owned_key->data) free_engine(owned_key->data);
        owned_key->data=NULL;owned_key->count=owned_key->capacity=0;
    }
}
static int patch_writer(int install) {
    unsigned char *target=base+0x1812f50;
    const unsigned char *original_bytes=appearance_guards[0].bytes;
    if(memcmp(target,install?original_bytes:patch,15)) return 0;
    if(install) {
        memset(patch,0x90,sizeof(patch));patch[0]=0xff;patch[1]=0x25;
        memset(patch+2,0,4);void *fn=(void*)player_save_blocked;memcpy(patch+6,&fn,8);
    }
    DWORD old,unused;
    if(!VirtualProtect(target,15,PAGE_EXECUTE_READWRITE,&old)) return 0;
    memcpy(target,install?patch:original_bytes,15);
    FlushInstructionCache(GetCurrentProcess(),target,15);
    /* Restore page flags even if a system error is reported. The instruction
       bytes determine whether the hook is installed; never lose that state. */
    VirtualProtect(target,15,old,&unused);
    writer_installed=install;
    return 1;
}
static int replace_code(unsigned guard_index,unsigned char *replacement,size_t length,int install) {
    const AppearanceGuard *g=&appearance_guards[guard_index];unsigned char *target=base+g->rva;
    const unsigned char *desired=install?replacement:g->bytes,*current=install?g->bytes:replacement;
    if(!memcmp(target,desired,length)) return 1;
    if(memcmp(target,current,length)) return 0;
    DWORD old,unused;if(!VirtualProtect(target,length,PAGE_EXECUTE_READWRITE,&old)) return 0;
    memcpy(target,desired,length);FlushInstructionCache(GetCurrentProcess(),target,length);
    VirtualProtect(target,length,old,&unused);return 1;
}
static void editor_save_blocked(void *widget) {
    if(active&&same_context()&&!cancelled&&!applied&&readable(widget,0x6a0,NULL,0)&&
       (widget==screen||object_ok(widget,0x6a0))) {
        void *cat=*(void**)((char*)widget+0x488);
        if(bound&&cat==actor&&object_ok(cat,0x3c8)) {
            void *mesh=*(void**)((char*)cat+0x2b8);
            if(object_ok(mesh,0x210)) capture((Custom*)((char*)mesh+0x118));
        }
        native_intent=*((unsigned char*)widget+0x3ba)?2:1;
    }
    /* Root overlays Apply/Cancel and owns closure. Never execute native
       creation-flow transition, tutorial writes or global graphics changes. */
}
static void editor_transition_blocked(void *widget,const uint8_t *next) {
    if(active&&widget==screen&&!cancelled&&!applied)
        native_intent=readable(next,1,NULL,0)&&*next==26?1:2;
}
static int class_is(void *object,uint32_t class_rva) {
    if(!object_ok(object,0x28)) return 0;
    void *klass=((void*(*)(void))(base+class_rva))();
    void *actual=*(void**)((char*)object+0x10);
    if(!object_ok(klass,0x40)||!object_ok(actual,0x40)) return 0;
    int depth=*(int*)((char*)klass+0x38),actual_depth=*(int*)((char*)actual+0x38);
    void **chain=*(void***)((char*)actual+0x30);
    return depth>=0&&depth<=1024&&actual_depth>=depth&&
      readable(chain,(size_t)(depth+1)*8,NULL,0)&&chain[depth]==(char*)klass+0x30;
}
static int camera_array_ok(const EngineArray *a,size_t element) {
    return a->count>=0&&a->count<=a->capacity&&a->capacity<=4096&&
      ((!a->capacity&&!a->data)||(a->capacity&&readable(a->data,(size_t)a->capacity*element,NULL,0)));
}
static void camera_take_runtime(void *helper) {
    memcpy(camera_runtime_state,(char*)helper+0x310,sizeof(camera_runtime_state));
    /* Move the original queue's ownership out of the helper. Editor changes
       can grow/free only its new queue, never the saved allocation. */
    memset((char*)helper+0x310,0,sizeof(camera_runtime_state));
    *(float*)((char*)helper+0x324)=-1.0f;
}
static void camera_restore_runtime(void *helper) {
    void *queue=*(void**)((char*)helper+0x310);
    if(queue&&queue!=*(void**)camera_runtime_state)free_engine(queue);
    memcpy((char*)helper+0x310,camera_runtime_state,sizeof(camera_runtime_state));
    memset(camera_runtime_state,0,sizeof(camera_runtime_state));
}
static void camera_free_owned_targets(void) {
    if(camera_owned_targets) {
        for(unsigned i=0;i<5;i++)free_engine(((Str*)camera_owned_targets[i].bytes)->data);
        free_engine(camera_owned_targets);camera_owned_targets=NULL;
    }
    camera_target_mask=0;
}
static const char *editor_tree_error(void *candidate) {
    static char error[96];
    /* HoldButtonBack (+580) is assigned FROM the footer by NativeConstruct;
       it is an output, not an authored BindWidget prerequisite. */
    static const unsigned fields[]={0x4d8,0x4e0,0x4e8,0x4f0,0x4f8,0x500,0x508,0x510,0x518,0x520,0x528,0x530,0x538};
    for(unsigned i=0;i<sizeof(fields)/sizeof(fields[0]);i++) {
        if(!object_ok(*(void**)((char*)candidate+fields[i]),0x28)) {
            snprintf(error,sizeof(error),"ERROR Editor blueprint binding missing at +0x%x",fields[i]);return error;
        }
    }
    return NULL;
}
static const char *guard_screen(uintptr_t address) {
    if(!same_context()||screen||cancelled||applied||!bound||!camera_helper||camera_target_mask!=31)
        return "ERROR Cannot bind editor screen";
    void *candidate=(void*)address;
    if(!object_ok(candidate,0x6a0)||!class_is(candidate,0x1853070))return "ERROR Invalid editor screen";
    void *cat=*(void**)((char*)candidate+0x488);
    if(cat&&cat!=actor)return "ERROR Editor does not own the selected preview";
    const char *tree_error=editor_tree_error(candidate);if(tree_error)return tree_error;
    void **v=*(void***)candidate;
    if(!readable(v-1,0x6d8,base,0)||v[0x608/8]!=base+0x1286030||v[0x580/8]!=base+0x191b5a0)
        return "ERROR Unsupported editor vtable";
    void **storage=VirtualAlloc(NULL,0x6d8,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    if(!storage) return "ERROR Cannot allocate editor guard";
    memcpy(storage,v-1,0x6d8);screen_clone=storage+1;
    screen_clone[0x608/8]=(void*)editor_transition_blocked;
    screen_original_vtable=v;screen=candidate;screen_index=*(int32_t*)((char*)candidate+0xc);
    *(void***)candidate=screen_clone;
    /* Record before AddToViewport invokes NativeConstruct so partial mount
       cleanup can always remove this screen's input/camera delegates. */
    camera_screen=candidate;
    return "OK GUARD_SCREEN";
}
static const char *borrow_camera(uintptr_t address) {
    if(!same_context()||camera_helper||cancelled||applied) return "ERROR No new camera transaction";
    void *helper=(void*)address;
    if(!object_ok(helper,0x348)||!class_is(helper,0x185dd70)||
       *(void**)((char*)*(void**)helper+0x760)!=(void*)(base+0x1258450)) return "ERROR Invalid camera helper";
    void *mesh=((void*(*)(void*))(base+0x1d133d0))((char*)helper+0x340);
    void *owner=NULL;
    if(mesh) {
        if(!object_ok(mesh,0xb0))return "ERROR Invalid previous camera mesh";
        owner=*(void**)((char*)mesh+0xa8);
        if(!object_ok(owner,0x2b0)||owner==actor)return "ERROR Invalid previous camera actor";
    }
    EngineArray *targets=(EngineArray*)((char*)helper+0x2d8),*queue=(EngineArray*)((char*)helper+0x310);
    if(!camera_array_ok(targets,sizeof(CameraTarget))||!camera_array_ok(queue,8))return "ERROR Invalid camera arrays";
    /* Reserve a game-owned array, using the verified TArray reserve helper. */
    EngineArray owned={0};
    ((void(*)(uint32_t,uint32_t,int32_t,int32_t,void**,int32_t,int32_t*))(base+0x119e960))
       (sizeof(CameraTarget),8,5,0,&owned.data,5,&owned.capacity);
    if(!owned.data||owned.capacity<5)return "ERROR Cannot allocate private camera targets";
    memset(owned.data,0,(size_t)owned.capacity*sizeof(CameraTarget));
    camera_owned_targets=owned.data;camera_target_mask=0;
    camera_original_targets=*targets;owned.count=5;*targets=owned;
    camera_filter=*((unsigned char*)helper+0x2b0);*((unsigned char*)helper+0x2b0)=0;
    camera_helper=helper;camera_old_actor=owner;
    camera_index=*(int32_t*)((char*)helper+0xc);camera_actor_index=owner?*(int32_t*)((char*)owner+0xc):0;
    camera_take_runtime(helper);
    return "OK CAMERA_BORROWED";
}
static const char *camera_target(unsigned index,uintptr_t address) {
    static const wchar_t *names[]={L"SelectBody",L"SelectEye",L"SelectEyeTinny",L"SelectEyeMedium",L"SelectMouth"};
    if(!same_context()||!camera_helper||screen||camera_screen||!camera_owned_targets||index<1||index>5)
        return "ERROR No private camera setup";
    void *candidate=(void*)address;
    if(!object_ok(candidate,0xb00)||!class_is(candidate,0x122a660))return "ERROR Invalid customization camera";
    unsigned char *p=camera_owned_targets[index-1].bytes;
    assign_string((Str*)p,names[index-1],(int32_t)wcslen(names[index-1]));
    *(int32_t*)(p+0x10)=1;*(void**)(p+0x18)=candidate;p[0x20]=1;
    camera_target_mask|=1u<<(index-1);return "OK CAMERA_TARGET_READY";
}
static const char *detach_screen(void) {
    if(!active||GetCurrentThreadId()!=owner_thread) return "ERROR No owned transaction";
    if(!camera_helper) return "OK CAMERA_NOT_BORROWED";
    if(camera_screen&&object_ok(camera_screen,0x6a0)&&class_is(camera_screen,0x1853070))
        ((void(*)(void*))(base+0x1285ed0))(camera_screen);
    if(object_ok(camera_helper,0x348)&&*(int32_t*)((char*)camera_helper+0xc)==camera_index) {
        if(camera_screen) ((void(*)(void*,void*))(base+0x125d4d0))((char*)camera_helper+0x2f0,camera_screen);
        if(camera_old_actor&&(!object_ok(camera_old_actor,0x2b0)||*(int32_t*)((char*)camera_old_actor+0xc)!=camera_actor_index))
            return "ERROR Previous camera actor disappeared; keep preview alive";
        EngineArray *current=(EngineArray*)((char*)camera_helper+0x2d8);
        if(current->data!=camera_owned_targets||!camera_array_ok((EngineArray*)((char*)camera_helper+0x310),8))
            return "ERROR Private camera ownership changed";
        *current=camera_original_targets;memset(&camera_original_targets,0,sizeof(camera_original_targets));
        *((unsigned char*)camera_helper+0x2b0)=camera_filter;
        camera_restore_runtime(camera_helper);
        /* The owned cameras are destroyed after END. An initially unbound
           helper must remain unbound: calling SetTrackedActor(NULL) crashes
           when its active camera exists. Restoring the exact weakref bytes is
           sufficient because only our private cameras were changed. */
    } else {
        /* The helper destructor already released its current arrays; retained
           old allocations are ours to release. Never double-free its targets. */
        camera_owned_targets=NULL;
        for(int i=0;i<camera_original_targets.count;i++) {
            unsigned char *p=(unsigned char*)camera_original_targets.data+(size_t)i*0x70;
            free_engine(((Str*)p)->data);free_engine(*(void**)(p+0x50));
        }
        free_engine(camera_original_targets.data);free_engine(*(void**)camera_runtime_state);
        memset(&camera_original_targets,0,sizeof(camera_original_targets));memset(camera_runtime_state,0,sizeof(camera_runtime_state));
    }
    camera_free_owned_targets();
    camera_helper=camera_old_actor=camera_screen=NULL;
    return "OK CAMERA_RESTORED";
}
static int record_editor_baseline(void) {
    if(have_editor_baseline)return 1; /* Repeated INIT must not erase user edits. */
    void *component=*(void**)((char*)actor+0x2b8);
    if(!object_ok(component,0x210)||!custom_ok((Custom*)((char*)component+0x118)))return 0;
    copy_custom(&editor_baseline,(Custom*)((char*)component+0x118));
    have_editor_baseline=1;have_pending=0;return 1;
}
static const char *initialize_screen(uintptr_t address) {
    if(!same_context()||!bound||!camera_helper||cancelled||applied||camera_target_mask!=31) return "ERROR No active editor preview and five private cameras";
    void *candidate=(void*)address;
    if(!object_ok(candidate,0x6a0)||!class_is(candidate,0x1853070)) return "ERROR Invalid game editor widget";
    void *cat=*(void**)((char*)candidate+0x488);
    if(cat) {
        if(cat==actor&&*(void**)((char*)candidate+0x578)==camera_helper&&
           object_ok(*(void**)((char*)candidate+0x568),0x28)) {
            camera_screen=candidate;
            return record_editor_baseline()?"OK ALREADY_INITIALIZED":"ERROR Invalid initialized preview";
        }
        return "ERROR Editor already initialized with a different or incomplete context";
    }
    /* BindWidget fields prove the actual blueprint widget tree exists. Never
       initialize an unconstructed base class or run initialization twice. */
    const char *tree_error=editor_tree_error(candidate);if(tree_error)return tree_error;
    if(!object_ok(*(void**)(base+0xa8a6e10),0x28)) return "ERROR Editor settings manager unavailable";
    camera_screen=candidate;
    ((void(*)(void*))(base+0x1916830))(candidate);
    if(*(void**)((char*)candidate+0x488)!=actor||*(void**)((char*)candidate+0x578)!=camera_helper)
        return "ERROR Native editor requires the tagged Cat actor and camera helper";
    return record_editor_baseline()?"OK INITIALIZED":"ERROR Invalid initialized preview";
}
static void merge_appearance(Custom *out,const Custom *saved,const Custom *edited,const Custom *initial_preview) {
    /* The native player editor may normalize NPC-only options while mounting.
       Commit only later changes, retaining all untouched saved fields. */
    copy_custom(out,saved);
    for(unsigned off=0xc;off<0x64;off+=4)
        if(cosmetic_force_all||memcmp(edited->b+off,initial_preview->b+off,4))memcpy(out->b+off,edited->b+off,4);
    if(cosmetic_force_all||edited->b[0x64]!=initial_preview->b[0x64])out->b[0x64]=edited->b[0x64];
    if(cosmetic_force_all||memcmp(edited->b+0x68,initial_preview->b+0x68,4))memcpy(out->b+0x68,edited->b+0x68,4);
    /* This creator exposes Nature/Pattern/Markings/Colors. Size, wardrobe and
       scars have no controls here; preserve them even if native preview updates
       incidentally change those fields after initialization. */
}
static int preview_valid(void) {
    return bound && object_ok(actor,0x3c8)&&*(int32_t*)((char*)actor+0xc)==actor_index&&
      object_ok(*(void**)((char*)actor+0x2b8),0x210);
}
#include "appearance_library.h"
static int read_player(Custom *out,int selected_slot) {
    Str key={0};memset(out,0,sizeof(*out));
    return ((uint8_t(*)(Custom*,Str*,int32_t))(base+0x1813210))(out,&key,selected_slot)!=0;
}
static int read_target(Custom *out) {
    if(role==0)return read_player(out,slot);
    memset(out,0,sizeof(*out));read_npc(manager,out,role,slot);return custom_ok(out);
}
#include "player_skins.h"
static const char *begin_edit(unsigned r,unsigned clan) {
    if(active) return "ERROR Already editing a cat";
    if(r>254||clan<1||clan>5) return "ERROR Invalid cat identity";
    /* The code can be called from a patched engine entry while Lua hot-reloads.
       Pin it until process exit so a Lua collection cannot unload the hook. */
    HMODULE pinned;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,
                          (LPCWSTR)(uintptr_t)player_save_blocked,&pinned)) return "ERROR Cannot retain save guard";
    manager=*(void**)(base+0xa8a6e30);
    if(!object_ok(manager,0x170)) return "ERROR Save manager unavailable";
    save_game=*(void**)((char*)manager+0x168);
    if(!object_ok(save_game,0xa0)) return "ERROR Save unavailable";
    Str *g=(Str*)((char*)save_game+0x30);
    profile_index=*(int32_t*)((char*)save_game+0x78);
    if(profile_index<0||!string_ok(g)||g->count<2) return "ERROR No active profile";
    if(!current_character_slot(&flow_manager,&slot))return "ERROR No active character";
    Str *slots=*(Str**)((char*)save_game+0x68);
    int count=*(int*)((char*)save_game+0x70);
    if(profile_index>=count||count>128||!readable(slots,(size_t)count*sizeof(Str),NULL,0)||
       !string_ok(&slots[profile_index])||slots[profile_index].count<2) return "ERROR Profile unavailable";
    wcscpy(profile_id,slots[profile_index].data);
    wcscpy(gamer_id,g->data);owner_thread=GetCurrentThreadId();role=(uint8_t)r;expected_clan=(uint8_t)clan;
    int read_ok=read_target(&original);
    if(!read_ok||!custom_ok(&original)||original.b[0]!=expected_clan||((Str*)(original.b+0x70))->count<2) {
        destroy_custom(&original);return "ERROR Cat does not match active clan";
    }
    copy_custom(&pending,&original);have_pending=applied=bound=cancelled=native_intent=have_editor_baseline=0;suppressed=0;actor=NULL;
    active=1;
    if(!patch_writer(1)) {active=0;destroy_custom(&pending);destroy_custom(&original);return "ERROR Player save guard unavailable";}
    memset(editor_save_patch,0,14);editor_save_patch[0]=0xff;editor_save_patch[1]=0x25;
    void *hook=(void*)editor_save_blocked;memcpy(editor_save_patch+6,&hook,8);
    editor_save_guard=replace_code(10,editor_save_patch,14,1);
    tutorial_guard=replace_code(11,tutorial_patch,1,1);
    if(!editor_save_guard||!tutorial_guard) {
        if(editor_save_guard&&replace_code(10,editor_save_patch,14,0)) editor_save_guard=0;
        if(tutorial_guard&&replace_code(11,tutorial_patch,1,0)) tutorial_guard=0;
        if(editor_save_guard||tutorial_guard||!patch_writer(0))
            return "ERROR Guard cleanup required; no editor was opened";
        active=0;
        destroy_custom(&pending);destroy_custom(&original);return "ERROR Editor safety guards unavailable";
    }
    return "OK BEGIN";
}
static const char *bind_preview(uintptr_t p) {
    if(!same_context()||applied||cancelled||bound) return "ERROR Cannot bind preview";
    void *candidate=(void*)p;
    if(!object_ok(candidate,0x3c8)) return "ERROR Invalid editor actor";
    /* IsA(AGuiCatCustomActor), using UE's FStructBaseChain, not just offsets. */
    if(!class_is(candidate,0x18388c0)) return "ERROR Actor must be the game customization preview";
    void *component=*(void**)((char*)candidate+0x2b8);
    if(!object_ok(component,0x210)||!custom_ok((Custom*)((char*)component+0x118))) return "ERROR Preview is not ready";
    actor=candidate;actor_index=*(int32_t*)((char*)actor+0xc);
    copy_custom(&preview_original,(Custom*)((char*)component+0x118));bound=1;
    apply_preview(component,&original,0);
    return "OK BIND";
}
static const char *capture_preview(void) {
    if(comparing_original)return "ERROR Return to edited preview before applying";
    if(!same_context()||applied||cancelled||!preview_valid()) return "ERROR Preview unavailable";
    capture((Custom*)((char*)*(void**)((char*)actor+0x2b8)+0x118));
    return have_pending?"OK CAPTURE":"ERROR Invalid appearance";
}
static const char *apply_edit(void) {
    if(comparing_original)return "ERROR Return to edited preview before applying";
    if(!same_context()||applied||cancelled||!have_pending||!have_editor_baseline) return "ERROR No applicable initialized appearance";
    Custom fresh;int read_ok=read_target(&fresh);
    if(!read_ok||!custom_ok(&fresh)||!custom_equal(&fresh,&original)) {destroy_custom(&fresh);return "ERROR Cat changed while editing; cancel and reopen";}
    Custom merged;merge_appearance(&merged,&fresh,&pending,&editor_baseline);
    int changed=!custom_equal(&fresh,&merged);destroy_custom(&fresh);
    if(changed) {
        if(role==0) {
            /* Only the explicit Apply transaction may call the original player
               writer. No engine tick/editor teardown runs in this interval. */
            if(!patch_writer(0)){destroy_custom(&merged);return "ERROR Cannot authorize player appearance save";}
            Str key={0};((void(*)(const Custom*,Str*,int32_t))(base+0x1812f50))(&merged,&key,slot);
            if(!patch_writer(1)){destroy_custom(&merged);applied=1;return "ERROR Appearance saved but editor guard could not resume; close editor";}
        }else write_npc(role,&merged);
    }
    read_ok=read_target(&fresh);
    int verified=read_ok&&custom_ok(&fresh)&&custom_equal(&fresh,&merged);
    /* World-refresh reads this preview. Restore untouched NPC-only options too. */
    if(verified&&preview_valid())apply_preview(*(void**)((char*)actor+0x2b8),&merged,0);
    destroy_custom(&fresh);destroy_custom(&merged);
    /* Even on verification failure never let editor callbacks write the player. */
    applied=1;
    return verified?(changed?"OK APPLIED_QUEUED":"OK UNCHANGED"):"ERROR Save readback mismatch; guard remains active";
}
static const char *finish_edit(void) {
    if(!active||GetCurrentThreadId()!=owner_thread) return "ERROR No owned transaction";
    const char *camera_result=detach_screen();if(strncmp(camera_result,"OK ",3)) return camera_result;
    /* Root must wait for editor close before END. Do not dereference stale actors. */
    if(preview_valid()&&same_context()) apply_preview(*(void**)((char*)actor+0x2b8),&preview_original,0);
    if(screen) {
        if(readable(screen,0x28,NULL,0)&&*(int32_t*)((char*)screen+0xc)==screen_index) {
            if(*(void***)screen!=screen_clone&&*(void***)screen!=screen_original_vtable)
                return "ERROR Editor vtable changed; guard remains active";
            *(void***)screen=screen_original_vtable;
        }
        VirtualFree(screen_clone-1,0,MEM_RELEASE);screen=NULL;screen_clone=NULL;screen_original_vtable=NULL;
    }
    if(editor_save_guard&&!replace_code(10,editor_save_patch,14,0)) return "ERROR Cannot restore editor save handler";
    editor_save_guard=0;
    if(tutorial_guard&&!replace_code(11,tutorial_patch,1,0)) return "ERROR Cannot restore tutorial handler";
    tutorial_guard=0;
    if(writer_installed&&!patch_writer(0)) return "ERROR Cannot remove player save guard; keep editor closed";
    cosmetic_release();cosmetic_force_all=0;
    if(bound) destroy_custom(&preview_original);
    if(have_editor_baseline)destroy_custom(&editor_baseline);
    destroy_custom(&pending);destroy_custom(&original);
    active=bound=have_pending=applied=cancelled=have_editor_baseline=0;actor=NULL;
    return "OK END";
}
static const char *portrait_preview(unsigned r,uintptr_t address) {
    /* This API applies to an OWNED, off-screen GuiCatCustomActor supplied by
       root. Never pass CatHud or the editor's borrowed preview here. */
    if(r==0||r>254) return "ERROR Invalid portrait role";
    void *preview=(void*)address;
    if(preview==actor||!object_ok(preview,0x3c8)||!class_is(preview,0x18388c0)) return "ERROR Invalid owned portrait actor";
    void *m=*(void**)(base+0xa8a6e30),*mesh=*(void**)((char*)preview+0x2b8);
    if(!object_ok(m,0x170)||!object_ok(mesh,0x210)) return "ERROR Portrait context unavailable";
    Custom data;memset(&data,0,sizeof(data));read_npc(m,&data,(uint8_t)r,-1);
    if(!custom_ok(&data)||((Str*)(data.b+0x70))->count<2) {destroy_custom(&data);return "ERROR Portrait cat is unavailable";}
    apply_preview(mesh,&data,0);destroy_custom(&data);
    return "OK PORTRAIT_DATA_READY";
}
static const char *cat_metadata(unsigned r) {
    static char response[128];
    if(r==0||r>254) return "ERROR Invalid cat role";
    void *m=*(void**)(base+0xa8a6e30);
    if(!object_ok(m,0x170)) return "ERROR Save manager unavailable";
    Custom data;memset(&data,0,sizeof(data));read_npc(m,&data,(uint8_t)r,-1);
    if(!custom_ok(&data)||((Str*)(data.b+0x70))->count<2) {destroy_custom(&data);return "ERROR Cat unavailable";}
    snprintf(response,sizeof(response),"OK META narrative=%u clan=%u rank=%u",r,data.b[0],data.b[1]);
    destroy_custom(&data);return response;
}
__declspec(dllexport) int ClanAppearance_dispatch(void *lua_state) {
    (void)lua_state;unsigned id=0,r=0,clan=0;unsigned long long address=0;char command[24]={0},tail;
    FILE *f=local_file(L"appearance-request.txt",L"r");
    if(!f){report(0,"ERROR Missing request");return 0;}
    char line[1024];if(!fgets(line,sizeof(line),f)){fclose(f);report(0,"ERROR Empty request");return 0;}fclose(f);
    if(sscanf(line,"%u %23s",&id,command)!=2){report(id,"ERROR Invalid request");return 0;}
    if(!initialize()){report(id,"ERROR Unsupported executable");return 0;}
    const char *result="ERROR Unknown command";
    if(!strcmp(command,"BEGIN")&&sscanf(line,"%u %23s %u %u %c",&id,command,&r,&clan,&tail)==4) result=begin_edit(r,clan);
    else if(!strcmp(command,"BIND")&&sscanf(line,"%u %23s %llx %c",&id,command,&address,&tail)==3) result=bind_preview((uintptr_t)address);
    else if(!strcmp(command,"GUARD_SCREEN")&&sscanf(line,"%u %23s %llx %c",&id,command,&address,&tail)==3) result=guard_screen((uintptr_t)address);
    else if(!strcmp(command,"INIT_SCREEN")&&sscanf(line,"%u %23s %llx %c",&id,command,&address,&tail)==3) result=initialize_screen((uintptr_t)address);
    else if(!strcmp(command,"BORROW_CAMERA")&&sscanf(line,"%u %23s %llx %c",&id,command,&address,&tail)==3) result=borrow_camera((uintptr_t)address);
    else if(!strcmp(command,"CAMERA_TARGET")&&sscanf(line,"%u %23s %u %llx %c",&id,command,&r,&address,&tail)==4) result=camera_target(r,(uintptr_t)address);
    else if(!strcmp(command,"DETACH_SCREEN")) result=detach_screen();
    else if(!strcmp(command,"PORTRAIT")&&sscanf(line,"%u %23s %u %llx %c",&id,command,&r,&address,&tail)==4) result=portrait_preview(r,(uintptr_t)address);
    else if(!strcmp(command,"META")&&sscanf(line,"%u %23s %u %c",&id,command,&r,&tail)==3) result=cat_metadata(r);
    else if(!strcmp(command,"STATUS")) result="OK STATUS";
    else if(!strcmp(command,"CONTEXT_LAYOUT")) result="OK CONTEXT_LAYOUT flow_slot=340";
    else if(!strcmp(command,"CAPTURE")) result=capture_preview();
    else if(!strcmp(command,"PLAYER_READ")) result=player_skin_read();
    else if(!strcmp(command,"PLAYER_REFRESH")&&sscanf(line,"%u %23s %llx %c",&id,command,&address,&tail)==3) result=player_skin_refresh((uintptr_t)address);
    else if(!strcmp(command,"SKIN_PORTRAIT")||!strcmp(command,"CREATOR_LOAD")||!strcmp(command,"CREATOR_READ")) result=skin_external_command(command,line);
    else if(!strcmp(command,"PREVIEW_READ"))result=cosmetic_export(0);
    else if(!strcmp(command,"ORIGINAL_READ"))result=cosmetic_export(1);
    else if(!strcmp(command,"PREVIEW_LOAD")) {
        int used=0;if(sscanf(line,"%u %23s %n",&id,command,&used)==2&&used>0)result=cosmetic_import(line+used);
    }
    else if(!strcmp(command,"RANDOMIZE"))result=cosmetic_randomize();
    else if(!strcmp(command,"COMPARE")&&sscanf(line,"%u %23s %u %c",&id,command,&r,&tail)==3)result=cosmetic_compare((int)r);
    else if(!strcmp(command,"RESET")) {
        if(same_context()&&!applied&&!cancelled&&preview_valid()) {
            cosmetic_release();cosmetic_force_all=0;
            apply_preview(*(void**)((char*)actor+0x2b8),&original,0);
            refresh_current_panel();
            assign_custom(&pending,&original);have_pending=0;result="OK RESET";
        } else result="ERROR Preview unavailable";
    }
    else if(!strcmp(command,"APPLY")) result=apply_edit();
    else if(!strcmp(command,"CANCEL")) {
        if(active&&GetCurrentThreadId()==owner_thread){cancelled=1;have_pending=0;result="OK CANCEL";}
        else result="ERROR No owned transaction";
    }
    else if(!strcmp(command,"END")) result=finish_edit();
    report(id,result);return 0;
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID unused) {
    (void)unused;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;
}
