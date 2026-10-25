#undef NDEBUG
#include <assert.h>
#include "../native/enemy_cleanup.c"
static unsigned char generator[0x600],enemy[0x900],player[0x900],wrong[0x900],klass[0x30],gklass[0x30];
static Weak entries[3];
static char fake_valid(const Weak*w){return w->serial!=0;}
static void*fake_get(const Weak*w){return w->index==1?enemy:w->index==2?player:wrong;}
int main(void){
    *(void**)(generator+0x10)=gklass;*(void**)(enemy+0x10)=klass;*(void**)(wrong+0x10)=gklass;
    *(void**)(enemy+0x888)=generator;
    WeakArray a={entries,1,3};memcpy(generator+0x3c8,&a,sizeof(a));entries[0]=(Weak){1,1};
    int total,live;assert(!check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live)&&total==1&&live==1);
    entries[0]=(Weak){2,1};assert(strstr(check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live),"protected player"));
    entries[0]=(Weak){3,1};assert(strstr(check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live),"unexpected actor class"));
    entries[0]=(Weak){1,0};assert(!check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live)&&live==0);
    entries[0]=(Weak){1,1};*(void**)(enemy+0x888)=NULL;assert(strstr(check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live),"ownership"));
    a.count=129;memcpy(generator+0x3c8,&a,sizeof(a));assert(strstr(check_array(generator,gklass,player,klass,fake_valid,fake_get,&total,&live),"array"));
    assert(!build_functions(NULL,NULL));puts("PASS enemy cleanup native ownership guards (6 cases)");return 0;
}
