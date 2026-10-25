/* Observation-only inventory callback for inspected Steam build 24847281.
 * Replaces the inventory-use entry plus queue/resolve entries in both verified
 * combat component vtables. Every wrapper calls its original exactly once.
 * Records actual count/resource deltas. Never edits gameplay/save values.
 * Install, update, drain and remove must run on UE's game thread.
 * Mailboxes are relative to this DLL. No Lua ABI dependency is required. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <math.h>
#include <inttypes.h>

#define MAX_TARGETS 4
#define QUEUE_SIZE 64
typedef struct { float current, maximum; int valid; } Resource;
typedef struct { uintptr_t actor, health, stamina; int32_t actor_id, health_id, stamina_id; } Target;
typedef struct { uintptr_t actor; Resource hp0,hp1,sp0,sp1; } Delta;
typedef struct {
 uint64_t epoch, sequence, tag; int before,after,requested,count; Delta targets[MAX_TARGETS];
} Event;
typedef uint64_t (*UseItem)(void*,uint64_t,uint8_t,int32_t);
typedef void (*QueueItem)(void*,const uint64_t*);
typedef void (*ResolveItem)(void*);
typedef struct {uintptr_t component;int32_t id;uint64_t tag;int consumed;} Receipt;
static Receipt receipts[MAX_TARGETS];
static QueueItem original_queue;
static ResolveItem original_resolve;
static void **combat_slots[4];
static unsigned combat_mask;
static HMODULE self;
static unsigned char *base;
static UseItem original;
static void **patch_slot;
static DWORD game_thread;
static uintptr_t inventory;
static int32_t inventory_id;
static Target targets[MAX_TARGETS];
static int target_count, installed, inside;
static uint64_t epoch, sequence;
static Event queue[QUEUE_SIZE];
static unsigned head,tail,dropped;
static const char *watch_error="ERROR invalid watch syntax";

static int readable(const void *p,size_t n,const void *allocation,int executable) {
 uintptr_t cursor=(uintptr_t)p;if(!cursor||n>UINTPTR_MAX-cursor)return 0;
 uintptr_t end=cursor+n;
 while(cursor<end){MEMORY_BASIC_INFORMATION m;
  if(!VirtualQuery((void*)cursor,&m,sizeof(m))||m.State!=MEM_COMMIT||(allocation&&m.AllocationBase!=allocation)||(m.Protect&(PAGE_GUARD|PAGE_NOACCESS)))return 0;
  DWORD k=m.Protect&0xff;
  if(k!=PAGE_READONLY&&k!=PAGE_READWRITE&&k!=PAGE_WRITECOPY&&k!=PAGE_EXECUTE_READ&&k!=PAGE_EXECUTE_READWRITE&&k!=PAGE_EXECUTE_WRITECOPY)return 0;
  if(executable&&k!=PAGE_EXECUTE_READ&&k!=PAGE_EXECUTE_READWRITE&&k!=PAGE_EXECUTE_WRITECOPY)return 0;
  uintptr_t start=(uintptr_t)m.BaseAddress;if(m.RegionSize>UINTPTR_MAX-start||start+m.RegionSize<=cursor)return 0;cursor=start+m.RegionSize;
 }return 1;
}
static FILE *local_file(const wchar_t *name,const wchar_t *mode){
 wchar_t path[32768];DWORD n=GetModuleFileNameW(self,path,32768);if(!n||n>=32768)return NULL;
 wchar_t *slash=wcsrchr(path,L'\\');if(!slash)return NULL;slash[1]=0;
 if(wcslen(path)+wcslen(name)>=32768)return NULL;wcscat(path,name);return _wfopen(path,mode);
}
static void status(const char *s){FILE*f=local_file(L"item-status.txt",L"wb");if(f){fprintf(f,"%s\n",s);fclose(f);}}
static int object(uintptr_t p,size_t n,int32_t *id){
 if(!readable((void*)p,n,NULL,0))return 0;
 uint32_t flags=*(uint32_t*)(p+8);if(flags&0x60018000u)return 0;
 uintptr_t vt=*(uintptr_t*)p;if(!readable((void*)vt,8,base,0))return 0;
 int32_t index=*(int32_t*)(p+12);if(index<0||index>100000000)return 0;if(id)*id=index;return 1;
}
static int same_object(uintptr_t p,size_t n,int32_t id){int32_t actual;return object(p,n,&actual)&&actual==id;}

/* TMap<FGameplayTag,int32> is a 0x50-byte TSparseArray/TSet wrapper.
 * Scan allocated slots only; erased holes are never read as inventory entries.
 * All bounds and buffers are checked before reading. */
