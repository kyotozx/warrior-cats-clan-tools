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
#include "admin_quest_guards.h"
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
    unsigned long long nonce=0,q=0,pc=0,manager=0;char command[24]={0};int expected_status=0,expected_count=0;
    const char *message="Invalid request";int status=-1,result=-1,count=-1,active=-1,in_progress=0,after=-1,stepped=0,objective_index=-1;
    uintptr_t objective_vtable=0,objective_status_rva=0,objective_finish_rva=0;
    FILE *request=local_file(L"admin-quest-request.txt",L"r");if(!request)goto done;
    int fields=fscanf(request,"%llu %23s %llx %llx %llx %d %d",&nonce,command,&q,&pc,&manager,&expected_status,&expected_count);
    int extra=fgetc(request);while(extra=='\r'||extra=='\n'||extra==' '||extra=='\t')extra=fgetc(request);fclose(request);
    int probe=!strcmp(command,"QUEST_PROBE"),step=!strcmp(command,"QUEST_STEP"),turnin=!strcmp(command,"QUEST_TURN_IN");
    if(fields!=7||extra!=EOF||!nonce||(!probe&&!step&&!turnin)||expected_status<0||expected_status>4||expected_count<0||expected_count>1000000)goto done;
    if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
    if(!build_ok()){message="Unsupported game build";goto done;}
    if(!manager_ok((void*)(uintptr_t)manager)){message="Save manager changed";goto done;}
    unsigned char *quest=(void*)(uintptr_t)q,*player=(void*)(uintptr_t)pc;
    if(!readable(quest,0x398,NULL,0)||!readable(player,0x28,NULL,0)||
       (*(void**)quest!=base+0x9a734c0&&*(void**)quest!=base+0x9b57758)){message="Unsupported quest instance";goto done;}
    if(*(void**)quest==base+0x9b57758&&!readable(quest,0x3f0,NULL,0)){message="Invalid adventure quest mapping";goto done;}
    void *graph=*(void**)(quest+0x58);
    if(!readable(graph,0xc8,NULL,0)||*(void**)((unsigned char*)graph+0xc0)!=quest){message="Quest graph ownership mismatch";goto done;}
    void *owning=((void*(*)(void*))(base+0x1d14b30))(quest+0x260);
    if(owning!=player){message="Quest belongs to another player";goto done;}
    void *qm=*(void**)(base+0xa8b73e0);if(!readable(qm,0x48,NULL,0)){message="Quest manager unavailable";goto done;}
    status=((uint8_t(*)(void*))(base+0x16c75b0))(quest);
    /* Accept virtual340 intentionally resets reflected caches. These original
       getters read the selected graph's QuestAlias data in the active save. */
    result=((uint8_t(*)(void*))(base+0x16c7490))(quest);
    count=((int(*)(void*))(base+0x16c7430))(quest);active=*(int*)(quest+0x338);
    if((status!=2&&status!=3&&status!=4)||result<0||result>2||count<0||count>1000000||active<0||active>128){message="Invalid quest state";goto done;}
    void **objectives=*(void***)(quest+0x330);void *next=NULL,*next_finish=NULL;
    if(active&&!readable(objectives,(size_t)active*8,NULL,0)){message="Invalid objective collection";goto done;}
    for(int i=0;i<active;i++) {
        unsigned char *objective=objectives[i];
        if(!readable(objective,0x148,NULL,0)||*(void**)(objective+0x100)!=quest){message="Objective ownership mismatch";goto done;}
        unsigned char *vt=*(void**)objective;
        objective_index=i;objective_vtable=(uintptr_t)vt-(uintptr_t)base;
        if(readable(vt,0x518,base,0)){
            objective_status_rva=(uintptr_t)*(void**)(vt+0x410)-(uintptr_t)base;
            objective_finish_rva=(uintptr_t)*(void**)(vt+0x3d8)-(uintptr_t)base;
        }
        if(!readable(vt,0x518,base,0)||*(void**)(vt+0x410)!=base+0x16daff0){message="Unsupported objective handlers";goto done;}
        void *finish=*(void**)(vt+0x3d8);
        if(finish!=base+0x16d7ec0&&!(vt==base+0x9a68190&&finish==base+0x16cfd80&&readable(objective,0x1a8,NULL,0))){message="Unsupported objective handlers";goto done;}
        int objective_status=((uint8_t(*)(void*))(base+0x16daff0))(objective);
        if(objective_status<0||objective_status>4){message="Invalid objective status";goto done;}
        if(objective_status==1){in_progress++;if(!next){next=objective;next_finish=finish;}}
        if(turnin&&objective_status!=4){message="Quest still has unfinished objectives";goto done;}
    }
    if(!probe&&(status!=expected_status||count!=expected_count)){message="Quest preview is stale";goto done;}
    if(step) {
        if(status!=2||!next){message="No active objective is ready";goto done;}
        /* Full virtual success handler: objective tasks, save update, graph advance. */
        ((void(*)(void*,uint8_t))next_finish)(next,4);stepped=1;
    }else if(turnin) {
        if(status!=3||result!=1){message="Only successful completed quests may be turned in";goto done;}
        /* Ordinary turn-in dispatches reward delegates and sets TurnedIn once. */
        ((void(*)(void*))(base+0x16c1a20))(quest);
    }
    after=((uint8_t(*)(void*))(base+0x16c75b0))(quest);
    if(turnin&&after!=4){message="Quest turn-in was not confirmed";goto done;}
    message=probe?"READY":"APPLIED";
done:;
    FILE *out=local_file(L"admin-quest-status.txt",L"w");if(out){fprintf(out,"nonce=%llu\nstatus=%s\nquest_status=%d\nresult=%d\ncount=%d\nactive=%d\nin_progress=%d\nafter=%d\nstepped=%d\nobjective_index=%d\nobjective_vtable=%llx\nobjective_status_rva=%llx\nobjective_finish_rva=%llx\n",nonce,message,status,result,count,active,in_progress,after,stepped,objective_index,(unsigned long long)objective_vtable,(unsigned long long)objective_status_rva,(unsigned long long)objective_finish_rva);fclose(out);}return 0;
}
__declspec(dllexport) int ClanQuests_run(void *lua_state){(void)lua_state;return run();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
