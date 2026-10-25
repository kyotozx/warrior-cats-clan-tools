/* Exact-build offline XP and stamina bridge. Invoked synchronously on game thread. */
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
#include "admin_sandbox_guards.h"
static int build_ok(void) {
 base=(unsigned char*)GetModuleHandleW(NULL);
 if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
 IMAGE_DOS_HEADER*d=(void*)base;
 if(d->e_magic!=IMAGE_DOS_SIGNATURE||d->e_lfanew<64||d->e_lfanew>0x100000)return 0;
 IMAGE_NT_HEADERS64*n=(void*)(base+d->e_lfanew);
 if(!readable(n,sizeof(*n),base,0)||n->Signature!=IMAGE_NT_SIGNATURE||n->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||n->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||n->OptionalHeader.SizeOfImage!=187576320u||n->FileHeader.TimeDateStamp!=141614920u)return 0;
 for(unsigned i=0;i<sizeof(sandbox_guards)/sizeof(sandbox_guards[0]);i++)if(!readable(base+sandbox_guards[i].rva,16,base,1)||memcmp(base+sandbox_guards[i].rva,sandbox_guards[i].code,16))return 0;
 return 1;
}
static int resource_ok(unsigned char*c,uintptr_t owner,uintptr_t cls,uintptr_t table,size_t size) {
 return readable(c,size,NULL,0)&&readable((void*)owner,0x28,NULL,0)&&readable((void*)cls,0x40,NULL,0)&&*(uintptr_t*)(c+0x10)==cls&&*(uintptr_t*)(c+0x20)==owner&&*(void**)c==base+table&&c[0x104]<=1;
}
static int bounds(float current,float maximum) {
 return isfinite(current)&&isfinite(maximum)&&maximum>0&&maximum<=10000000&&current>=0&&current<=maximum+.01f;
}
typedef struct { uint64_t*data;int count,capacity; } TagArray;
typedef struct { TagArray tags,parents; } TagContainer;
typedef struct { wchar_t*data;int count,capacity; } Str;
static int save_stats(unsigned char*c) {
 if(!readable(base+0xa8ba6e8,8,base,0))return 0;
 void*script=*(void**)(base+0xa8ba6e8);if(!readable(script,0x40,NULL,0))return 0;
 Str out={0},key={L"Stats",6,6};
 ((void(*)(void*,Str*,const void*,const void*,void*,int,void*,int))(base+0x1beb200))(script,&out,c+0x138,NULL,NULL,0x20805,NULL,1);
 int ok=out.count>1&&out.count<=8192&&out.capacity>=out.count&&readable(out.data,(size_t)out.count*2,NULL,0)&&out.data[out.count-1]==0;
 if(ok)((void(*)(const Str*,const Str*))(base+0x16af790))(&out,&key);
 if(out.data)((void(*)(void*))(base+0x19db970))(out.data);
 if(!ok)return 0;
 union {uint64_t align;unsigned char b[0x38];} reread={0};
 ((void*(*)(void*))(base+0x180f450))(&reread);
 ok=memcmp(reread.b+0x1c,c+0x154,24)==0;
 Str*type=(Str*)(reread.b+8);if(type->data)((void(*)(void*))(base+0x19db970))(type->data);
 return ok;
}
static int move_list(uint64_t*out,int*count) {
 TagContainer list={0};int ok=1;
 ((void*(*)(void*))(base+0x16a3930))(&list);
 if(list.tags.count<0||list.tags.count>512||list.tags.capacity<list.tags.count||list.tags.capacity>4096||list.parents.count<0||list.parents.count>512||list.parents.capacity<list.parents.count||list.parents.capacity>4096)ok=0;
 if(ok&&list.tags.count&&!readable(list.tags.data,(size_t)list.tags.count*8,NULL,0))ok=0;
 if(ok){*count=list.tags.count;if(*count)memcpy(out,list.tags.data,(size_t)*count*8);}
 if(list.tags.data)((void(*)(void*))(base+0x19db970))(list.tags.data);
 if(list.parents.data)((void(*)(void*))(base+0x19db970))(list.parents.data);
 return ok;
}
static int run(void) {
 unsigned long long nonce=0,cptr=0,owner=0,cls=0,manager=0;
 char command[24]={0};double expected=0,amount=0;int expected_level=0;unsigned tag_index=0;
 uint64_t moves[512]={0};int move_count=0;
 const char*status="Invalid request";float current=0,maximum=0,after=0;int level=0,max_level=0,after_level=0;float stats[6]={0};
 FILE*f=local_file(L"admin-sandbox-request.txt",L"r");if(!f)goto done;
 int fields=fscanf(f,"%llu %23s %llx %llx %llx %llx %lf %d %lf %u",&nonce,command,&cptr,&owner,&cls,&manager,&expected,&expected_level,&amount,&tag_index);
 int extra=fgetc(f);while(extra==' '||extra=='\r'||extra=='\n'||extra=='\t')extra=fgetc(f);fclose(f);
 int xp=!strcmp(command,"XP_PROBE")||!strcmp(command,"XP_ADD");
 int stamina=!strcmp(command,"STAMINA_PROBE")||!strcmp(command,"STAMINA_FILL");
 int attack=!strcmp(command,"MOVES_PROBE")||!strcmp(command,"MOVE_UNLOCK");
 int stats_set=!strcmp(command,"STAT_SET"),health=!strcmp(command,"HEALTH_PROBE")||!strcmp(command,"HEALTH_MAX");
 int apply=!strcmp(command,"XP_ADD")||!strcmp(command,"STAMINA_FILL")||!strcmp(command,"MOVE_UNLOCK")||stats_set||!strcmp(command,"HEALTH_MAX");
 if(fields!=10||extra!=EOF||!nonce||(!xp&&!stamina&&!attack&&!stats_set&&!health)||!isfinite(expected)||!isfinite(amount)||expected<0||amount<0||amount>100000||tag_index>0x7fffffffU)goto done;
 if(stats_set&&(tag_index>5||amount<1||amount>10000||floor(amount)!=amount))goto done;
 if(health&&apply&&(amount<1||amount>10000||floor(amount)!=amount))goto done;
 if(attack&&apply&&!tag_index)goto done;
 if(apply&&xp&&(amount<1||floor(amount)!=amount))goto done;
 if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId()){status="Wrong thread";goto done;}
 if(!build_ok()){status="Unsupported game build";goto done;}
 unsigned char*c=(void*)(uintptr_t)cptr;
 if(xp||attack||stats_set) {
  if(!resource_ok(c,(uintptr_t)owner,(uintptr_t)cls,0x9b5a6c0,0x170)||!readable((void*)(uintptr_t)owner,0x398,NULL,0)||*(void**)((uintptr_t)owner+0x390)!=c){status="Level component owner or class mismatch";goto done;}
  if(!readable(base+0xa8a6e30,8,base,0)||*(uintptr_t*)(base+0xa8a6e30)!=(uintptr_t)manager||!readable((void*)(uintptr_t)manager,0x248,NULL,0)||*(void**)(void*)(uintptr_t)manager!=base+0x9c5a7f0){status="Save manager changed";goto done;}
  if(*(void**)(base+0x9b5a6c0+0x508)!=base+0x165b460||*(void**)(base+0x9b5a6c0+0x510)!=base+0x16588a0){status="Level handler changed";goto done;}
  level=*(int*)(c+0x120);max_level=*(int*)(c+0x124);
  if(level<1||level>max_level||max_level>1000){status="Invalid level bounds";goto done;}
 }else if(health){
  if(!readable(c,0x128,NULL,0)||!readable((void*)(uintptr_t)owner,0x28,NULL,0)||!readable((void*)(uintptr_t)cls,0x40,NULL,0)||*(uintptr_t*)(c+0x10)!=(uintptr_t)cls||*(uintptr_t*)(c+0x20)!=(uintptr_t)owner||c[0x104]>1){status="Invalid health component owner";goto done;}
  void**vt=*(void***)c;
  if(!readable(vt,0x518,base,0)||*(void**)((char*)vt+0x4f0)!=base+0x16554c0||*(void**)((char*)vt+0x510)!=base+0x1655300){status="Invalid health resource handlers";goto done;}
  if(c[0x104]){status="Temporary health maximum override active";goto done;}
 }else{
  uintptr_t table=readable(c,8,NULL,0)?(uintptr_t)*(void**)c-(uintptr_t)base:0;
  if((table!=0x9acb558&&table!=0x9b90318)||!resource_ok(c,(uintptr_t)owner,(uintptr_t)cls,table,0x120)||*(void**)(base+table+0x510)!=base+0x165b580){status="Stamina component owner or class mismatch";goto done;}
 }
 current=*(float*)(c+0x10c);maximum=*(float*)(c+(c[0x104]?0x100:0x110));
 if(!bounds(current,maximum)){status="Invalid resource bounds";goto done;}
 if(stats_set){
  float*value=(float*)(c+0x154+tag_index*4),before=*value;
  if(level!=expected_level||!isfinite(before)||fabs(before-expected)>.01){status="Stat preview is stale";goto done;}
  for(int i=0;i<6;i++){float v=*(float*)(c+0x154+i*4);if(!isfinite(v)||v<1||v>100000){status="Invalid player stats";goto done;}}
  *value=(float)amount;
  if(!save_stats(c)){*value=before;int restored=save_stats(c);status=restored?"Stat readback failed; original restored":"Stat save/readback failed; backup required";goto done;}
  for(int i=0;i<6;i++)stats[i]=*(float*)(c+0x154+i*4);
  after=current;after_level=level;status="APPLIED";goto done;
 }
 if(attack){
  if(!move_list(moves,&move_count)){status="Invalid unlocked move list";goto done;}
  if(apply){
   uint64_t tag=0,name=(uint64_t)tag_index;
   ((void*(*)(void*,const void*,int))(base+0x3cd9110))(&tag,&name,0);
   if(tag!=name){status="Unknown gameplay move tag";goto done;}
   for(int i=0;i<move_count;i++)if(moves[i]==tag){status="Move already unlocked";goto done;}
   ((void(*)(const void*,int))(base+0x16a3470))(&tag,0);
   if(!move_list(moves,&move_count)){status="Move readback unavailable";goto done;}
   int found=0;for(int i=0;i<move_count;i++)if(moves[i]==tag)found=1;
   if(!found){status="Move unlock readback mismatch";goto done;}
  }
  after=current;after_level=level;status=apply?"APPLIED":"READY";goto done;
 }
 if(apply){
  if(fabs((health?maximum:current)-expected)>.01||(xp&&level!=expected_level)){status="Preview is stale";goto done;}
  if(xp){
   float scale=*(float*)(c+0x114),offset=*(float*)(c+0x118);
   if(!isfinite(scale)||scale<=0||scale>100||!isfinite(offset)||fabsf(offset)>10000){status="Invalid experience modifiers";goto done;}
   if(level>=max_level){status="Maximum level reached";goto done;}
   /* Same virtual add-resource path as the game's GainXP item effect. It
      dispatches native level-up, stat updates, HUD events and serialization. */
   ((void(*)(void*,float))(base+0x165b460))(c,(float)amount);
  }else if(health){
   ((void(*)(void*,float))(base+0x16554c0))(c,(float)amount);
   ((void(*)(void*,float))(base+0x1655300))(c,current);
  }else ((void(*)(void*,float))(base+0x165b580))(c,maximum);
 }
 after=*(float*)(c+0x10c);maximum=*(float*)(c+(c[0x104]?0x100:0x110));after_level=xp?*(int*)(c+0x120):0;
 if(!bounds(after,maximum)||(xp&&(after_level<level||after_level>max_level))){status="Resource readback mismatch";goto done;}
 if(apply&&stamina&&fabsf(after-maximum)>.01f){status="Stamina readback mismatch";goto done;}
 if(apply&&health&&fabs(maximum-amount)>.01){status="Health maximum readback mismatch";goto done;}
 if(xp)for(int i=0;i<6;i++){stats[i]=*(float*)(c+0x154+i*4);if(!isfinite(stats[i])){status="Invalid player stats";goto done;}}
 status=apply?"APPLIED":"READY";
done:
 f=local_file(L"admin-sandbox-status.txt",L"w");if(f){fprintf(f,"nonce=%llu\nstatus=%s\ncurrent=%.9g\nmaximum=%.9g\nafter=%.9g\nlevel=%d\nmax_level=%d\nafter_level=%d\n",nonce,status,current,maximum,after,level,max_level,after_level);for(int i=0;i<6;i++)fprintf(f,"stat%d=%.9g\n",i,stats[i]);for(int i=0;i<move_count;i++)fprintf(f,"move=%u %u\n",(unsigned)moves[i],(unsigned)(moves[i]>>32));fclose(f);}return 0;
}
__declspec(dllexport) int ClanSandbox_run(void*lua){(void)lua;return run();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
