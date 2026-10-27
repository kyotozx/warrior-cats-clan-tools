/* Steam patch 1.1 adds a seventh flag and two mouse sensitivity floats.
 * Preserve all native fields when toggling custom controls. */
#include <stddef.h>
#include <math.h>
#include <string.h>
typedef struct {
    unsigned char flags[7];
    unsigned char padding;
    float mouse_x;
    float mouse_y;
} PlayerSettings;
_Static_assert(sizeof(PlayerSettings)==16,"Patch 1.1 player settings ABI");
_Static_assert(offsetof(PlayerSettings,mouse_x)==8,"Mouse X offset");
_Static_assert(offsetof(PlayerSettings,mouse_y)==12,"Mouse Y offset");
static int player_settings_valid(const PlayerSettings *p) {
    for(unsigned i=0;i<7;i++)if(p->flags[i]>1)return 0;
    return isfinite(p->mouse_x)&&isfinite(p->mouse_y)&&
        p->mouse_x>=0&&p->mouse_x<=1000&&p->mouse_y>=0&&p->mouse_y<=1000;
}
static int player_settings_equal(const PlayerSettings *a,const PlayerSettings *b) {
    return !memcmp(a->flags,b->flags,7)&&a->mouse_x==b->mouse_x&&a->mouse_y==b->mouse_y;
}
