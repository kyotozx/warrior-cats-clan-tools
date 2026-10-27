/* Den-only, bounded recipe transactions through native inventory callbacks.
 * No save/map writes; material deductions use the same signed AddItem call as
 * ASwtAdventureHousingHotspot::OnOptionPicked. Lua owns the review/backup UI. */
#include "admin_inventory_common.h"
#include "workshop_catalog.h"
#include "workshop_guards.h"
static uint64_t last_applied;
static int workshop_count(uintptr_t component,uint64_t tag,unsigned kind,int*value){
 /* The shared reader adds 0x150. Native supplies, ready decorations and
  * accessories are identical sparse maps at 0x150, 0x1a0 and 0x1f0. */
 if(kind>2)return 0;return item_count(component+kind*0x50,tag,value);
}
static int tag_for(unsigned index,uint64_t*out){
 uint64_t name=0,tag=0;
 ((void*(*)(void*,const char*))(base+0x1b10c80))(&name,workshop_items[index].tag);
 ((void*(*)(void*,const void*,int))(base+0x3cda1c0))(&tag,&name,0);
 if(!name||tag!=name)return 0;*out=tag;return 1;
}
static int den_ok(uintptr_t actor){
 if(!readable((void*)actor,0x3f8,NULL,0)||(*(uint32_t*)(actor+8)&0x60018000u))return 0;
 uintptr_t v=*(uintptr_t*)actor;
 if(v!=(uintptr_t)(base+0x9b49b28)&&v!=(uintptr_t)(base+0x9c4e190))return 0;
 if(*(int32_t*)(actor+0x3f0)!=-1||!*(uint64_t*)(actor+0x2f0))return 0;
 uintptr_t level=*(uintptr_t*)(actor+0x20);
 return readable((void*)level,0xc8,NULL,0)&&!(*(uint32_t*)(level+8)&0x60018000u)&&*(uintptr_t*)(level+0xc0)!=0;
}
static uint64_t mix(uint64_t h,uint64_t n){return(h^n)*UINT64_C(1099511628211);}
static int run(void){
 unsigned long long nonce=0,object=0,owner=0,cls=0,manager=0,den=0,expected=0;
 unsigned index=0;int quantity=0,free_mode=0,current=0,after=0,allowed=0,mutated=0;
 int counts[4]={0},needs[4]={0};uint64_t tags[4]={0},tag=0,stamp=0;
 char command[20]={0};const char*message="Invalid request";
 FILE*f=local_file(L"workshop-request.txt",L"r");if(!f)goto done;
 int fields=fscanf(f,"%llu %19s %llx %llx %llx %llx %llx %u %d %d %llx",&nonce,command,&object,&owner,&cls,&manager,&den,&index,&quantity,&free_mode,&expected);
 int extra=fgetc(f);while(extra==' '||extra=='\r'||extra=='\n'||extra=='\t')extra=fgetc(f);fclose(f);
 int apply=!strcmp(command,"CRAFT"),probe=!strcmp(command,"PROBE");
 if(fields!=11||extra!=EOF||!nonce||(!apply&&!probe)||index<1||index>sizeof(workshop_items)/sizeof(workshop_items[0])||quantity<1||quantity>99||(free_mode!=0&&free_mode!=1))goto done;
 if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
 if(!build_ok()){message="Unsupported game build";goto done;}
 for(unsigned i=0;i<sizeof(workshop_guards)/sizeof(workshop_guards[0]);i++)if(!readable(base+workshop_guards[i].rva,16,base,1)||memcmp(base+workshop_guards[i].rva,workshop_guards[i].code,16)){message="Inventory category callbacks changed";goto done;}
 if(!manager_ok((void*)(uintptr_t)manager)||!den_ok((uintptr_t)den)){message="Save or den changed";goto done;}
 unsigned char*c=(void*)(uintptr_t)object,*state=(void*)(uintptr_t)owner;
 if(!readable(c,0x390,NULL,0)||!readable(state,0x3c0,NULL,0)||!readable((void*)(uintptr_t)cls,0x40,NULL,0)){message="Invalid inventory mappings";goto done;}
 if((*(uint32_t*)(c+8)&0x60018000u)||(*(uint32_t*)(state+8)&0x60018000u)||*(void**)c!=base+0x9c4b220||*(uintptr_t*)(c+0x10)!=cls||*(void**)(c+0x20)!=state||*(void**)(state+0x388)!=c||*(int*)(c+0x25c)!=-1){message="Inventory class or owner changed";goto done;}
 if(*(void**)(base+0x9c4b220+0x4f0)!=base+0x17c4020||*(void**)(base+0x9c4b220+0x508)!=base+0x1657760||*(void**)(base+0x9c4b220+0x500)!=base+0x17c53c0){message="Inventory callbacks changed";goto done;}
 const WorkshopItem*item=&workshop_items[index-1];
 if(!tag_for(index-1,&tag)||!workshop_count(object,tag,item->kind,&current)||current>100000000-quantity){message="Invalid item or quantity";goto done;}
 after=current;
 allowed=((uint8_t(*)(void*,uint64_t,int))(base+0x17c4020))(c,tag,quantity)?1:0;
 stamp=mix(mix(mix(UINT64_C(1469598103934665603),index),quantity),free_mode);stamp=mix(stamp,current);
 if(!free_mode&&!item->count)allowed=3;
 for(unsigned i=0;i<item->count;i++){
  if(!tag_for(item->material[i],&tags[i])||!item_count(object,tags[i],&counts[i])){message="Invalid material count";goto done;}
  needs[i]=free_mode?0:item->amount[i]*quantity;
  if(counts[i]<needs[i])allowed=2;
  stamp=mix(stamp,counts[i]);
 }
 if(apply){
  if(nonce==last_applied){message="Request already consumed";goto done;}
  if(stamp!=expected){message="Inventory changed; refresh the preview";goto done;}
  if(allowed!=1){message="Recipe or inventory requirements are not met";goto done;}
  last_applied=nonce;
  for(unsigned i=0;i<item->count;i++)if(needs[i]){
   mutated=1;((void(*)(void*,uint64_t,int,uint8_t))(base+0x1655c90))(c,tags[i],-needs[i],1);
   int readback=0;
   if(!item_count(object,tags[i],&readback)||readback!=counts[i]-needs[i]){message="Material readback failed; review inventory before retrying";goto done;}
  }
  mutated=1;
  if(item->kind==1)((void(*)(void*,uint64_t,int))(base+0x1655e00))(c,tag,quantity);
  else if(item->kind==2)((void(*)(void*,uint64_t,int))(base+0x1656020))(c,tag,quantity);
  else ((void(*)(void*,uint64_t,int,uint8_t))(base+0x1655c90))(c,tag,quantity,1);
  if(!workshop_count(object,tag,item->kind,&after)||after!=current+quantity){message="Item readback failed; review inventory before retrying";goto done;}
 }
 message=apply?"APPLIED":"READY";
done:
 f=local_file(L"workshop-status.txt",L"w");if(f){
  fprintf(f,"nonce=%llu\nstatus=%s\ncurrent=%d\nafter=%d\nallowed=%d\nstamp=%llx\nmutated=%d\n",nonce,message,current,after,allowed,(unsigned long long)stamp,mutated);
  for(int i=0;i<4;i++)fprintf(f,"cost%d=%d\nneed%d=%d\n",i+1,counts[i],i+1,needs[i]);fclose(f);
 }return 0;
}
__declspec(dllexport) int ClanWorkshop_run(void*lua){(void)lua;return run();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
