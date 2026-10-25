/* Applies saved clan appearance to an owned walking-NPC component, no save write.
 * Lua supplies exact class pointers after validating the spawned actor class. */
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
static char readback_detail[1024];
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
static int custom_equal(const unsigned char *a,const unsigned char *b) {
    /* FCatCustomData has padding and six deep-owned FString allocations. */
    if(!readable(a,0xf8,NULL,0)||!readable(b,0xf8,NULL,0))return 0;
    if(memcmp(a,b,2)||memcmp(a+4,b+4,0x60)||a[0x64]!=b[0x64]||
       memcmp(a+0x68,b+0x68,4)||a[0x90]!=b[0x90]||
       memcmp(a+0x94,b+0x94,4)||memcmp(a+0xd8,b+0xd8,0x20))return 0;
    const unsigned offsets[]={0x70,0x80,0x98,0xa8,0xb8,0xc8};
    for(unsigned i=0;i<6;i++) {
        const unsigned char *x=a+offsets[i],*y=b+offsets[i];
        int nx=*(const int*)(x+8),ny=*(const int*)(y+8);
        if(nx<0||ny<0||nx>65536||ny>65536)return 0;
        if(nx)nx--;if(ny)ny--;
        if(nx!=ny)return 0;
        if(nx&&(!readable(*(void*const*)x,(size_t)(nx+1)*2,NULL,0)||
           !readable(*(void*const*)y,(size_t)(ny+1)*2,NULL,0)||
           memcmp(*(void*const*)x,*(void*const*)y,(size_t)nx*2)))return 0;
    }
    return 1;
}
static void custom_diff(const unsigned char *actual,const unsigned char *expected) {
    const unsigned ranges[][2]={{0,2},{4,0x60},{0x64,1},{0x68,4},{0x90,1},{0x94,4},{0xd8,0x20}};
    size_t used=0;unsigned count=0;
    for(unsigned r=0;r<7;r++)for(unsigned j=0;j<ranges[r][1];j++) {
        unsigned o=ranges[r][0]+j;if(actual[o]==expected[o])continue;
        if(count++<24&&used<sizeof(readback_detail)-40)
            used+=(size_t)snprintf(readback_detail+used,sizeof(readback_detail)-used,"%s%02x:%02x>%02x",used?",":"",o,expected[o],actual[o]);
    }
    const unsigned strings[]={0x70,0x80,0x98,0xa8,0xb8,0xc8};
    for(unsigned i=0;i<6&&used<sizeof(readback_detail)-100;i++) {
        unsigned o=strings[i];int a=*(const int*)(actual+o+8),e=*(const int*)(expected+o+8);
        int equal=a==e&&a>=0&&a<=65536&&(!a||(readable(*(void*const*)(actual+o),(size_t)a*2,NULL,0)&&readable(*(void*const*)(expected+o),(size_t)a*2,NULL,0)&&!memcmp(*(void*const*)(actual+o),*(void*const*)(expected+o),(size_t)a*2)));
        if(!equal)used+=(size_t)snprintf(readback_detail+used,sizeof(readback_detail)-used,"%sstring%02x:length%d>%d",used?",":"",o,e,a);
    }
    if(!used)snprintf(readback_detail,sizeof(readback_detail),"comparison_failed_without_scalar_difference");
}

