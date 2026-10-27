/* Build-specific existing keyboard-setting API. No hooks or save-file writes.
 * Lua calls these exports only on game thread; Lua owns game Save() and rollback. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <ctype.h>
#include "player_settings_layout.h"
typedef struct{wchar_t *p;int32_t n,cap;} Str;
typedef struct{unsigned char *p;int32_t n,cap;} Array;
static HMODULE self;static unsigned char *base;static DWORD thread_id;
static int readable(const void*p,size_t n){MEMORY_BASIC_INFORMATION m;uintptr_t a=(uintptr_t)p,end=a+n;if(!a||end<a)return 0;while(a<end){if(!VirtualQuery((void*)a,&m,sizeof(m))||m.State!=MEM_COMMIT||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;uintptr_t next=(uintptr_t)m.BaseAddress+m.RegionSize;if(next<=a)return 0;a=next;}return 1;}
static FILE* local_file(const wchar_t*name,const wchar_t*mode){wchar_t path[32768];DWORD n=GetModuleFileNameW(self,path,32768);if(!n||n>=32768)return NULL;wchar_t*s=wcsrchr(path,L'\\');if(!s)return NULL;s[1]=0;if(wcslen(path)+wcslen(name)>=32768)return NULL;wcscat(path,name);return _wfopen(path,mode);}
static void error(unsigned id,const char*message){FILE*f=local_file(L"settings-response.txt",L"wb");if(f){fprintf(f,"%u ERROR %s\n",id,message);fclose(f);}}
static int init(void){
 if(base)return 1;unsigned char*b=(unsigned char*)GetModuleHandleW(NULL);if(!readable(b,4096))return 0;
 IMAGE_DOS_HEADER*d=(void*)b;if(d->e_magic!=IMAGE_DOS_SIGNATURE||d->e_lfanew<64||d->e_lfanew>0x100000)return 0;
 IMAGE_NT_HEADERS64*n=(void*)(b+d->e_lfanew);if(!readable(n,sizeof(*n))||n->Signature!=IMAGE_NT_SIGNATURE||n->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||n->OptionalHeader.SizeOfImage!=187576320u||n->FileHeader.TimeDateStamp!=3539680621u)return 0;
 /* Verify exact native vtable implementation addresses before any call. */
 if(*(uintptr_t*)(b+0x9c5a928+0x5f0)!=(uintptr_t)(b+0x1948340)||*(uintptr_t*)(b+0x9c5a928+0x5e8)!=(uintptr_t)(b+0x1948210)||*(uintptr_t*)(b+0x9c43f40+0x370)!=(uintptr_t)(b+0x1929560)||*(uintptr_t*)(b+0x9c43f40+0x338)!=(uintptr_t)(b+0x1929410))return 0;
 /* The remapper owns input350; these direct settings APIs do not use its slot.
  * Requiring the original here would break VSync when saved remaps load first. */
 if(*(uintptr_t*)(b+0x9c5a928+0x5b8)!=(uintptr_t)(b+0x19455e0)||*(uintptr_t*)(b+0x9c5a928+0x5c0)!=(uintptr_t)(b+0x1946510))return 0;
 if(*(uintptr_t*)(b+0x9c5a928+0x598)!=(uintptr_t)(b+0x180f130)||*(uintptr_t*)(b+0x9c5a928+0x5b0)!=(uintptr_t)(b+0x180f730))return 0;
 const unsigned char getter[]={0x48,0x89,0x5c,0x24,0x08,0x57,0x48,0x83,0xec,0x50};if(memcmp(b+0x1948340,getter,sizeof getter)||memcmp(b+0x1948210,getter,sizeof getter))return 0;
 base=b;return 1;
}
static int obj(void*p,uintptr_t vt,size_t size){return readable(p,size)&&*(uintptr_t*)p==(uintptr_t)(base+vt)&&!(*(uint32_t*)((char*)p+8)&0x60018000u);}
static int editable(unsigned c){return c==65||c==70||c==71||c==72||c==74||c==75||c==76||c==77||c==78;}
static void release(Str*s){if(s->p)((void(*)(void*))(base+0x19dd120))(s->p);memset(s,0,sizeof(*s));}
static int str_ok(const Str*s){return s->n>=0&&s->n<=512&&s->cap>=s->n&&(!s->n||(readable(s->p,s->n*2)&&s->p[s->n-1]==0));}
static Str command_name(unsigned c){Str result={0};uint8_t command=(uint8_t)c;((void*(*)(Str*,const uint8_t*))(base+0x126c420))(&result,&command);return result;}
static Str get(void*manager,const Str*key){Str out={0};((void*(*)(void*,Str*,const Str*))(base+0x1948340))(manager,&out,key);return out;}
static void set(void*manager,const Str*key,const Str*value){((void(*)(void*,const Str*,const Str*))(base+0x1948210))(manager,key,value);}
static void rebuild(void*input){((void(*)(void*,uint8_t))(base+0x1929410))(input,1);}
static int mode(void*manager,int requested){
 PlayerSettings player={0};
 ((void*(*)(void*,void*,int32_t))(base+0x19455e0))(manager,&player,0);
 if(!player_settings_valid(&player))return -1;
 int old=player.flags[0];
 if(requested>=0){
  if(requested>1)return -1;
  player.flags[0]=(unsigned char)requested;
  ((void(*)(void*,int32_t,const void*))(base+0x1946510))(manager,0,&player);
  PlayerSettings after={0};
  ((void*(*)(void*,void*,int32_t))(base+0x19455e0))(manager,&after,0);
  if(!player_settings_valid(&after)||!player_settings_equal(&after,&player))return -1;
  return requested;
 }
 return old;
}
static void dispose(Array*a){if(a->p){for(int i=0;i<a->n;i++){unsigned char*p=a->p+i*0x58;((void(*)(void*))(base+0x119de70))(*(void**)(p+0x28));((void(*)(void*))(base+0x119de70))(*(void**)(p+0x50));}((void(*)(void*))(base+0x19dd120))(a->p);}memset(a,0,sizeof(*a));}
static int ascii(const Str*s,char*out,size_t size){if(!str_ok(s)||(size_t)s->n>=size)return 0;int n=s->n?s->n-1:0;for(int i=0;i<n;i++){if(s->p[i]<33||s->p[i]>126)return 0;out[i]=(char)s->p[i];}out[n]=0;return 1;}
__declspec(dllexport) int Settings_command(void*unused){
 (void)unused;unsigned id=0;char action[16],value[512];unsigned long long manager_address,input_address,pc_address;unsigned command=0;
 FILE*f=local_file(L"settings-request.txt",L"rb");if(!f){error(0,"missing request");return 0;}
 int parsed=fscanf(f,"%u %15s %llx %llx %llx %u %511s",&id,action,&manager_address,&input_address,&pc_address,&command,value);fclose(f);
 if(parsed<5||!id){error(id,"invalid request");return 0;}if(!thread_id)thread_id=GetCurrentThreadId();if(thread_id!=GetCurrentThreadId()||!init()){error(id,"unsupported build or thread");return 0;}
 void*manager=(void*)(uintptr_t)manager_address;void*input=(void*)(uintptr_t)input_address;
 if(!obj(manager,0x9c5a928,0x248)||!obj(input,0x9c43f40,0x4a0)||*(void**)(base+0xa8a6e30)!=manager||*(uintptr_t*)((char*)input+0x20)!=(uintptr_t)pc_address){error(id,"stale input context");return 0;}
 if(!strcmp(action,"VSYNC")){if(parsed<6||command>2){error(id,"invalid VSync request");return 0;}if(command<2)((void(*)(void*,uint8_t,uint8_t,uint8_t))(base+0x180f130))(manager,2,12,(uint8_t)command);uint8_t value=((uint8_t(*)(void*,uint8_t,uint8_t,uint8_t))(base+0x180f730))(manager,2,12,0);if(value>1||(command<2&&value!=command)){error(id,"shared VSync readback failed");return 0;}f=local_file(L"settings-response.txt",L"wb");if(f){fprintf(f,"%u OK\nV %u\n",id,value);fclose(f);}return 0;}
 if(!strcmp(action,"MODE")){if(parsed<6||command>1||mode(manager,(int)command)<0){error(id,"invalid custom controls mode");return 0;}rebuild(input);f=local_file(L"settings-response.txt",L"wb");if(f){fprintf(f,"%u OK\n",id);fclose(f);}return 0;}
 if(!strcmp(action,"LIST")){
  int custom=mode(manager,-1);if(custom<0){error(id,"unsupported player settings");return 0;}
  Array bindings={0};((void*(*)(void*,Array*))(base+0x128a6d0))(input,&bindings);
  if(bindings.n<0||bindings.n>256||bindings.cap<bindings.n||!readable(bindings.p,(size_t)bindings.n*0x58)){error(id,"unsupported keyboard map");return 0;}
  f=local_file(L"settings-response.txt",L"wb");if(!f){dispose(&bindings);return 0;}fprintf(f,"%u OK\nM %d\n",id,custom);
  for(int i=0;i<bindings.n;i++){unsigned char*p=bindings.p+i*0x58;unsigned type=p[0],c=p[1];uint64_t key=0;float scale=1;char stored[512]="";
   if(type>1)continue;memcpy(&key,p+(type?0x40:0x18),8);if(type)memcpy(&scale,p+0x38,4);
   if(editable(c)){Str name=command_name(c);Str old=get(manager,&name);int safe=ascii(&old,stored,sizeof stored);release(&old);release(&name);if(!safe){fclose(f);dispose(&bindings);error(id,"unsupported saved binding text");return 0;}}
   fprintf(f,"B %u %u %u %u %.9g %d %s\n",c,type,(unsigned)key,(unsigned)(key>>32),scale,editable(c),*stored?stored:"-");
  }fclose(f);dispose(&bindings);return 0;
 }
 if((strcmp(action,"SET")&&strcmp(action,"RAW"))||parsed!=7||!editable(command)){error(id,"unsupported binding request");return 0;}
 Str name=command_name(command);if(!str_ok(&name)){error(id,"command enum unavailable");return 0;}
 wchar_t text[512];int count=0;
 if(!strcmp(action,"SET")){
  for(size_t i=0;value[i];i++)if(!isalnum((unsigned char)value[i])&&value[i]!='_'){release(&name);error(id,"invalid key token");return 0;}
  if(strlen(value)>80){release(&name);error(id,"key too long");return 0;}
  wchar_t key[81];for(size_t i=0;i<=strlen(value);i++)key[i]=(wchar_t)value[i];count=swprintf(text,512,L"0,%ls,%ls",name.n?name.p:L"",key);
 }else if(!strcmp(value,"-")){text[0]=0;count=0;}
 else {count=(int)strlen(value);for(int i=0;i<=count;i++)text[i]=(wchar_t)value[i];}
 if(count<0||count>=511){release(&name);error(id,"binding text overflow");return 0;}
 Str desired={text,count+1,count+1};set(manager,&name,&desired);Str after=get(manager,&name);
 int matches=str_ok(&after)&&(count==0?(after.n<=1):(after.n==desired.n&&!memcmp(after.p,text,(size_t)desired.n*2)));release(&after);release(&name);
 if(!matches){error(id,"binding readback mismatch");return 0;}
 if(!strcmp(action,"SET")&&mode(manager,1)<0){error(id,"cannot enable custom controls");return 0;}rebuild(input);
 f=local_file(L"settings-response.txt",L"wb");if(f){fprintf(f,"%u OK\n",id);fclose(f);}return 0;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=module;DisableThreadLibraryCalls(module);}return TRUE;}
