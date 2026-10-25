#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../native/settings_remap.c"
#include <assert.h>
static int releases;static int marker;
static void release_test(void*p){assert(p==&marker);releases++;}
static void entry(unsigned char*p,unsigned command,unsigned kind,unsigned key,float scale){memset(p,0,0x58);p[0]=(unsigned char)kind;p[1]=(unsigned char)command;uint64_t name=key;unsigned char*k=p+(kind?0x40:0x18);memcpy(k,&name,8);void*reference=&marker;memcpy(k+16,&reference,8);if(kind)memcpy(p+0x38,&scale,4);}
static Array*original0(void*p,Array*out){(void)p;return out;}
static Array*original1(void*p,Array*out){(void)p;return out;}
static void original_action_test(void*p,uint8_t c,void*k,uint8_t a,uint8_t b,uint8_t d,uint8_t e){(void)p;(void)c;(void)k;(void)a;(void)b;(void)d;(void)e;}
static void original_axis_test(void*p,uint8_t c,void*k,float s){(void)p;(void)c;(void)k;(void)s;}
int main(void){
 unsigned char data[3*0x58],original[sizeof data];entry(data,60,1,10,1);entry(data+0x58,60,1,11,-1);entry(data+0xb0,65,0,12,1);memcpy(original,data,sizeof data);Array array={data,3,3};
 release_reference=release_test;rule_count=1;rules[0]=(RemapRule){.device=1,.command=60,.kind=1,.source=10,.target=20,.scale=0x3f800000};
 assert(patch_array(&array,0)==0&&releases==0&&!memcmp(data,original,sizeof data));
 assert(patch_array(&array,1)==1&&releases==1);assert(entry_key(data)==20);assert(entry_scale(data)==0x3f800000);assert(!memcmp(data+0x58,original+0x58,2*0x58));
 for(int i=0;i<0x58;i++)if(i<0x40||i>=0x58)assert(data[i]==original[i]);for(int i=0x48;i<0x58;i++)assert(data[i]==0);
 assert(patch_array(&array,1)==0&&releases==1);puts("PASS exact device/command/key/axis-side match; one cached FKey reference released; other mappings unchanged");
 rules[0]=(RemapRule){.device=0,.command=65,.kind=0,.source=12,.target=22,.scale=0x3f800000};assert(patch_array(&array,0)==1&&entry_key(data+0xb0)==22&&releases==2);
 array.n=257;assert(!array_ok(&array));array.n=3;data[0]=2;assert(!array_ok(&array));data[0]=1;
 puts("PASS action remap and malformed array rejection");
 unsigned char menu_key[24]={0};uint64_t menu_name=33;memcpy(menu_key,&menu_name,8);void*menu_reference=&marker;memcpy(menu_key+16,&menu_reference,8);
 rules[0]=(RemapRule){.device=1,.command=26,.kind=0,.source=33,.target=44,.scale=0x3f800000};patch_common_key(25,0,0x3f800000,menu_key);assert(!memcmp(menu_key,&menu_name,8)&&releases==2);
 patch_common_key(26,0,0x3f800000,menu_key);memcpy(&menu_name,menu_key,8);assert(menu_name==44&&releases==3);for(int i=8;i<24;i++)assert(menu_key[i]==0);
 puts("PASS native menu Confirm remap changes only exact command/key and releases one owned reference");
 void**slots=VirtualAlloc(NULL,4096,MEM_RESERVE|MEM_COMMIT,PAGE_READWRITE);assert(slots);generator_slots[0]=&slots[0];generator_slots[1]=&slots[1];generators[0]=original0;generators[1]=original1;
 slots[0]=gamepad;slots[1]=original1;hook_flags=1;remap_installed=0;bound_input=NULL;assert(remove_remap());assert(slots[0]==(void*)original0&&slots[1]==(void*)original1&&!hook_flags);
 slots[0]=gamepad;slots[1]=keyboard;hook_flags=3;remap_installed=1;assert(remove_remap());assert(slots[0]==(void*)original0&&slots[1]==(void*)original1&&!hook_flags&&!remap_installed);
 slots[0]=original1;slots[1]=keyboard;hook_flags=3;assert(!remove_remap());assert(slots[0]==(void*)original1);slots[0]=gamepad;assert(remove_remap());
 action_slot=&slots[2];axis_slot=&slots[3];original_action=original_action_test;original_axis=original_axis_test;slots[0]=gamepad;slots[1]=keyboard;slots[2]=add_action;slots[3]=add_axis;hook_flags=15;assert(remove_remap());assert(!hook_flags&&slots[2]==(void*)original_action_test&&slots[3]==(void*)original_axis_test);
 slots[2]=add_action;slots[3]=original_axis_test;hook_flags=4;assert(remove_remap());assert(slots[2]==(void*)original_action_test&&!hook_flags);
 VirtualFree(slots,0,MEM_RELEASE);puts("PASS full/partial hook cleanup and refusal to overwrite another hook");return 0;
}
