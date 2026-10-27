/* Game-thread-only health setter adapter, exact Steam build 26184573.
 * Calls the game's resource setter so HUD/delegates are notified. No save edit.
 * Lua supplies the live main-player health component, class and owner pointers.
 * A read-only probe must precede use. All pointer/class/code guards fail closed.
 */
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
static int build_ok(void) {
    static const unsigned char code[]={0x40,0x53,0x48,0x83,0xec,0x50,0x48,0x8b,0x05,0x33,0xe1,0xe2,0x08,0x48,0x33,0xc4};
    base=(unsigned char*)GetModuleHandleW(NULL);
    if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
    IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<(LONG)sizeof(*dos)||dos->e_lfanew>0x100000)return 0;
    IMAGE_NT_HEADERS64 *nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    if(!readable(nt,sizeof(*nt),base,0)||nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||
       nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||nt->OptionalHeader.SizeOfImage!=187576320u||nt->FileHeader.TimeDateStamp!=3539680621u)return 0;
    return readable(base+0x16554f0,sizeof(code),base,1)&&memcmp(base+0x16554f0,code,sizeof(code))==0;
}
static int run(int apply) {
    unsigned long long nonce=0,c=0,owner=0,cls=0;
    const char *message="Invalid request";
    float current=0,maximum=0,after=0;uintptr_t setter_rva=0;
    FILE *request=local_file(L"admin-heal-request.txt",L"r");
    if(!request)goto done;
    int fields=fscanf(request,"%llu %llx %llx %llx",&nonce,&c,&owner,&cls);
    int extra=fgetc(request);while(extra=='\n'||extra=='\r'||extra==' '||extra=='\t')extra=fgetc(request);
    fclose(request);
    if(fields!=4||extra!=EOF||!nonce)goto done;
    if(!game_thread)game_thread=GetCurrentThreadId();
    if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
    if(!build_ok()){message="Unsupported game build";goto done;}
    unsigned char *component=(unsigned char*)(uintptr_t)c;
    if(!readable(component,0x128,NULL,0)||!readable((void*)(uintptr_t)owner,0x28,NULL,0)||!readable((void*)(uintptr_t)cls,0x40,NULL,0)){
        message="Invalid object mappings";goto done;
    }
    if(*(uintptr_t*)(component+0x10)!=(uintptr_t)cls||*(uintptr_t*)(component+0x20)!=(uintptr_t)owner){
        message="Health class or owner mismatch";goto done;
    }
    uintptr_t *vt=*(uintptr_t**)component;
    if(!readable(vt,0x518,base,0)){message="Invalid resource vtable";goto done;}
    uintptr_t setter=*(uintptr_t*)((unsigned char*)vt+0x510);
    setter_rva=setter-(uintptr_t)base;
    if(setter!=(uintptr_t)(base+0x16554f0)){message="Unsupported resource setter";goto done;}
    if(component[0x104]>1){message="Invalid resource maximum mode";goto done;}
    memcpy(&current,component+0x10c,4);
    /* Health's override clamps to the computed maximum at +0x110, independently
       of the denominator selector used for percentage display. */
    memcpy(&maximum,component+0x110,4);
    if(!isfinite(current)||!isfinite(maximum)||maximum<=0||maximum>1000000||current<0||current>maximum+0.01f){message="Invalid health bounds";goto done;}
    if(apply)((void(*)(void*,float))setter)(component,maximum);
    memcpy(&after,component+0x10c,4);
    if(!isfinite(after)||(apply&&fabsf(after-maximum)>0.01f)){message="Health readback mismatch";goto done;}
    message=apply?"HEALED":"READY";
done:;
    FILE *status=local_file(L"admin-heal-status.txt",L"w");
    if(status){fprintf(status,"nonce=%llu\nstatus=%s\ncurrent=%.9g\nmaximum=%.9g\nafter=%.9g\nsetter_rva=%llx\n",nonce,message,current,maximum,after,(unsigned long long)setter_rva);fclose(status);}
    return 0;
}
__declspec(dllexport) int ClanToolsHeal_probe(void *lua_state){(void)lua_state;return run(0);}
__declspec(dllexport) int ClanToolsHeal_apply(void *lua_state){(void)lua_state;return run(1);}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
