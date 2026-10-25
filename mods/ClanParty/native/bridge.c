/* Build-specific bridge for Wrc Steam build 24847281. Called on the game thread
 * from UE4SS Lua, through package.loadlib. No Lua ABI or engine SDK dependency.
 * This uses the game's party reader/copy/writer; it never edits save files. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <ctype.h>

typedef struct { uint8_t role, pad[3]; uint32_t name, number; } Cat;
typedef struct { Cat *data; int32_t count, capacity; } Party;
_Static_assert(sizeof(Cat)==12, "Unexpected cat ABI");
_Static_assert(sizeof(Party)==16, "Unexpected array ABI");
static HMODULE self;
static unsigned char *base;
static void (*read_party)(Party*);
static Party* (*copy_party)(Party*,const Party*);
static void (*write_party)(Party*);
static void (*free_party)(void*);

/* Check mappings before reading build-specific offsets, including PE headers.
 * The game thread owns the native state; these checks do not make off-thread
 * native calls safe. allocation==NULL permits ordinary heap allocations. */
static int readable(const void *address, size_t size, const void *allocation, int executable) {
    uintptr_t cursor=(uintptr_t)address;
    if(!cursor || size>UINTPTR_MAX-cursor) return 0;
    uintptr_t end=cursor+size;
    while(cursor<end) {
        MEMORY_BASIC_INFORMATION mbi;
        if(!VirtualQuery((void*)cursor,&mbi,sizeof(mbi)) || mbi.State!=MEM_COMMIT ||
           (allocation && mbi.AllocationBase!=allocation) ||
           (mbi.Protect&(PAGE_GUARD|PAGE_NOACCESS))) return 0;
        DWORD protection=mbi.Protect&0xff;
        if(protection!=PAGE_READONLY && protection!=PAGE_READWRITE &&
           protection!=PAGE_WRITECOPY && protection!=PAGE_EXECUTE_READ &&
           protection!=PAGE_EXECUTE_READWRITE && protection!=PAGE_EXECUTE_WRITECOPY) return 0;
        if(executable && protection!=PAGE_EXECUTE_READ &&
           protection!=PAGE_EXECUTE_READWRITE && protection!=PAGE_EXECUTE_WRITECOPY) return 0;
        uintptr_t region=(uintptr_t)mbi.BaseAddress;
        if(mbi.RegionSize>UINTPTR_MAX-region || region+mbi.RegionSize<=cursor) return 0;
        cursor=region+mbi.RegionSize;
    }
    return 1;
}
static int module_path(wchar_t *path,DWORD capacity) {
    DWORD length=GetModuleFileNameW(self,path,capacity);
    return length && length<capacity;
}
static FILE *open_local(const wchar_t *name,const wchar_t *mode) {
    wchar_t path[32768];
    if(!module_path(path,32768)) return NULL;
    wchar_t *slash=wcsrchr(path,L'\\'); if(!slash) return NULL;
    slash[1]=0; if(wcslen(path)+wcslen(name)>=32768) return NULL;
    wcscat(path,name); return _wfopen(path,mode);
}
static void status(const char *message) {
    FILE *f=open_local(L"bridge-status.txt",L"w");
    if(f){fprintf(f,"%s\n",message);fclose(f);}
}
static int initialize(void) {
    base=(unsigned char*)GetModuleHandleW(NULL);
    const uint32_t offsets[]={0x16a6480,0x16b1360,0x16a6950,0x19db970};
    const unsigned char expected[4][16]={
      {0x40,0x55,0x53,0x57,0x41,0x54,0x41,0x56,0x48,0x8d,0x6c,0x24,0xf0,0x48,0x81,0xec},
      {0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x57,0x48,0x83,0xec,0x40,0x48},
      {0x48,0x89,0x4c,0x24,0x08,0x55,0x41,0x56,0x41,0x57,0x48,0x8d,0x6c,0x24,0x80,0x48},
      {0x48,0x85,0xc9,0x74,0x2e,0x53,0x48,0x83,0xec,0x20,0x48,0x8b,0xd9,0x48,0x8b,0x0d}};
    if(!base || !readable(base,sizeof(IMAGE_DOS_HEADER),base,0)) goto unsupported;
    const IMAGE_DOS_HEADER *dos=(const IMAGE_DOS_HEADER*)base;
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE || dos->e_lfanew<(LONG)sizeof(*dos) ||
       dos->e_lfanew>0x100000) goto unsupported;
    const IMAGE_NT_HEADERS64 *nt=(const IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
    if(!readable(nt,sizeof(*nt),base,0) || nt->Signature!=IMAGE_NT_SIGNATURE ||
       nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64 ||
       nt->FileHeader.SizeOfOptionalHeader<sizeof(IMAGE_OPTIONAL_HEADER64) ||
       nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC) goto unsupported;
    const uint32_t image_size=nt->OptionalHeader.SizeOfImage;
    /* Exact build header plus code guards: reject before dereferencing any RVA. */
    if(image_size!=187576320u || nt->FileHeader.TimeDateStamp!=141614920u ||
       image_size<0xa8a6e30u+sizeof(void*)) goto unsupported;
    for(int i=0;i<4;i++) if(offsets[i]>image_size-16 ||
       !readable(base+offsets[i],16,base,1) || memcmp(base+offsets[i],expected[i],16)) goto unsupported;
    if(!readable(base+0xa8a6e30,sizeof(void*),base,0)) goto unsupported;
    if(!*(void**)(base+0xa8a6e30)){status("WAIT save manager unavailable");return 0;}
    if(!readable(*(void**)(base+0xa8a6e30),0x28,NULL,0)) goto unsupported;
    read_party=(void(*)(Party*))(base+offsets[0]);
    copy_party=(Party*(*)(Party*,const Party*))(base+offsets[1]);
    write_party=(void(*)(Party*))(base+offsets[2]);
    free_party=(void(*)(void*))(base+offsets[3]);return 1;
unsupported:
        status("ERROR unsupported game build; native calls disabled");return 0;
}
static int snapshot(void) {
    Party p={0};read_party(&p);
    if(p.count<0 || p.count>32 || p.capacity<p.count ||
       (p.count && !readable(p.data,(size_t)p.count*sizeof(Cat),NULL,0))){
        status("ERROR unexpected party array");return 0;
    }
    FILE *f=open_local(L"snapshot.txt",L"w");
    int written=0;
    if(f){fprintf(f,"%d\n",p.count);for(int i=0;i<p.count;i++)
        fprintf(f,"%u %u %u\n",p.data[i].role,p.data[i].name,p.data[i].number);
        written=!ferror(f);if(fclose(f)!=0)written=0;}
    if(p.data)free_party(p.data);
    if(!written)status("ERROR could not write party snapshot");
    return written;
}
__declspec(dllexport) int ClanParty_read(void *unused) {
    (void)unused;if(initialize() && snapshot())status("READ OK");return 0;
}
__declspec(dllexport) int ClanParty_apply(void *unused) {
    (void)unused;if(!initialize())return 0;
    FILE *f=open_local(L"request.txt",L"r");if(!f){status("ERROR missing request");return 0;}
    int n=-1;Cat cats[2]={0};int valid=fscanf(f,"%d",&n)==1 && n>=0 && n<=2;
    for(int i=0;valid && i<n;i++){
        unsigned long long role,name,number;
        valid=fscanf(f,"%llu %llu %llu",&role,&name,&number)==3 && role>0 && role<105 &&
              name>0 && name<=UINT32_MAX && number==0;
        if(valid){cats[i].role=(uint8_t)role;cats[i].name=(uint32_t)name;cats[i].number=0;}
    }
    if(n==2 && cats[0].role==cats[1].role)valid=0;
    int trailing;while((trailing=fgetc(f))!=EOF) if(!isspace((unsigned char)trailing)) valid=0;
    fclose(f);if(!valid){status("ERROR invalid request");return 0;}
    Party source={cats,n,n},owned={0};
    copy_party(&owned,&source);
    if(owned.count!=n || owned.capacity<n || (n && !owned.data)){
        status("ERROR engine party allocation failed");return 0;
    }
    write_party(&owned); /* writer consumes the engine-owned allocation */
    if(snapshot())status("APPLIED OK");return 0;
}
__declspec(dllexport) int ClanParty_manager(void *unused) {
    (void)unused;
    wchar_t executable[32768];
    if(!module_path(executable,32768)) return 0;
    wchar_t *slash=wcsrchr(executable,L'\\');if(!slash)return 0;*slash=0;
    slash=wcsrchr(executable,L'\\');if(!slash)return 0;slash[1]=0;
    const wchar_t suffix[]=L"ClanParty.exe";
    if(wcslen(executable)+wcslen(suffix)>=32768)return 0;
    wcscat(executable,suffix);
    HINSTANCE result=ShellExecuteW(NULL,L"open",executable,NULL,NULL,SW_SHOWNORMAL);
    status((INT_PTR)result>32?"MANAGER OPENED":"ERROR could not open party manager");
    return 0;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved){
    (void)reserved;if(reason==DLL_PROCESS_ATTACH){self=module;DisableThreadLibraryCalls(module);}return TRUE;
}
