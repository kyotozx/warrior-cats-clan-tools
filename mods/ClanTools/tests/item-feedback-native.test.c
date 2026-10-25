#define ITEM_FEEDBACK_TEST
#undef NDEBUG
#include "../native/item_feedback.c"
#include <assert.h>
static unsigned char invbuf[0x400],actorbuf[0x100],hpbuf[0x130],spbuf[0x130],mapdata[60];
static uintptr_t fakevt[8];static int calls,mode;
static unsigned char turnbuf[0x400];static int queued,resolved;
static void queue_item(void *component,const uint64_t *tag){queued++;if(mode==2){*(int32_t*)(mapdata+8)-=1;*(uint64_t*)((uintptr_t)component+0x370)=*tag;}}
static void resolve_item(void *component){(void)component;resolved++;if(mode==3)*(float*)(hpbuf+0x10c)+=5;}
static void initobject(unsigned char *p,int id){*(uintptr_t*)p=(uintptr_t)fakevt;*(int32_t*)(p+12)=id;}
static uint64_t use(void *p,uint64_t tag,uint8_t apply,int32_t requested){
 assert(p==invbuf);assert(tag==7);assert(requested==1);calls++;
 if(mode==1&&apply){*(int32_t*)(mapdata+8)-=1;*(float*)(hpbuf+0x10c)=100;}
 return 0;
}
int main(void){
 base=(unsigned char*)GetModuleHandleW(NULL);/* object vtable checks need image allocation */
 uintptr_t imagevt=(uintptr_t)base;initobject(invbuf,1);initobject(actorbuf,2);initobject(hpbuf,3);initobject(spbuf,4);
 *(uintptr_t*)invbuf=imagevt;*(uintptr_t*)actorbuf=imagevt;*(uintptr_t*)hpbuf=imagevt;*(uintptr_t*)spbuf=imagevt;
 uintptr_t m=(uintptr_t)invbuf+0x150;*(uintptr_t*)m=(uintptr_t)mapdata;*(int32_t*)(m+8)=3;*(int32_t*)(m+12)=3;*(uint32_t*)(m+0x10)=5;*(int32_t*)(m+0x28)=3;*(int32_t*)(m+0x2c)=128;*(int32_t*)(m+0x34)=1;
 uint64_t tag7=7,tag8=8;memcpy(mapdata,&tag7,8);*(int32_t*)(mapdata+8)=5;memcpy(mapdata+20,&tag7,8);*(int32_t*)(mapdata+28)=999;memcpy(mapdata+40,&tag8,8);*(int32_t*)(mapdata+48)=4;
 int v;assert(item_count((uintptr_t)invbuf,7,&v)&&v==5);assert(item_count((uintptr_t)invbuf,9,&v)&&v==0);
 *(int32_t*)(invbuf+0x25c)=-1;*(float*)(hpbuf+0x10c)=95;*(float*)(hpbuf+0x110)=100;*(float*)(spbuf+0x10c)=20;*(float*)(spbuf+0x110)=50;
 inventory=(uintptr_t)invbuf;inventory_id=1;targets[0]=(Target){(uintptr_t)actorbuf,(uintptr_t)hpbuf,(uintptr_t)spbuf,2,3,4};target_count=1;installed=1;epoch=1;game_thread=GetCurrentThreadId();original=use;mode=1;
 assert(observed_use(invbuf,7,1,1)==0);assert(calls==1&&head==1);assert(queue[0].before==5&&queue[0].after==4);assert(queue[0].targets[0].hp0.current==95&&queue[0].targets[0].hp1.current==100);
 mode=0;observed_use(invbuf,7,1,1);assert(calls==2&&head==2&&queue[1].before==queue[1].after);
 observed_use(invbuf,7,0,1);assert(calls==3&&head==2);*(int32_t*)(invbuf+0x25c)=0;observed_use(invbuf,7,1,1);assert(calls==4&&head==2);
 *(int32_t*)(invbuf+0x25c)=-1;initobject(turnbuf,5);*(uintptr_t*)turnbuf=imagevt;*(uintptr_t*)(turnbuf+0x20)=(uintptr_t)actorbuf;
 original_queue=queue_item;original_resolve=resolve_item;mode=2;unsigned prior=head;
 observed_queue(turnbuf,&tag7);assert(queued==1&&head==prior&&receipts[0].consumed==1);
 *(float*)(hpbuf+0x10c)=80;mode=3;observed_resolve(turnbuf);assert(resolved==1&&head==(prior+1)%QUEUE_SIZE);assert(queue[prior].targets[0].hp0.current==80&&queue[prior].targets[0].hp1.current==85);assert(queue[prior].before-queue[prior].after==1);
 prior=head;observed_resolve(turnbuf);assert(resolved==2&&head==prior);/* duplicate resolution has no receipt */
 mode=0;observed_queue(turnbuf,&tag7);mode=3;observed_resolve(turnbuf);assert(head==prior);/* failed consumption cannot claim a heal */
 mode=2;observed_queue(turnbuf,&tag7);*(uint64_t*)(turnbuf+0x370)=8;mode=3;observed_resolve(turnbuf);assert(head==prior);/* changed action invalidates receipt */
 *(uint32_t*)(turnbuf+8)=0x00010000;mode=2;observed_queue(turnbuf,&tag7);assert(receipts[0].consumed==0);/* dying object bypasses observer */
 *(uint32_t*)(m+0x10)=7;assert(!item_count((uintptr_t)invbuf,7,&v));
 puts("Native item tests passed: sparse map holes, actual delta, blocked, non-use, temporary mode, corruption.");return 0;
}
