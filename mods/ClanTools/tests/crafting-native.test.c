#ifdef NDEBUG
#undef NDEBUG
#endif
#include "../native/crafting.c"
#include <assert.h>
static unsigned char actorbuf[0x400],levelbuf[0xd0],worldbuf[0x40],otherworld[0x40];static uintptr_t fakevt[256];static unsigned stage=1,calls;static int expected;
static unsigned char fake_state(void *a){assert(a==actorbuf);return (unsigned char)stage;}
static void progress(void *a){assert(a==actorbuf);assert(*(int32_t*)(actorbuf+0x3a0)==expected);calls++;if(expected<=100)stage=3;}
int main(void){
 base=(unsigned char*)((uintptr_t)fakevt-0x9b49b28);*(uintptr_t*)actorbuf=(uintptr_t)fakevt;*(int32_t*)(actorbuf+12)=9;*(uint64_t*)(actorbuf+0x2f0)=42;*(int32_t*)(actorbuf+0x3f0)=-1;*(int32_t*)(actorbuf+0x3a0)=14400;
 *(uintptr_t*)(actorbuf+0x20)=(uintptr_t)levelbuf;*(uintptr_t*)(levelbuf+0xc0)=(uintptr_t)worldbuf;*(int32_t*)(levelbuf+12)=2;*(int32_t*)(worldbuf+12)=3;
 projects[0]=(Project){.actor=(uintptr_t)actorbuf,.id=9};assert(level_world((uintptr_t)actorbuf,&projects[0]));count=1;installed=1;game_thread=GetCurrentThreadId();original=progress;state=fake_state;
 speed=2;expected=7200;observed(actorbuf);assert(calls==1&&stage==1&&*(int32_t*)(actorbuf+0x3a0)==14400);
 speed=0;expected=0;observed(actorbuf);assert(calls==2&&stage==3&&*(int32_t*)(actorbuf+0x3a0)==14400);
 expected=14400;observed(actorbuf);assert(calls==3);stage=1;speed=1;observed(actorbuf);assert(calls==4);
 speed=10;*(int32_t*)(actorbuf+12)=10;observed(actorbuf);assert(calls==5);assert(*(int32_t*)(actorbuf+0x3a0)==14400);
 *(int32_t*)(actorbuf+12)=9;assert(known((uintptr_t)actorbuf));*(uintptr_t*)(levelbuf+0xc0)=(uintptr_t)otherworld;assert(!known((uintptr_t)actorbuf));observed(actorbuf);assert(calls==6);
 *(uintptr_t*)(levelbuf+0xc0)=(uintptr_t)worldbuf;*(int32_t*)(worldbuf+12)=4;assert(!known((uintptr_t)actorbuf));*(int32_t*)(worldbuf+12)=3;assert(known((uintptr_t)actorbuf));
 *(uint32_t*)(actorbuf+8)=0x10000;assert(!known((uintptr_t)actorbuf));*(uint32_t*)(actorbuf+8)=0;*(uint32_t*)(levelbuf+8)=0x40000000;assert(!known((uintptr_t)actorbuf));
 *(uint32_t*)(levelbuf+8)=0;*(uintptr_t*)actorbuf=(uintptr_t)(base+0x9c4e190);assert(known((uintptr_t)actorbuf));
 void**table=VirtualAlloc(NULL,4096,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);assert(table);slots[0]=table;slots[1]=table+1;table[0]=observed;table[1]=observed;hook_flags=3;assert(restore_hooks());assert(table[0]==(void*)original&&table[1]==(void*)original&&!hook_flags);
 table[0]=observed;hook_flags=1;assert(restore_hooks());assert(!hook_flags);table[0]=original;hook_flags=1;assert(!restore_hooks());table[0]=observed;assert(restore_hooks());VirtualFree(table,0,MEM_RELEASE);
 puts("PASS base/Wrc subclass ownership and both full/partial progress-hook restoration");
 puts("Native crafting tests passed: duration scaling/restoration, real completion, stale actor/level/world identities and destroyed-object refusal.");return 0;
}
