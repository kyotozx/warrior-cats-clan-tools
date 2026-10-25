/* Read-only ownership preflight for the native generator SpawnedPreys array.
 * Invoke only on the game thread, immediately before the Lua cleanup action. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <ctype.h>
static HMODULE self;
static DWORD game_thread;
typedef struct { int32_t index,serial; } Weak;
typedef struct { Weak *data; int32_t count,capacity; } WeakArray;
_Static_assert(sizeof(Weak)==8 && sizeof(WeakArray)==16,"Engine weak array ABI");
static int readable(const void *p,size_t size) {
    uintptr_t at=(uintptr_t)p,end=at+size;
    if(!at||end<at)return 0;
    while(at<end){MEMORY_BASIC_INFORMATION m;
        if(!VirtualQuery((void*)at,&m,sizeof(m))||m.State!=MEM_COMMIT||
           (m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
        DWORD flags=m.Protect&255;
        if(flags!=PAGE_READONLY&&flags!=PAGE_READWRITE&&flags!=PAGE_WRITECOPY&&
           flags!=PAGE_EXECUTE_READ&&flags!=PAGE_EXECUTE_READWRITE&&flags!=PAGE_EXECUTE_WRITECOPY)return 0;
        uintptr_t next=(uintptr_t)m.BaseAddress+m.RegionSize;
        if(next<=at)return 0;at=next;
    }return 1;
}
static FILE *local_file(const wchar_t *name,const wchar_t *mode){
    wchar_t p[32768];DWORD n=GetModuleFileNameW(self,p,32768);
    if(!n||n>=32768)return NULL;
    wchar_t *slash=wcsrchr(p,L'\\');if(!slash)return NULL;slash[1]=0;
    if(wcslen(p)+wcslen(name)>=32768)return NULL;
    wcscat(p,name);return _wfopen(p,mode);
}
static void report(unsigned long long nonce,const char *reason,int count,int live){
    FILE*f=local_file(L"enemy-cleanup-status.txt",L"w");if(!f)return;
    if(reason)fprintf(f,"%llu REFUSED %s\n",nonce,reason);
    else fprintf(f,"%llu SAFE %d %d\n",nonce,count,live);
    fclose(f);
}
static int exact_object(void *p,void *klass,size_t size){
    return readable(p,size)&&readable(klass,0x28)&&*(void**)((char*)p+0x10)==klass;
}
static const char *check_array(void *gen,void *genclass,void *player,void *enemyclass,
    char (*weak_valid)(const Weak*),void*(*weak_get)(const Weak*),int *total,int *live){
    if(!exact_object(gen,genclass,0x3d8)||!readable(player,0x28)||!readable(enemyclass,0x28))return "Invalid object or class";
    WeakArray a;memcpy(&a,(char*)gen+0x3c8,sizeof(a));
    if(a.count<0||a.count>128||a.capacity<a.count||a.capacity>4096||
       (a.count&&!readable(a.data,(size_t)a.count*sizeof(Weak))))return "Invalid SpawnedPreys array";
    *total=a.count;*live=0;
    for(int i=0;i<a.count;i++){
        if(!weak_valid(a.data+i))continue;
        void *actor=weak_get(a.data+i);if(!actor)return "Weak actor changed during inspection";
        if(actor==player)return "SpawnedPreys contains protected player";
        if(!exact_object(actor,enemyclass,0x890))return "SpawnedPreys contains unexpected actor class";
        if(*(void**)((char*)actor+0x888)!=gen)return "SpawnedPreys ownership does not match";
        ++*live;
    }return NULL;
}
static int build_functions(char (**valid)(const Weak*),void*(**get)(const Weak*)){
    unsigned char*b=(unsigned char*)GetModuleHandleW(NULL);
    if(!readable(b,sizeof(IMAGE_DOS_HEADER)))return 0;
    IMAGE_DOS_HEADER*d=(IMAGE_DOS_HEADER*)b;
    if(d->e_magic!=IMAGE_DOS_SIGNATURE||d->e_lfanew<64||d->e_lfanew>0x100000)return 0;
    IMAGE_NT_HEADERS64*n=(IMAGE_NT_HEADERS64*)(b+d->e_lfanew);
    if(!readable(n,sizeof(*n))||n->Signature!=IMAGE_NT_SIGNATURE||
       n->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||n->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||
       n->OptionalHeader.SizeOfImage!=187576320u||n->FileHeader.TimeDateStamp!=141614920u)return 0;
    const unsigned char valid_bytes[]={0x44,0x8b,0x41,0x04,0x45,0x85,0xc0,0x74,0x46,0x8b,0x01,0x85,0xc0,0x78,0x40,0x3b};
    const unsigned char get_bytes[]={0x44,0x8b,0x49,0x04,0x45,0x85,0xc9,0x74,0x48,0x8b,0x01,0x85,0xc0,0x78,0x42,0x3b};
    if(!readable(b+0x1d16540,16)||!readable(b+0x1d133d0,16)||
       memcmp(b+0x1d16540,valid_bytes,16)||memcmp(b+0x1d133d0,get_bytes,16))return 0;
    *valid=(char(*)(const Weak*))(b+0x1d16540);*get=(void*(*)(const Weak*))(b+0x1d133d0);return 1;
}
__declspec(dllexport) int ClanEnemy_cleanup_probe(void *unused){
    (void)unused;unsigned long long nonce=0,g=0,gc=0,p=0,ec=0;
    FILE*f=local_file(L"enemy-cleanup-request.txt",L"r");if(!f){report(0,"Missing request",0,0);return 0;}
    int parsed=fscanf(f,"%llu %llx %llx %llx %llx",&nonce,&g,&gc,&p,&ec)==5;
    int c;while((c=fgetc(f))!=EOF)if(!isspace((unsigned char)c))parsed=0;fclose(f);
    if(!parsed||!nonce||!g||!gc||!p||!ec){report(nonce,"Invalid request",0,0);return 0;}
    DWORD thread=GetCurrentThreadId();if(game_thread&&game_thread!=thread){report(nonce,"Thread changed",0,0);return 0;}
    char(*valid)(const Weak*)=NULL;void*(*get)(const Weak*)=NULL;
    if(!build_functions(&valid,&get)){report(nonce,"Unsupported game build",0,0);return 0;}
    game_thread=thread;int total=0,live=0;
    const char *error=check_array((void*)(uintptr_t)g,(void*)(uintptr_t)gc,(void*)(uintptr_t)p,(void*)(uintptr_t)ec,valid,get,&total,&live);
    report(nonce,error,total,live);return 0;
}
BOOL WINAPI DllMain(HINSTANCE m,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=m;DisableThreadLibraryCalls(m);}return TRUE;}
