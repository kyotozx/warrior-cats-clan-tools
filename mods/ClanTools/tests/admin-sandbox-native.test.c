#undef NDEBUG
#include "../native/admin_sandbox.c"
#include <assert.h>

int main(void) {
 /* Captured level-20 state: move listing and attribute reads/edits share
    the XP component, whose next-level threshold is zero at the cap. */
 assert(level_bounds(0,0,20,20));
 assert(!bounds(0,0)); /* Health and stamina must keep a positive maximum. */
 assert(level_bounds(169,500,11,20));
 assert(level_bounds(0,500,20,20));
 /* A successful XP grant can cross from a normal level into capped 0/0.
    Readback must validate the resulting level, not the preview's level. */
 assert(level_bounds(499,500,19,20));
 assert(level_bounds(0,0,20,20));
 assert(!level_bounds(0,0,19,20));
 assert(!level_bounds(1,0,20,20));
 assert(!level_bounds(-1,0,20,20));
 assert(!level_bounds(0,-1,20,20));
 assert(!level_bounds(0,0,0,0));
 assert(!level_bounds(0,0,21,20));
 assert(!level_bounds(0,0,1001,1001));
 assert(!level_bounds(501,500,19,20));
 assert(!level_bounds(0,10000001,20,20));
 const float invalid[]={NAN,INFINITY,-INFINITY};
 for(unsigned i=0;i<sizeof(invalid)/sizeof(invalid[0]);i++) {
  assert(!level_bounds(invalid[i],0,20,20));
  assert(!level_bounds(0,invalid[i],20,20));
  assert(!bounds(invalid[i],100));
  assert(!bounds(0,invalid[i]));
 }
 assert(bounds(0,100));assert(bounds(100,100));
 assert(!bounds(-1,100));assert(!bounds(101,100));
 puts("Native sandbox bounds passed: capped XP, cap transition, invalid levels/resources, strict health/stamina.");
 return 0;
}