static int item_count(uintptr_t component,uint64_t tag,int *value){
 uintptr_t map=component+0x150;
 if(!readable((void*)map,0x50,NULL,0))return 0;
 uintptr_t data=*(uintptr_t*)map,bit_heap=*(uintptr_t*)(map+0x20);
 int32_t num=*(int32_t*)(map+8),cap=*(int32_t*)(map+12),bits=*(int32_t*)(map+0x28),bitcap=*(int32_t*)(map+0x2c),free_count=*(int32_t*)(map+0x34);
 if(num<0||num>65536||cap<num||cap>65536||bits<num||bits>65536||bitcap<bits||bitcap>65536||free_count<0||free_count>num)return 0;
 if(!num){*value=0;return 1;}
 uintptr_t flags=bit_heap?bit_heap:map+0x10;
 if((!bit_heap&&bits>128)||!readable((void*)flags,((size_t)bits+31)/32*4,NULL,0)||!readable((void*)data,(size_t)num*20,NULL,0))return 0;
 int found=0,live=0,result=0;
 for(int i=0;i<num;i++){
  if(!(*(uint32_t*)(flags+(size_t)(i>>5)*4)&(1u<<(i&31))))continue;
  live++;uintptr_t entry=data+(size_t)i*20;
  /* FGameplayTag is two 32-bit words in 20-byte entries: odd entries are
   * four-byte aligned, so a uint64_t pointer dereference is undefined. */
  uint64_t entry_tag;memcpy(&entry_tag,(void*)entry,sizeof(entry_tag));
  if(entry_tag==tag){if(found++)return 0;result=*(int32_t*)(entry+8);if(result<0||result>100000000)return 0;}
 }
 if(live!=num-free_count)return 0;*value=result;return 1;
}
static Resource resource(uintptr_t pointer,int32_t id){
 Resource out={0};if(!same_object(pointer,0x120,id))return out;
 unsigned char overridden=*(unsigned char*)(pointer+0x104);if(overridden>1)return out;
 float current=*(float*)(pointer+0x10c),maximum=*(float*)(pointer+(overridden?0x100:0x110));
 if(!isfinite(current)||!isfinite(maximum)||maximum<=0||maximum>10000000||current<0||current>maximum+0.01f)return out;
 out.current=current;out.maximum=maximum;out.valid=1;return out;
}
static int build_supported(void){
 base=(unsigned char*)GetModuleHandleW(NULL);
 if(!readable(base,sizeof(IMAGE_DOS_HEADER),base,0))return 0;
 IMAGE_DOS_HEADER *dos=(IMAGE_DOS_HEADER*)base;if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<64||dos->e_lfanew>0x100000)return 0;
 IMAGE_NT_HEADERS64 *nt=(IMAGE_NT_HEADERS64*)(base+dos->e_lfanew);
 if(!readable(nt,sizeof(*nt),base,0)||nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64||nt->OptionalHeader.Magic!=IMAGE_NT_OPTIONAL_HDR64_MAGIC||nt->OptionalHeader.SizeOfImage!=187576320u||nt->FileHeader.TimeDateStamp!=141614920u)return 0;
 /* Generated from inspected original bytes; update only after a fresh analysis. */
 static const unsigned char use_prefix[]={0x48,0x89,0x5c,0x24,0x18,0x48,0x89,0x74,0x24,0x20,0x48,0x89,0x54,0x24,0x10};
 if(!readable(base+0x17c4300,sizeof(use_prefix),base,1)||memcmp(base+0x17c4300,use_prefix,sizeof(use_prefix)))return 0;
 if(!readable(base+0x9c4c508+0x4f8,sizeof(void*),base,0))return 0;
 static const unsigned char queue_prefix[]={0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10};
 static const unsigned char resolve_prefix[]={0x4c,0x8b,0xdc,0x55,0x49,0x8d,0x6b,0xe8};
 if(!readable(base+0x17d9c90,sizeof(queue_prefix),base,1)||memcmp(base+0x17d9c90,queue_prefix,sizeof(queue_prefix))||!readable(base+0x17dd5f0,sizeof(resolve_prefix),base,1)||memcmp(base+0x17dd5f0,resolve_prefix,sizeof(resolve_prefix)))return 0;
 const uintptr_t vt[2]={0x9b8eaa8,0x9c61b90};
 for(int i=0;i<2;i++){if(!readable(base+vt[i]+0x4f8,0x58,base,0))return 0;combat_slots[i*2]=(void**)(base+vt[i]+0x4f8);combat_slots[i*2+1]=(void**)(base+vt[i]+0x548);}
 original_queue=(QueueItem)(base+0x17d9c90);original_resolve=(ResolveItem)(base+0x17dd5f0);
 patch_slot=(void**)(base+0x9c4c508+0x4f8);original=(UseItem)(base+0x17c4300);return 1;
}
static int watched_component(uintptr_t component,int32_t *id){
 if(!installed||inside||GetCurrentThreadId()!=game_thread||!same_object(inventory,0x390,inventory_id)||!object(component,0x378,id))return -1;
 uintptr_t vt=*(uintptr_t*)component;
 if(vt!=(uintptr_t)(base+0x9b8eaa8)&&vt!=(uintptr_t)(base+0x9c61b90)
#ifdef ITEM_FEEDBACK_TEST
 &&vt!=(uintptr_t)base
#endif
 )return -1;
 uintptr_t owner=*(uintptr_t*)(component+0x20);
 for(int i=0;i<target_count;i++)if(targets[i].actor==owner&&same_object(owner,0x28,targets[i].actor_id))return i;
 return -1;
}
static void capture(Event *e,int after){
 for(int i=0;i<target_count;i++)if(same_object(targets[i].actor,0x28,targets[i].actor_id)){
  Delta *d=&e->targets[i];d->actor=targets[i].actor;
  Resource hp=resource(targets[i].health,targets[i].health_id),sp=resource(targets[i].stamina,targets[i].stamina_id);
  if(after){d->hp1=hp;d->sp1=sp;}else{d->hp0=hp;d->sp0=sp;}
 }
}
static void enqueue(Event *e){e->sequence=++sequence;unsigned next=(head+1)%QUEUE_SIZE;if(next==tail)dropped++;else{queue[head]=*e;head=next;}}
/* Queue is the exact player item-selection transaction: native inventory
 * removal uses apply_effects=0. Keep its actual receipt, never emit a heal yet. */
