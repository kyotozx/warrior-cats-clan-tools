#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <stdio.h>
#include <stdint.h>
#include "../native/player_settings_layout.h"
int main(void) {
    struct {PlayerSettings player;uint64_t sentinel;} buffer={0};
    buffer.sentinel=UINT64_C(0x0123456789abcdef);
    /* Model the native getter's full 16-byte write, including both floats. */
    const unsigned char native[16]={0,1,0,1,0,1,1,0,0,0,128,62,0,0,64,63};
    memcpy(&buffer.player,native,sizeof native);
    assert(buffer.sentinel==UINT64_C(0x0123456789abcdef));
    assert(player_settings_valid(&buffer.player));
    PlayerSettings desired=buffer.player;desired.flags[0]=1;
    assert(desired.mouse_x==.25f&&desired.mouse_y==.75f&&desired.flags[6]==1);
    PlayerSettings after=desired;after.padding=255;
    assert(player_settings_equal(&after,&desired));
    after.mouse_y=.5f;assert(!player_settings_equal(&after,&desired));
    after=desired;after.flags[6]=0;assert(!player_settings_equal(&after,&desired));
    after=desired;after.flags[6]=2;assert(!player_settings_valid(&after));
    after=desired;after.mouse_x=NAN;assert(!player_settings_valid(&after));
    puts("PASS patch 1.1 settings capacity, flag and sensitivity preservation");
    return 0;
}
