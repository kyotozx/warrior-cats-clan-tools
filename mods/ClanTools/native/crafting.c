/* Steam 24847281 / UE5.7.4. Narrow housing timer adapter.
 * Calls the original progress/completion method with a temporary duration.
 * Never writes timestamps, materials, inventory, save files or completion state.
 * All exports and callbacks must execute on the game thread. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
#define MAX_PROJECTS 256
typedef void (*Progress)(void*);
typedef unsigned char (*State)(void*);
typedef unsigned char (*Elapsed)(void*,float*,int32_t);
typedef struct {uintptr_t actor;int32_t id;uintptr_t level,world;int32_t level_id,world_id;} Project;
static HMODULE self;static unsigned char *base;static DWORD game_thread;
static Progress original;static State state;static Elapsed elapsed;static void **slots[2];static unsigned hook_flags;
static Project projects[MAX_PROJECTS];static int count,installed,inside,speed=1;
static uint64_t epoch;
static int readable(const void *p,size_t n,const void *allocation,int executable){
 uintptr_t cursor=(uintptr_t)p;if(!cursor||n>UINTPTR_MAX-cursor)return 0;uintptr_t end=cursor+n;
 while(cursor<end){MEMORY_BASIC_INFORMATION m;
  if(!VirtualQuery((void*)cursor,&m,sizeof(m))||m.State!=MEM_COMMIT||(allocation&&m.AllocationBase!=allocation)||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
  DWORD k=m.Protect&255;if(k!=PAGE_READONLY&&k!=PAGE_READWRITE&&k!=PAGE_WRITECOPY&&k!=PAGE_EXECUTE_READ&&k!=PAGE_EXECUTE_READWRITE&&k!=PAGE_EXECUTE_WRITECOPY)return 0;
  if(executable&&k!=PAGE_EXECUTE_READ&&k!=PAGE_EXECUTE_READWRITE&&k!=PAGE_EXECUTE_WRITECOPY)return 0;
  uintptr_t start=(uintptr_t)m.BaseAddress;if(m.RegionSize>UINTPTR_MAX-start||start+m.RegionSize<=cursor)return 0;cursor=start+m.RegionSize;
 }return 1;
}
static FILE *file(const wchar_t *name,const wchar_t *mode){wchar_t p[32768];DWORD n=GetModuleFileNameW(self,p,32768);if(!n||n>=32768)return NULL;wchar_t *s=wcsrchr(p,L'\\');if(!s)return NULL;s[1]=0;if(wcslen(p)+wcslen(name)>=32768)return NULL;wcscat(p,name);return _wfopen(p,mode);}
static void status(const char *s){FILE*f=file(L"crafting-status.txt",L"wb");if(f){fprintf(f,"%s\n",s);fclose(f);}}
static int build(void){
 base=(unsigned char*)GetModuleHandleW(NULL);if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
 IMAGE_DOS_HEADER*d=(IMAGE_DOS_HEADER*)base;if(d->e_magic!=IMAGE_DOS_SIGNATURE||d->e_lfanew<64||d->e_lfanew>0x100000)return 0;
 IMAGE_NT_HEADERS64*n=(IMAGE_NT_HEADERS64*)(base+d->e_lfanew);
 if(!readable(n,sizeof(*n),base,0)||n->Signature!=IMAGE_NT_SIGNATURE||n->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||n->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||n->OptionalHeader.SizeOfImage!=187576320u||n->FileHeader.TimeDateStamp!=141614920u)return 0;
 static const unsigned char tick[]={0x40,0x53,0x48,0x83,0xec,0x40,0x48,0x8b,0xd9,0xc7,0x44,0x24,0x50,0,0,0,0};
 static const unsigned char get[]={0x48,0x89,0x5c,0x24,0x10,0x57,0x48,0x83,0xec,0x50};
 static const unsigned char time[]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,0x55,0x57,0x41,0x56};
 if(!readable(base+0x17842e0,sizeof(tick),base,1)||memcmp(base+0x17842e0,tick,sizeof(tick))||!readable(base+0x1786290,sizeof(get),base,1)||memcmp(base+0x1786290,get,sizeof(get))||!readable(base+0x1811600,sizeof(time),base,1)||memcmp(base+0x1811600,time,sizeof(time)))return 0;
 slots[0]=(void**)(base+0x9b49b60+0x760);slots[1]=(void**)(base+0x9c4cb90+0x760);for(int i=0;i<2;i++)if(!readable(slots[i],8,base,0))return 0;
 original=(Progress)(base+0x17842e0);state=(State)(base+0x1786290);elapsed=(Elapsed)(base+0x1811600);return 1;
}
static int valid(uintptr_t a,int32_t *id){
 if(!readable((void*)a,0x3f8,NULL,0)||(*(uint32_t*)(a+8)&0x60018000u))return 0;
 uintptr_t vt=*(uintptr_t*)a;if(vt!=(uintptr_t)(base+0x9b49b60)&&vt!=(uintptr_t)(base+0x9c4cb90))return 0;
 int32_t v=*(int32_t*)(a+12),duration=*(int32_t*)(a+0x3a0);
 if(v<0||v>100000000||duration<0||duration>31536000||!*(uint64_t*)(a+0x2f0)||*(int32_t*)(a+0x3f0)!=-1)return 0;
 if(id)*id=v;return 1;
}
static void invalid_hotspot(uintptr_t a,int index){
 char message[512];if(!readable((void*)a,0x3f8,NULL,0)){snprintf(message,sizeof message,"ERROR hotspot[%d] actor unreadable",index);status(message);return;}
 uintptr_t level=*(uintptr_t*)(a+0x20),world=0;unsigned lf=0,wf=0;int lid=-1,wid=-1;
 if(readable((void*)level,0xc8,NULL,0)){lf=*(uint32_t*)(level+8);lid=*(int32_t*)(level+12);world=*(uintptr_t*)(level+0xc0);}
 if(readable((void*)world,0x30,NULL,0)){wf=*(uint32_t*)(world+8);wid=*(int32_t*)(world+12);}
 snprintf(message,sizeof message,"ERROR hotspot[%d] actor=%llx vtRva=%llx expected=9b49b60/9c4cb90 flags=%x id=%d duration=%d tag=%llx slot=%d level=%llx levelFlags=%x levelId=%d world=%llx worldFlags=%x worldId=%d",index,(unsigned long long)a,(unsigned long long)(*(uintptr_t*)a-(uintptr_t)base),*(uint32_t*)(a+8),*(int32_t*)(a+12),*(int32_t*)(a+0x3a0),(unsigned long long)*(uint64_t*)(a+0x2f0),*(int32_t*)(a+0x3f0),(unsigned long long)level,lf,lid,(unsigned long long)world,wf,wid);status(message);
}
static int level_world(uintptr_t actor,Project*p){
 uintptr_t level=*(uintptr_t*)(actor+0x20);
 if(!readable((void*)level,0xc8,NULL,0)||(*(uint32_t*)(level+8)&0x60018000u))return 0;
 uintptr_t world=*(uintptr_t*)(level+0xc0);
 if(!readable((void*)world,0x30,NULL,0)||(*(uint32_t*)(world+8)&0x60018000u))return 0;
 int32_t lid=*(int32_t*)(level+12),wid=*(int32_t*)(world+12);if(lid<0||wid<0)return 0;
 if(p){p->level=level;p->world=world;p->level_id=lid;p->world_id=wid;}return 1;
}
static int same(Project p){int32_t id;Project now={0};return valid(p.actor,&id)&&id==p.id&&level_world(p.actor,&now)&&now.level==p.level&&now.world==p.world&&now.level_id==p.level_id&&now.world_id==p.world_id;}
static int known(uintptr_t a){for(int i=0;i<count;i++)if(projects[i].actor==a&&same(projects[i]))return 1;return 0;}
static void run_progress(void *actor,int factor){
 uintptr_t a=(uintptr_t)actor;int32_t saved=*(int32_t*)(a+0x3a0);
 int32_t reduced=factor==0?0:(int32_t)(((int64_t)saved+factor-1)/factor);
 *(int32_t*)(a+0x3a0)=reduced;inside=1;original(actor);inside=0;
 /* Synchronous game-thread call; only restore our own temporary value. */
 if(readable((void*)a,0x3f8,NULL,0)&&*(int32_t*)(a+0x3a0)==reduced)*(int32_t*)(a+0x3a0)=saved;
}
static void observed(void *actor){
 if(!installed||inside||GetCurrentThreadId()!=game_thread||speed==1||!known((uintptr_t)actor)||state(actor)!=1){original(actor);return;}
 run_progress(actor,speed);
}
static int exchange(void **slot,void *expected,void *replacement){DWORD old;if(!VirtualProtect(slot,8,PAGE_READWRITE,&old))return 0;void *actual=InterlockedCompareExchangePointer((void*volatile*)slot,replacement,expected);DWORD ignored;int restored=VirtualProtect(slot,8,old,&ignored)!=0;if(actual!=expected)return 0;if(!restored){InterlockedCompareExchangePointer((void*volatile*)slot,expected,replacement);return 0;}return 1;}
static int restore_hooks(void){installed=0;for(unsigned i=0;i<2;i++)if(hook_flags&(1u<<i)){if(!exchange(slots[i],(void*)observed,(void*)original))return 0;hook_flags&=~(1u<<i);}count=0;speed=1;return 1;}
static int thread(void){if(!game_thread)game_thread=GetCurrentThreadId();return game_thread==GetCurrentThreadId()&&!inside;}
__declspec(dllexport) int Crafting_configure(void *unused){
 (void)unused;if(!thread()){status("ERROR wrong thread");return 0;}if(!build()){status("ERROR unsupported game build");return 0;}
 FILE*f=file(L"crafting-watch.txt",L"rb");if(!f){status("ERROR missing watch");return 0;}
 unsigned version;unsigned long long e;int factor,n;Project next[MAX_PROJECTS];
 if(fscanf(f,"%u %llu %d %d",&version,&e,&factor,&n)!=4||version!=1||!e||(factor!=0&&factor!=1&&factor!=2&&factor!=5&&factor!=10)||n<0||n>MAX_PROJECTS){fclose(f);status("ERROR invalid watch");return 0;}
 for(int i=0;i<n;i++){unsigned long long a=0;if(fscanf(f,"%llx",&a)!=1||!valid((uintptr_t)a,&next[i].id)||!level_world((uintptr_t)a,&next[i])){fclose(f);invalid_hotspot((uintptr_t)a,i);return 0;}next[i].actor=(uintptr_t)a;if(i&&next[i].world!=next[0].world){fclose(f);status("ERROR mixed active worlds");return 0;}for(int j=0;j<i;j++)if(next[j].actor==next[i].actor){fclose(f);status("ERROR duplicate hotspot");return 0;}}
 int extra;do{extra=fgetc(f);}while(extra==' '||extra=='\r'||extra=='\n'||extra=='\t');fclose(f);if(extra!=EOF){status("ERROR trailing watch data");return 0;}
 if(installed){if(hook_flags!=3||*slots[0]!=(void*)observed||*slots[1]!=(void*)observed){status("ERROR hook replaced");return 0;}}
 else {
  if(hook_flags){status("ERROR pending progress hook cleanup");return 0;}
  if(*slots[0]!=(void*)original||*slots[1]!=(void*)original){status("ERROR unexpected progress vtable");return 0;}
  HMODULE pinned;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)(uintptr_t)observed,&pinned)){status("ERROR cannot pin progress adapter");return 0;}
  for(unsigned i=0;i<2;i++){if(!exchange(slots[i],(void*)original,(void*)observed)){restore_hooks();status("ERROR cannot install progress adapter");return 0;}hook_flags|=1u<<i;}installed=1;
 }
 memcpy(projects,next,(size_t)n*sizeof(Project));count=n;speed=factor;epoch=e;status("CONFIGURED");return 0;
}
__declspec(dllexport) int Crafting_remove(void *unused){(void)unused;if(!thread()){status("ERROR wrong thread");return 0;}if(!restore_hooks()){status("ERROR cannot restore progress adapter");return 0;}status("REMOVED");return 0;}
__declspec(dllexport) int Crafting_scan(void *unused){
 (void)unused;if(!thread()||!installed){status("ERROR adapter unavailable");return 0;}
 FILE*f=file(L"crafting-projects.txt",L"wb");if(!f){status("ERROR cannot write projects");return 0;}
 fprintf(f,"CRAFTING 1 %llu\n",(unsigned long long)epoch);
 for(int i=0;i<count;i++){Project p=projects[i];if(!same(p))continue;unsigned s=state((void*)p.actor);float seconds=0;int measured=elapsed((void*)(p.actor+0x2f0),&seconds,*(int32_t*)(p.actor+0x3f0));if(!measured||!isfinite(seconds)||seconds<0)seconds=0;
  uint64_t tag=0;uintptr_t vt=*(uintptr_t*)p.actor;typedef uint64_t *(*Tag)(void*,uint64_t*);((Tag)*(uintptr_t*)(vt+0x798))((void*)p.actor,&tag);
  fprintf(f,"P %llx %u %d %.9g %u %u\n",(unsigned long long)p.actor,s,*(int32_t*)(p.actor+0x3a0),seconds,(unsigned)tag,(unsigned)(tag>>32));}
 fclose(f);status("SCANNED");return 0;
}
__declspec(dllexport) int Crafting_complete(void *unused){
 (void)unused;if(!thread()||!installed){status("ERROR adapter unavailable");return 0;}
 FILE*f=file(L"crafting-complete.txt",L"rb");unsigned long long e,a;int parsed=f?fscanf(f,"%llu %llx",&e,&a):0;if(f)fclose(f);
 if(parsed!=2||e!=epoch||!known((uintptr_t)a)){status("ERROR stale project");return 0;}
 if(state((void*)(uintptr_t)a)!=1){status("ERROR project is not building");return 0;}
 run_progress((void*)(uintptr_t)a,0);
 if(!known((uintptr_t)a)||state((void*)(uintptr_t)a)!=3){status("ERROR completion not observed");return 0;}
 status("COMPLETED");return 0;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=module;DisableThreadLibraryCalls(module);}return TRUE;}
