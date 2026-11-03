/* Steam patch 1.2 player settings, as read and written by the native getter and
 * setter: seven flags, mouse camera X/Y, map mouse move/zoom sensitivity and the
 * follow-camera flag (bMovementAffectsCamera) at 0x18. The native rebuild reads
 * it into a 32-byte buffer. Preserve all native fields when toggling controls. */
#include <stddef.h>
#include <math.h>
#include <string.h>
typedef struct {
    unsigned char flags[7];
    unsigned char padding;
    float mouse_x;
    float mouse_y;
    float map_move;
    float map_zoom;
    unsigned char follow_camera;
    unsigned char tail[3];
} PlayerSettings;
_Static_assert(sizeof(PlayerSettings)==28,"Patch 1.2 player settings ABI");
_Static_assert(offsetof(PlayerSettings,mouse_x)==8,"Mouse X offset");
_Static_assert(offsetof(PlayerSettings,mouse_y)==12,"Mouse Y offset");
_Static_assert(offsetof(PlayerSettings,map_move)==16,"Map move offset");
_Static_assert(offsetof(PlayerSettings,map_zoom)==20,"Map zoom offset");
_Static_assert(offsetof(PlayerSettings,follow_camera)==24,"Follow camera offset");
static int player_settings_float(float v){return isfinite(v)&&v>=0&&v<=1000;}
static int player_settings_valid(const PlayerSettings *p) {
    for(unsigned i=0;i<7;i++)if(p->flags[i]>1)return 0;
    return p->follow_camera<=1&&player_settings_float(p->mouse_x)&&player_settings_float(p->mouse_y)&&
        player_settings_float(p->map_move)&&player_settings_float(p->map_zoom);
}
static int player_settings_equal(const PlayerSettings *a,const PlayerSettings *b) {
    return !memcmp(a->flags,b->flags,7)&&a->mouse_x==b->mouse_x&&a->mouse_y==b->mouse_y&&
        a->map_move==b->map_move&&a->map_zoom==b->map_zoom&&a->follow_camera==b->follow_camera;
}
