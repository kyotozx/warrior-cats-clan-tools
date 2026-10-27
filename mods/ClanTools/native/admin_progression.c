/* Exact-build offline progression bridge. Invoked synchronously on game thread. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
static HMODULE self;
static DWORD game_thread;
static unsigned char *base;
static int readable(const void *p,size_t n,const void *allocation,int executable) {
    uintptr_t x=(uintptr_t)p,end=x+n;
    if(!x||end<x)return 0;
    while(x<end) {
        MEMORY_BASIC_INFORMATION m;
        if(!VirtualQuery((void*)x,&m,sizeof(m))||m.State!=MEM_COMMIT||
           (allocation&&m.AllocationBase!=allocation)||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
        DWORD q=m.Protect&255;
        if(q!=PAGE_READONLY&&q!=PAGE_READWRITE&&q!=PAGE_WRITECOPY&&q!=PAGE_EXECUTE_READ&&q!=PAGE_EXECUTE_READWRITE&&q!=PAGE_EXECUTE_WRITECOPY)return 0;
        if(executable&&q!=PAGE_EXECUTE_READ&&q!=PAGE_EXECUTE_READWRITE&&q!=PAGE_EXECUTE_WRITECOPY)return 0;
        uintptr_t next=(uintptr_t)m.BaseAddress+m.RegionSize;
        if(next<=x)return 0;x=next;
    }return 1;
}
static FILE *local_file(const wchar_t *name,const wchar_t *mode) {
    wchar_t p[32768];DWORD n=GetModuleFileNameW(self,p,32768);
    if(!n||n>=32768)return NULL;
    wchar_t *slash=wcsrchr(p,L'\\');if(!slash)return NULL;
    slash[1]=0;if(wcslen(p)+wcslen(name)>=32768)return NULL;
    wcscat(p,name);return _wfopen(p,mode);
}
#include "admin_progression_guards.h"
static int build_ok(void) {
    base=(unsigned char*)GetModuleHandleW(NULL);
    if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<64||dos->e_lfanew>0x100000)return 0;
    IMAGE_NT_HEADERS64 *nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    if(!readable(nt,sizeof(*nt),base,0)||nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||
       nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||nt->OptionalHeader.SizeOfImage!=187576320u||nt->FileHeader.TimeDateStamp!=3539680621u)return 0;
    for(unsigned i=0;i<sizeof(guards)/sizeof(guards[0]);i++)if(!readable(base+guards[i].rva,16,base,1)||memcmp(base+guards[i].rva,guards[i].code,16))return 0;
    return 1;
}
static int manager_ok(void *supplied) {
    if(!readable(base+0xa8a6e30,8,base,0)||*(void**)(base+0xa8a6e30)!=supplied||!readable(supplied,0x248,NULL,0))return 0;
    return *(void**)supplied==base+0x9c5a928;
}
static int run(void) {
    unsigned long long nonce=0,object=0,owner=0,cls=0,manager=0;
    unsigned role=0; char command[24]={0}; double expected=0,target=0;
    const char *message="Invalid request";float current=0,maximum=0,after=0;int before_rank=-1,after_rank=-1;
    FILE *request=local_file(L"admin-progression-request.txt",L"r");if(!request)goto done;
    int fields=fscanf(request,"%llu %23s %llx %llx %llx %llx %u %lf %lf",&nonce,command,&object,&owner,&cls,&manager,&role,&expected,&target);
    int extra=fgetc(request);while(extra=='\r'||extra=='\n'||extra==' '||extra=='\t')extra=fgetc(request);fclose(request);
    int pile=!strcmp(command,"PILE_PROBE")||!strcmp(command,"PILE_FILL")||!strcmp(command,"PILE_SET");
    int bond=!strcmp(command,"BOND_PROBE")||!strcmp(command,"BOND_SET");
    int apply=!strcmp(command,"PILE_FILL")||!strcmp(command,"PILE_SET")||!strcmp(command,"BOND_SET");
    if(fields!=9||extra!=EOF||!nonce||(!pile&&!bond)||!isfinite(expected)||!isfinite(target))goto done;
    if(bond&&(role<1||role>254||expected<0||expected>100||floor(expected)!=expected||target<0||target>100||floor(target)!=target))goto done;
    if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
    if(!build_ok()){message="Unsupported game build";goto done;}
    if(!manager_ok((void*)(uintptr_t)manager)){message="Save manager changed";goto done;}
    if(pile) {
        unsigned char *component=(void*)(uintptr_t)object,*state=(void*)(uintptr_t)owner;
        if(!readable(component,0x198,NULL,0)||!readable(state,0x520,NULL,0)||!readable((void*)(uintptr_t)cls,0x40,NULL,0)) {message="Invalid pile mappings";goto done;}
        if(*(uintptr_t*)(component+0x10)!=(uintptr_t)cls||*(void**)(component+0x20)!=state||*(void**)(state+0x508)!=component||*(void**)component!=base+0x9b3a860) {message="Pile class or owner mismatch";goto done;}
        if(component[0x104]>1){message="Invalid capacity mode";goto done;}
        current=*(float*)(component+0x10c);maximum=*(float*)(component+(component[0x104]?0x100:0x110));
        float scale=*(float*)(component+0x114),offset=*(float*)(component+0x118),elapsed=*(float*)(component+0x130);int cycles=*(int*)(component+0x13c);
        if(!isfinite(current)||!isfinite(maximum)||current<0||maximum<=0||maximum>1000000||current>maximum||!isfinite(scale)||scale<=0||scale>100||!isfinite(offset)||fabsf(offset)>10000||!isfinite(elapsed)||elapsed<0||elapsed>1000000||cycles<0||cycles>1000000){message="Invalid pile bounds";goto done;}
        if(apply) {
            if(fabs(current-expected)>0.01||target<0||target>maximum||(!strcmp(command,"PILE_FILL")&&fabs(maximum-target)>0.01)){message="Pile preview is stale";goto done;}
            if(fabs(current-target)>0.01) {
                float delta=((float)target-current-offset)/scale;
                if(!isfinite(delta)||fabsf(delta)>1000000||(current<=0&&delta<=0)||(current>=maximum&&delta>0)){message="Unsupported pile modifiers";goto done;}
                ((void(*)(void*,float))(base+0x17c1be0))(component,delta);
                after=*(float*)(component+0x10c);
                if(!isfinite(after)||fabsf(after-(float)target)>0.01f){message="Pile readback mismatch";goto done;}
                /* Preserve decay cycle/timer, serialize via the game's own save path. */
                ((void(*)(float,int,float))(base+0x18103d0))(after,cycles,elapsed);
            }
        }
        after=*(float*)(component+0x10c);
    } else {
        /* Gallery callback requires the active NPC manager; reject uninitialized saves. */
        void *npcs=*(void**)(base+0xa8b73e8);
        if(!readable(npcs,0x28,NULL,0)){message="NPC manager unavailable";goto done;}
        int value=((int(*)(uint8_t,int))(base+0x16a11b0))((uint8_t)role,-1);
        if(value<0||value>100){message="Invalid bond bounds";goto done;}
        current=(float)value;maximum=100;
        before_rank=((uint8_t(*)(int))(base+0x168f870))(value);
        if(apply) {
            if(value!=(int)expected){message="Bond preview is stale";goto done;}
            if(value!=(int)target)((void(*)(uint8_t,int))(base+0x16a0e90))((uint8_t)role,(int)target-value);
        }
        after=(float)((int(*)(uint8_t,int))(base+0x16a11b0))((uint8_t)role,-1);
        after_rank=((uint8_t(*)(int))(base+0x168f870))((int)after);
        if(apply&&after!=(float)target){message="Bond readback mismatch";goto done;}
    }
    message=apply?"APPLIED":"READY";
done:;
    FILE *status=local_file(L"admin-progression-status.txt",L"w");
    if(status){fprintf(status,"nonce=%llu\nstatus=%s\ncurrent=%.9g\nmaximum=%.9g\nafter=%.9g\nrank=%d\nafter_rank=%d\n",nonce,message,current,maximum,after,before_rank,after_rank);fclose(status);}return 0;
}
__declspec(dllexport) int ClanProgression_run(void *lua_state){(void)lua_state;return run();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}