#include "follower_guards.h"
static int build_ok(void) {
    base=(unsigned char*)GetModuleHandleW(NULL);
    if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<64||dos->e_lfanew>0x100000)return 0;
    IMAGE_NT_HEADERS64 *nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    if(!readable(nt,sizeof(*nt),base,0)||nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||
       nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||nt->OptionalHeader.SizeOfImage!=187576320u||nt->FileHeader.TimeDateStamp!=141614920u)return 0;
    unsigned ids[]={1,5,7};
    for(unsigned i=0;i<3;i++) {
        const AppearanceGuard *g=&appearance_guards[ids[i]];
        if(!readable(base+g->rva,16,base,1)||memcmp(base+g->rva,g->bytes,16))return 0;
    }return 1;
}
__declspec(dllexport) int ClanFollowers_appearance(void *lua_state) {
    (void)lua_state;
    readback_detail[0]=0;
    unsigned long long nonce=0,a=0,c=0,ac=0,cc=0;unsigned role=0,clan=0;
    const char *message="Invalid request";
    FILE *request=local_file(L"follower-request.txt",L"r");
    if(!request)goto done;
    int fields=fscanf(request,"%llu %llx %llx %llx %llx %u %u",&nonce,&a,&c,&ac,&cc,&role,&clan);
    int extra=fgetc(request);while(extra=='\n'||extra=='\r'||extra==' '||extra=='\t')extra=fgetc(request);
    fclose(request);
    if(fields!=7||extra!=EOF||!nonce||role<1||role>254||clan<1||clan>5)goto done;
    if(!game_thread)game_thread=GetCurrentThreadId();
    if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
    if(!build_ok()){message="Unsupported game build";goto done;}
    unsigned char *actor=(void*)(uintptr_t)a,*component=(void*)(uintptr_t)c;
    if(!readable(actor,0x9a0,NULL,0)||!readable(component,0x250,NULL,0)||!readable((void*)(uintptr_t)ac,0x40,NULL,0)||!readable((void*)(uintptr_t)cc,0x40,NULL,0)){
        message="Invalid object mappings";goto done;
    }
    if(*(uintptr_t*)(actor+0x10)!=(uintptr_t)ac||*(uintptr_t*)(component+0x10)!=(uintptr_t)cc||
       *(uintptr_t*)(component+0x20)!=(uintptr_t)a||*(uintptr_t*)(actor+0x860)!=(uintptr_t)c){
        message="Follower class or owner mismatch";goto done;
    }
    if(actor[0x890]!=1&&actor[0x890]!=2){message="Follower character type is not Cat";goto done;}
    if(!readable(base+0xa8a6e30,8,base,0)){message="Save manager unavailable";goto done;}
    void *manager=*(void**)(base+0xa8a6e30);
    if(!readable(manager,0x170,NULL,0)){message="Save manager unavailable";goto done;}
    _Alignas(8) unsigned char custom[0xf8]={0};
    ((void*(*)(void*,void*,uint8_t,int32_t))(base+0x194a600))(manager,custom,(uint8_t)role,-1);
    int prefix_count=*(int*)(custom+0x78);float size=*(float*)(custom+0x94);
    int strings_ok=1;unsigned string_offsets[]={0x70,0x80,0x98,0xa8,0xb8,0xc8};
    for(unsigned i=0;i<6;i++) {
        unsigned char *s=custom+string_offsets[i];int count=*(int*)(s+8),capacity=*(int*)(s+12);
        if(count<0||count>65536||capacity<count||capacity>1048576||(count&&!readable(*(void**)s,(size_t)count*2,NULL,0)))strings_ok=0;
    }
    if(!strings_ok||custom[0]!=(unsigned char)clan||prefix_count<2||prefix_count>256||!isfinite(size)||size<0||size>100){
        message="Selected clan cat is unavailable";
    }else{
        /* A temporary copy must retain this clanmate's colors; false would let
         * the native method substitute player colors. No save setter is used. */
        custom[0x64]=1;
        ((void(*)(void*,const void*,uint8_t))(base+0x17b0d20))(component,custom,0);
        /* Apply calls17B1980(component, BodyValue, true), which stores the
         * selected mesh index in FurIdx(+44). Normalize the temporary expected
         * readback to that derived cache; never overwrite the component/save. */
        memcpy(custom+0x44,custom+0x28,4);
        message=custom_equal(component+0x118,custom)?"APPLIED":"Appearance readback mismatch";
        if(strcmp(message,"APPLIED"))custom_diff(component+0x118,custom);
    }
    ((void(*)(void*))(base+0x17088f0))(custom);
 done:;
    FILE *status=local_file(L"follower-status.txt",L"w");
    if(status){fprintf(status,"nonce=%llu\nstatus=%s\n",nonce,message);if(readback_detail[0])fprintf(status,"readback_differences=%s\n",readback_detail);fclose(status);}return 0;
}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}

