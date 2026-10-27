/* Exact-build native AddItem, capacity check, notifications and game save path. */
#include "admin_inventory_common.h"
#include "admin_inventory_catalog.h"
static int run(void) {
 unsigned long long nonce=0,object=0,owner=0,cls=0,manager=0;
 unsigned index=0;int quantity=0,expected=0,current=0,after=0,allowed=0;
 char command[20]={0};const char*message="Invalid request";
 FILE*f=local_file(L"admin-inventory-request.txt",L"r");if(!f)goto done;
 int fields=fscanf(f,"%llu %19s %llx %llx %llx %llx %u %d %d",&nonce,command,&object,&owner,&cls,&manager,&index,&quantity,&expected);
 int extra=fgetc(f);while(extra==' '||extra=='\r'||extra=='\n'||extra=='\t')extra=fgetc(f);fclose(f);
 int apply=!strcmp(command,"ADD"),probe=!strcmp(command,"PROBE");
 if(fields!=9||extra!=EOF||!nonce||(!apply&&!probe)||index<1||index>sizeof(inventory_tags)/sizeof(inventory_tags[0])||quantity<1||quantity>999||expected<0||expected>100000000)goto done;
 if(!game_thread)game_thread=GetCurrentThreadId();if(game_thread!=GetCurrentThreadId()){message="Wrong thread";goto done;}
 if(!build_ok()){message="Unsupported game build";goto done;}
 if(!manager_ok((void*)(uintptr_t)manager)){message="Save manager changed";goto done;}
 unsigned char*c=(void*)(uintptr_t)object,*state=(void*)(uintptr_t)owner;
 if(!readable(c,0x390,NULL,0)||!readable(state,0x3c0,NULL,0)||!readable((void*)(uintptr_t)cls,0x40,NULL,0)){message="Invalid inventory mappings";goto done;}
 if(*(void**)c!=base+0x9c4b220||*(uintptr_t*)(c+0x10)!=cls||*(void**)(c+0x20)!=state||*(void**)(state+0x388)!=c){message="Inventory class or owner changed";goto done;}
 if(*(int*)(c+0x25c)!=-1){message="Temporary inventories are unsupported";goto done;}
 if(*(void**)(base+0x9c4b220+0x4f0)!=base+0x17c4020||*(void**)(base+0x9c4b220+0x508)!=base+0x1657760||*(void**)(base+0x9c4b220+0x500)!=base+0x17c53c0){message="Inventory callbacks changed";goto done;}
 uint64_t name=0,tag=0;
 ((void*(*)(void*,const char*))(base+0x1b10c80))(&name,inventory_tags[index-1]);
 ((void*(*)(void*,const void*,int))(base+0x3cda1c0))(&tag,&name,0);
 if(!name||tag!=name){message="Unknown inventory tag";goto done;}
 if(!item_count(object,tag,&current)){message="Invalid inventory map";goto done;}
 after=current;
 if(current>100000000-quantity){message="Inventory quantity overflow";goto done;}
 allowed=((uint8_t(*)(void*,uint64_t,int))(base+0x17c4020))(c,tag,quantity)!=0;
 if(apply){
  if(current!=expected){message="Inventory preview is stale";goto done;}
  if(!allowed){message="Your inventory has no room for this amount";goto done;}
  ((void(*)(void*,uint64_t,int,uint8_t))(base+0x1655c90))(c,tag,quantity,1);
  if(!item_count(object,tag,&after)||after!=current+quantity){message="Inventory readback mismatch; do not repeat without refreshing";goto done;}
 }
 message=apply?"APPLIED":"READY";
done:
 f=local_file(L"admin-inventory-status.txt",L"w");if(f){fprintf(f,"nonce=%llu\nstatus=%s\ncurrent=%d\nafter=%d\nallowed=%d\n",nonce,message,current,after,allowed);fclose(f);}return 0;
}
__declspec(dllexport) int ClanInventory_run(void*lua){(void)lua;return run();}
BOOL WINAPI DllMain(HINSTANCE h,DWORD reason,LPVOID reserved){(void)reserved;if(reason==DLL_PROCESS_ATTACH){self=h;DisableThreadLibraryCalls(h);}return TRUE;}
