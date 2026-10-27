/* Actual game and menu input-map adapter. Build to settings-remap-v3.dll.
 * Keeps canonical settings-bridge.dll untouched during root's live probes. */
#include "settings_bridge.c"
#include <math.h>
#include "settings_menu_catalog.h"
#define REMAP_MAX 192
typedef Array*(*Generator)(void*,Array*);
typedef struct{unsigned device,command,kind;uint64_t source,target;uint32_t scale;} RemapRule;
static RemapRule rules[REMAP_MAX];static unsigned rule_count;
static void*bound_input;static int32_t bound_index;static uintptr_t bound_pc;
static Generator generators[2];static void**generator_slots[2];static int remap_installed;static unsigned hook_flags;
static uint64_t remap_epoch;static void(*release_reference)(void*);
typedef void(*ActionAdder)(void*,uint8_t,void*,uint8_t,uint8_t,uint8_t,uint8_t);
typedef void(*AxisAdder)(void*,uint8_t,void*,float);
static ActionAdder original_action;static AxisAdder original_axis;static void **action_slot,**axis_slot;
static uint8_t(*is_gamepad_key)(void*);
static int input_ok(void*p,uintptr_t pc){return obj(p,0x9c43f40,0x4a0)&&readable((void*)pc,0x30)&&!(*(uint32_t*)(pc+8)&0x60018000u)&&*(uintptr_t*)((char*)p+0x20)==pc;}
static int bound_ok(void){return bound_input&&input_ok(bound_input,bound_pc)&&*(int32_t*)((char*)bound_input+12)==bound_index;}
static int array_ok(const Array*a){if(a->n<0||a->n>256||a->cap<a->n)return 0;if(a->n&&!readable(a->p,(size_t)a->n*0x58))return 0;for(int i=0;i<a->n;i++)if(a->p[i*0x58]>1)return 0;return 1;}
static uint64_t entry_key(const unsigned char*p){uint64_t key;memcpy(&key,p+(p[0]?0x40:0x18),8);return key;}
static uint32_t entry_scale(const unsigned char*p){uint32_t scale=0x3f800000;if(p[0])memcpy(&scale,p+0x38,4);return scale;}
static int match(const RemapRule*r,unsigned device,const unsigned char*p){return r->device==device&&r->command==p[1]&&r->kind==p[0]&&r->source==entry_key(p)&&r->scale==entry_scale(p);}
static unsigned patch_array(Array*a,unsigned device){
 if(!array_ok(a))return 0;unsigned changed=0;
 for(int i=0;i<a->n;i++){unsigned char*p=a->p+i*0x58;for(unsigned j=0;j<rule_count;j++)if(match(&rules[j],device,p)){
  unsigned char*key=p+(p[0]?0x40:0x18);void*reference;memcpy(&reference,key+16,8);
  /* FKey's cached details is a shared pointer; replacing only KeyName would
   * retain metadata for the previous physical key. The game parser zeros it. */
  if(reference)release_reference(reference);memcpy(key,&rules[j].target,8);memset(key+8,0,16);changed++;break;
 }}return changed;
}
/* Common menu maps are added directly, before generated gameplay arrays. */
static unsigned common_device(unsigned i){return is_gamepad_key(base+menu_catalog[i].key_rva)?0:1;}
static uint64_t common_name(unsigned i){uint64_t name;memcpy(&name,base+menu_catalog[i].key_rva,8);return name;}
static int common_matches(const RemapRule*r){int n=0;for(unsigned i=0;i<sizeof(menu_catalog)/sizeof(menu_catalog[0]);i++)if(r->command==menu_catalog[i].command&&r->kind==menu_catalog[i].kind&&r->scale==menu_catalog[i].scale&&r->source==common_name(i)&&r->device==common_device(i))n++;return n;}
static void patch_common_key(uint8_t command,unsigned kind,uint32_t scale,void*key){
 if(command>=60)return;uint64_t name;memcpy(&name,key,8);
 for(unsigned i=0;i<rule_count;i++)if(rules[i].command==command&&rules[i].kind==kind&&rules[i].scale==scale&&rules[i].source==name){
  void*reference;memcpy(&reference,(char*)key+16,8);if(reference)release_reference(reference);memcpy(key,&rules[i].target,8);memset((char*)key+8,0,16);return;
 }
}
static int should_patch(void*p){return remap_installed&&GetCurrentThreadId()==thread_id&&p==bound_input&&bound_ok();}
static void add_action(void*p,uint8_t command,void*key,uint8_t shift,uint8_t ctrl,uint8_t alt,uint8_t cmd){
 if(should_patch(p)&&!shift&&!ctrl&&!alt&&!cmd)patch_common_key(command,0,0x3f800000,key);
 original_action(p,command,key,shift,ctrl,alt,cmd);
}
static void add_axis(void*p,uint8_t command,void*key,float scale){uint32_t bits;memcpy(&bits,&scale,4);if(should_patch(p))patch_common_key(command,1,bits,key);original_axis(p,command,key,scale);}
static Array*generated(void*self_input,Array*out,unsigned device){Array*result=generators[device](self_input,out);if(remap_installed&&GetCurrentThreadId()==thread_id&&self_input==bound_input&&bound_ok())patch_array(result,device);return result;}
static Array*gamepad(void*p,Array*out){return generated(p,out,0);}
static Array*keyboard(void*p,Array*out){return generated(p,out,1);}
static int swap(void**slot,void*old,void*next){DWORD protect;if(!VirtualProtect(slot,8,PAGE_READWRITE,&protect))return 0;void*actual=InterlockedCompareExchangePointer((void*volatile*)slot,next,old);DWORD ignored;int restored=VirtualProtect(slot,8,protect,&ignored)!=0;if(actual!=old)return 0;if(!restored){InterlockedCompareExchangePointer((void*volatile*)slot,old,next);return 0;}return 1;}
static int remap_init(void){if(!init())return 0;generator_slots[0]=(void**)(base+0x9c43f40+0x348);generator_slots[1]=(void**)(base+0x9c43f40+0x350);generators[0]=(Generator)(base+0x128a600);generators[1]=(Generator)(base+0x128a6d0);release_reference=(void(*)(void*))(base+0x119de70);
 action_slot=(void**)(base+0x9c43f40+0x388);axis_slot=(void**)(base+0x9c43f40+0x390);original_action=(ActionAdder)(base+0x128b120);original_axis=(AxisAdder)(base+0x128b290);is_gamepad_key=(uint8_t(*)(void*))(base+0x1d6c470);
 return *(uintptr_t*)(base+0x9c43f40+0x340)==(uintptr_t)(base+0x1929400)&&*generator_slots[0]==((hook_flags&1)?(void*)gamepad:(void*)generators[0])&&*generator_slots[1]==((hook_flags&2)?(void*)keyboard:(void*)generators[1])&&*action_slot==((hook_flags&4)?(void*)add_action:(void*)original_action)&&*axis_slot==((hook_flags&8)?(void*)add_axis:(void*)original_axis);}