static void observed_queue(void *component,const uint64_t *tagptr){
 int32_t id;int index=watched_component((uintptr_t)component,&id);
 if(index<0||!readable(tagptr,8,NULL,0)){original_queue(component,tagptr);return;}
 uint64_t tag=*tagptr;int before,after;receipts[index]=(Receipt){0};
 int measured=tag&&*(int32_t*)(inventory+0x25c)==-1&&item_count(inventory,tag,&before);
 inside=1;original_queue(component,tagptr);inside=0;
 if(measured&&same_object((uintptr_t)component,0x378,id)&&same_object(inventory,0x390,inventory_id)&&item_count(inventory,tag,&after)&&before-after==1&&*(uint64_t*)((uintptr_t)component+0x370)==tag)
  receipts[index]=(Receipt){(uintptr_t)component,id,tag,1};
}
/* Round resolution invokes the game's effect application synchronously.
 * Only a matching consumed receipt may produce a success notification. */
static void observed_resolve(void *component){
 int32_t id;int index=watched_component((uintptr_t)component,&id);
 if(index<0){original_resolve(component);return;}
 Receipt r=receipts[index];receipts[index]=(Receipt){0};
 uint64_t tag=*(uint64_t*)((uintptr_t)component+0x370);int remaining;
 if(!tag||r.component!=(uintptr_t)component||r.id!=id||r.tag!=tag||r.consumed!=1||!item_count(inventory,tag,&remaining)){original_resolve(component);return;}
 Event e={0};e.epoch=epoch;e.tag=tag;e.requested=1;e.count=target_count;capture(&e,0);
 inside=1;original_resolve(component);inside=0;
 if(!same_object(inventory,0x390,inventory_id)||!item_count(inventory,tag,&remaining))return;
 e.after=remaining;e.before=remaining+r.consumed;capture(&e,1);enqueue(&e);
}
static uint64_t observed_use(void *component,uint64_t tag,uint8_t apply_effects,int32_t requested){
 /* Always preserve the exact original call, return value and gameplay effects. */
 if(!installed||GetCurrentThreadId()!=game_thread||inside||!apply_effects||requested<=0||requested>100000||(uintptr_t)component!=inventory||!same_object(inventory,0x390,inventory_id)||*(int32_t*)(inventory+0x25c)!=-1)return original(component,tag,apply_effects,requested);
 Event event={0};event.epoch=epoch;event.tag=tag;event.requested=requested;event.count=target_count;
 if(!item_count(inventory,tag,&event.before))return original(component,tag,apply_effects,requested);
 for(int i=0;i<target_count;i++){
  event.targets[i].actor=targets[i].actor;
  if(same_object(targets[i].actor,0x28,targets[i].actor_id)){
   event.targets[i].hp0=resource(targets[i].health,targets[i].health_id);event.targets[i].sp0=resource(targets[i].stamina,targets[i].stamina_id);
  }
 }
 inside=1;uint64_t result=original(component,tag,apply_effects,requested);inside=0;
 if(!same_object(inventory,0x390,inventory_id)||!item_count(inventory,tag,&event.after))return result;
 /* A concurrent unexpected inventory rewrite is not a usable observation. */
 if(event.after>event.before||event.before-event.after>requested)return result;
 for(int i=0;i<target_count;i++)if(same_object(targets[i].actor,0x28,targets[i].actor_id)){
  event.targets[i].hp1=resource(targets[i].health,targets[i].health_id);event.targets[i].sp1=resource(targets[i].stamina,targets[i].stamina_id);
 }
 event.sequence=++sequence;
 unsigned next=(head+1)%QUEUE_SIZE;if(next==tail)dropped++;else{queue[head]=event;head=next;}
 return result;
}
static int exchange_at(void **slot,void *expected,void *replacement){
 DWORD old;if(!VirtualProtect(slot,sizeof(void*),PAGE_READWRITE,&old))return 0;
 void *actual=InterlockedCompareExchangePointer((void*volatile*)slot,replacement,expected);
 DWORD ignored;int restored=VirtualProtect(slot,sizeof(void*),old,&ignored)!=0;
 if(actual!=expected)return 0;
 if(!restored){InterlockedCompareExchangePointer((void*volatile*)slot,expected,replacement);return 0;}
 return 1;
}
static int exchange_slot(void *expected,void *replacement){return exchange_at(patch_slot,expected,replacement);}
static void *combat_original(int i){return i%2?(void*)original_resolve:(void*)original_queue;}
static void *combat_hook(int i){return i%2?(void*)observed_resolve:(void*)observed_queue;}
static int restore_combat(void){int ok=1;for(int i=3;i>=0;i--)if(combat_mask&(1u<<i)){if(exchange_at(combat_slots[i],combat_hook(i),combat_original(i)))combat_mask&=~(1u<<i);else ok=0;}return ok;}
static int read_watch(uintptr_t *inv,uint64_t *watch_epoch,Target *list,int *count){
 FILE*f=local_file(L"item-watch.txt",L"rb");if(!f)return 0;
 unsigned version;unsigned long long value,e;int n;
 if(fscanf(f,"%u %llu %llx %d",&version,&e,&value,&n)!=4||version!=1||e==0||n<0||n>MAX_TARGETS){fclose(f);return 0;}
 *inv=(uintptr_t)value;*watch_epoch=e;*count=n;
 for(int i=0;i<n;i++){
  unsigned long long a,h,s;if(fscanf(f,"%llx %llx %llx",&a,&h,&s)!=3){fclose(f);return 0;}
  list[i].actor=(uintptr_t)a;list[i].health=(uintptr_t)h;list[i].stamina=(uintptr_t)s;
  if(!object(list[i].actor,0x28,&list[i].actor_id)){watch_error="ERROR invalid actor object";fclose(f);return 0;}
  if(list[i].health&&!object(list[i].health,0x120,&list[i].health_id)){watch_error="ERROR invalid health object";fclose(f);return 0;}
  if(list[i].stamina&&!object(list[i].stamina,0x120,&list[i].stamina_id)){watch_error="ERROR invalid stamina object";fclose(f);return 0;}
  /* UObject outer equals owning actor in these verified resource components. */
  if((list[i].health&&*(uintptr_t*)(list[i].health+0x20)!=list[i].actor)||(list[i].stamina&&*(uintptr_t*)(list[i].stamina+0x20)!=list[i].actor)){watch_error="ERROR resource owner offset mismatch";fclose(f);return 0;}
 }
 int c;do{c=fgetc(f);}while(c==' '||c=='\r'||c=='\n'||c=='\t');fclose(f);return c==EOF;
}
__declspec(dllexport) int ItemFeedback_install(void *unused){
 (void)unused;if(installed&&GetCurrentThreadId()!=game_thread){status("ERROR wrong thread");return 0;}
 if(!build_supported()){status("ERROR unsupported game build");return 0;}
 uintptr_t inv;uint64_t e;Target proposed[MAX_TARGETS]={0};int n,id;
 watch_error="ERROR invalid watch syntax";
 if(!read_watch(&inv,&e,proposed,&n)){status(watch_error);return 0;}
 if(!object(inv,0x390,&id)){status("ERROR invalid inventory object");return 0;}
 if(*(uintptr_t*)inv!=(uintptr_t)(base+0x9c4c508)){status("ERROR inventory vtable mismatch");return 0;}
 if(installed){if(*patch_slot!=(void*)observed_use||combat_mask!=15){status("ERROR hook replaced or incomplete installation");return 0;}for(int i=0;i<4;i++)if(*combat_slots[i]!=combat_hook(i)){status("ERROR combat hook replaced by another module");return 0;}}
 else{
  if(*patch_slot!=(void*)original){status("ERROR unexpected inventory vtable");return 0;}
  for(int i=0;i<4;i++)if(*combat_slots[i]!=combat_original(i)){status("ERROR unexpected combat vtable");return 0;}
  /* Pin the observer: its callback can never point at an unloaded DLL. */
  HMODULE pinned;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)(uintptr_t)observed_use,&pinned)){status("ERROR cannot pin observer");return 0;}
  game_thread=GetCurrentThreadId();
  if(!exchange_slot((void*)original,(void*)observed_use)){status("ERROR cannot install observer");return 0;}
  installed=1;
  for(int i=0;i<4;i++){
   if(!exchange_at(combat_slots[i],combat_original(i),combat_hook(i))){restore_combat();if(!combat_mask&&exchange_slot((void*)observed_use,(void*)original))installed=0;status("ERROR cannot install combat observer; remove required");return 0;}
   combat_mask|=1u<<i;
  }
 }
 if(epoch!=e||inventory!=inv){head=tail=0;dropped=0;memset(receipts,0,sizeof(receipts));}
 inventory=inv;inventory_id=id;epoch=e;target_count=n;memcpy(targets,proposed,sizeof(targets));status("INSTALLED");return 0;
}
__declspec(dllexport) int ItemFeedback_remove(void *unused){
 (void)unused;if(!installed){status("REMOVED");return 0;}
 if(GetCurrentThreadId()!=game_thread||inside){status("ERROR wrong thread or active callback");return 0;}
 if(!restore_combat()){status("ERROR combat observer restoration failed");return 0;}
 if(!exchange_slot((void*)observed_use,(void*)original)){status("ERROR observer restoration failed");return 0;}
 installed=0;inventory=0;target_count=0;head=tail=0;memset(receipts,0,sizeof(receipts));status("REMOVED");return 0;
}
static void print_resource(FILE*f,Resource before,Resource after){
 int valid=before.valid&&after.valid;fprintf(f," %d %.9g %.9g %.9g %.9g",valid,before.current,after.current,before.maximum,after.maximum);
}
__declspec(dllexport) int ItemFeedback_drain(void *unused){
 (void)unused;if(installed&&GetCurrentThreadId()!=game_thread){status("ERROR wrong thread");return 0;}
 FILE*f=local_file(L"item-events.txt",L"wb");if(!f){status("ERROR cannot write event mailbox");return 0;}
 fprintf(f,"ITEM_EVENTS 1 %u\n",dropped);dropped=0;
 while(tail!=head){Event*e=&queue[tail];fprintf(f,"E %llu %llu %u %u %d %d %d %d\n",(unsigned long long)e->epoch,(unsigned long long)e->sequence,(unsigned)e->tag,(unsigned)(e->tag>>32),e->before,e->after,e->requested,e->count);
  for(int i=0;i<e->count;i++){Delta*d=&e->targets[i];fprintf(f,"T %llx",(unsigned long long)d->actor);print_resource(f,d->hp0,d->hp1);print_resource(f,d->sp0,d->sp1);fputc('\n',f);}tail=(tail+1)%QUEUE_SIZE;
 }fclose(f);return 0;
}
BOOL WINAPI DllMain(HINSTANCE module,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=module;DisableThreadLibraryCalls(module);}return TRUE;}