static int remove_remap(void){
 if(!hook_flags){bound_input=NULL;rule_count=0;remap_installed=0;return 1;}
 remap_installed=0;
 if(hook_flags&1){if(!swap(generator_slots[0],(void*)gamepad,(void*)generators[0]))return 0;hook_flags&=~1u;}
 if(hook_flags&2){if(!swap(generator_slots[1],(void*)keyboard,(void*)generators[1]))return 0;hook_flags&=~2u;}
 if(hook_flags&4){if(!swap(action_slot,(void*)add_action,(void*)original_action))return 0;hook_flags&=~4u;}
 if(hook_flags&8){if(!swap(axis_slot,(void*)add_axis,(void*)original_axis))return 0;hook_flags&=~8u;}
 remap_installed=0;rule_count=0;if(bound_ok())rebuild(bound_input);bound_input=NULL;return 1;
}
static void remap_ok(unsigned id,const char*message){FILE*f=local_file(L"remap-response.txt",L"wb");if(f){fprintf(f,"%u OK %s\n",id,message);fclose(f);}}
static void remap_error(unsigned id,const char*message){FILE*f=local_file(L"remap-response.txt",L"wb");if(f){fprintf(f,"%u ERROR %s\n",id,message);fclose(f);}}
__declspec(dllexport) int Remap_command(void*unused){
 (void)unused;unsigned id=0,count=0;char action[16];unsigned long long input_address=0,pc=0,epoch=0;
 FILE*f=local_file(L"remap-request.txt",L"rb");if(!f){remap_error(0,"missing request");return 0;}
 int parsed=fscanf(f,"%u %15s %llx %llx %llu %u",&id,action,&input_address,&pc,&epoch,&count);
 if(parsed<2||!id){fclose(f);remap_error(id,"invalid request");return 0;}
 if(!thread_id)thread_id=GetCurrentThreadId();if(thread_id!=GetCurrentThreadId()||!remap_init()){fclose(f);remap_error(id,"unsupported build/thread or replaced hook");return 0;}
 if(!strcmp(action,"REMOVE")){fclose(f);if(remove_remap())remap_ok(id,"REMOVED");else remap_error(id,"cannot restore input generator hooks");return 0;}
 void*input=(void*)(uintptr_t)input_address;if(parsed!=6||!epoch||count>REMAP_MAX||!input_ok(input,(uintptr_t)pc)){fclose(f);remap_error(id,"invalid live input context");return 0;}
 Array arrays[2]={{0},{0}};generators[0](input,&arrays[0]);generators[1](input,&arrays[1]);
 if(!array_ok(&arrays[0])||!array_ok(&arrays[1])){fclose(f);remap_error(id,"unsupported generated input map");return 0;}
 if(!strcmp(action,"LIST")){
  fclose(f);f=local_file(L"remap-response.txt",L"wb");if(f){fprintf(f,"%u OK LIST\n",id);
   for(unsigned i=0;i<sizeof(menu_catalog)/sizeof(menu_catalog[0]);i++){
    unsigned device=common_device(i);uint64_t original=common_name(i),active=original;uint32_t scale=menu_catalog[i].scale;
    if(remap_installed&&input==bound_input&&bound_ok())for(unsigned j=0;j<rule_count;j++)if(rules[j].device==device&&rules[j].command==menu_catalog[i].command&&rules[j].kind==menu_catalog[i].kind&&rules[j].scale==scale&&rules[j].source==original){active=rules[j].target;break;}
    fprintf(f,"B %u %u %u %u %u %u %u %u\n",device,menu_catalog[i].command,menu_catalog[i].kind,(unsigned)original,(unsigned)(original>>32),scale,(unsigned)active,(unsigned)(active>>32));
   }
   for(unsigned device=0;device<2;device++)for(int i=0;i<arrays[device].n;i++){unsigned char*p=arrays[device].p+i*0x58;uint64_t original=entry_key(p),active=original;uint32_t scale=entry_scale(p);if(remap_installed&&input==bound_input&&bound_ok())for(unsigned j=0;j<rule_count;j++)if(match(&rules[j],device,p)){active=rules[j].target;break;}
    fprintf(f,"B %u %u %u %u %u %u %u %u\n",device,p[1],p[0],(unsigned)original,(unsigned)(original>>32),scale,(unsigned)active,(unsigned)(active>>32));
   }
   fclose(f);
  }dispose(&arrays[0]);dispose(&arrays[1]);return 0;
 }
 RemapRule next[REMAP_MAX];int valid_request=!strcmp(action,"APPLY");
 for(unsigned i=0;i<count&&valid_request;i++){
  unsigned source_index,source_number,target_index,target_number;RemapRule*r=&next[i];
  if(fscanf(f,"%u %u %u %u %u %u %u %u",&r->device,&r->command,&r->kind,&source_index,&source_number,&r->scale,&target_index,&target_number)!=8||r->device>1||r->command<1||r->command>=110||r->kind>1||!source_index||!target_index||source_number||target_number){valid_request=0;break;}
  r->source=((uint64_t)source_number<<32)|source_index;r->target=((uint64_t)target_number<<32)|target_index;
  int matches=r->command<60?common_matches(r):0;Array*a=&arrays[r->device];for(int k=0;k<a->n;k++)if(match(r,r->device,a->p+k*0x58))matches++;
  if(matches!=1){valid_request=0;break;}
  for(unsigned j=0;j<i;j++)if(next[j].device==r->device&&next[j].command==r->command&&next[j].kind==r->kind&&next[j].scale==r->scale&&next[j].source==r->source)valid_request=0;
 }
 int trailing;do{trailing=fgetc(f);}while(trailing==' '||trailing=='\n'||trailing=='\r'||trailing=='\t');fclose(f);dispose(&arrays[0]);dispose(&arrays[1]);
 if(!valid_request||trailing!=EOF){remap_error(id,"invalid, stale or ambiguous binding rules");return 0;}
 if(bound_input&&bound_input!=input&&!remove_remap()){remap_error(id,"cannot restore previous input context");return 0;}
 if(!count){if(remove_remap())remap_ok(id,"REMOVED");else remap_error(id,"cannot restore original key map");return 0;}
 if(!remap_installed){if(hook_flags&&!remove_remap()){remap_error(id,"pending hook cleanup");return 0;}HMODULE pin;if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_PIN,(LPCWSTR)(uintptr_t)gamepad,&pin)||!swap(generator_slots[0],(void*)generators[0],(void*)gamepad)){remap_error(id,"cannot install gamepad map adapter");return 0;}hook_flags|=1;
  if(!swap(generator_slots[1],(void*)generators[1],(void*)keyboard)){remove_remap();remap_error(id,"cannot install keyboard map adapter");return 0;}hook_flags|=2;
  if(!swap(action_slot,(void*)original_action,(void*)add_action)){remove_remap();remap_error(id,"cannot install menu action adapter");return 0;}hook_flags|=4;
  if(!swap(axis_slot,(void*)original_axis,(void*)add_axis)){remove_remap();remap_error(id,"cannot install menu axis adapter");return 0;}hook_flags|=8;remap_installed=1;
 }
 bound_input=input;bound_pc=(uintptr_t)pc;bound_index=*(int32_t*)((char*)input+12);remap_epoch=epoch;memcpy(rules,next,count*sizeof(RemapRule));rule_count=count;rebuild(input);remap_ok(id,"APPLIED");return 0;
}
