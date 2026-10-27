/* Included after preview_valid(). No name, rank, stats, size or wardrobe fields
 * cross this interface. The decimal vector is an explicit 24-field schema. */
#include <stdlib.h>
#include <errno.h>
#include <ctype.h>
enum { COSMETIC_COUNT=24 };
static int comparing_original;
static Custom compared_edit;
static int cosmetic_offset(unsigned i) { return i<22?(int)(0x0c+i*4):i==22?0x64:0x68; }
static void cosmetic_read(const Custom *c,int32_t values[COSMETIC_COUNT]) {
    for(unsigned i=0;i<COSMETIC_COUNT;i++) {
        if(i==22)values[i]=c->b[0x64];
        else memcpy(values+i,c->b+cosmetic_offset(i),4);
    }
}
static void cosmetic_write(Custom *c,const int32_t values[COSMETIC_COUNT]) {
    for(unsigned i=0;i<COSMETIC_COUNT;i++) {
        if(i==22)c->b[0x64]=(unsigned char)values[i];
        else memcpy(c->b+cosmetic_offset(i),values+i,4);
    }
}
static int cosmetic_values_ok(const int32_t v[COSMETIC_COUNT]) {
    /* NPC shapes can exceed the creator's slider maxima (e.g. BodyValue=9).
       Keep the NPC range, while rejecting negative/overflowed asset indices. */
    for(unsigned i=0;i<22;i++)if(v[i]<0||v[i]>255)return 0;
    return (v[22]==0||v[22]==1)&&v[23]>=0&&v[23]<=16;
}
static int cosmetic_parse(const char *text,int32_t values[COSMETIC_COUNT]) {
    if(!text)return 0;
    for(unsigned i=0;i<COSMETIC_COUNT;i++) {
        while(isspace((unsigned char)*text))text++;
        if(!isdigit((unsigned char)*text))return 0;
        errno=0;char *end;long n=strtol(text,&end,10);
        if(errno||end==text||n<0||n>255)return 0;
        values[i]=(int32_t)n;text=end;
        if(i+1<COSMETIC_COUNT&&!isspace((unsigned char)*text))return 0;
    }
    while(isspace((unsigned char)*text))text++;
    return !*text&&cosmetic_values_ok(values);
}
static const char *preview_library_error(void) {
    if(!same_context()||applied||cancelled||!preview_valid()||!have_editor_baseline)
        return "ERROR No initialized appearance preview";
    if(!object_ok(screen,0x6a0)||*(int32_t*)((char*)screen+0xc)!=screen_index||
       *(void**)((char*)screen+0x488)!=actor)return "ERROR Appearance screen changed";
    return NULL;
}
static int panel_methods(void **panels,void **refresh,void **randomize) {
    /* The native creator's command27 uses these exact four v580 callbacks.
       Each panel must still refer to our owned preview. */
    if(!object_ok(screen,0x6a0)||*(int32_t*)((char*)screen+0xc)!=screen_index||!preview_valid())return 0;
    static const unsigned random_rvas[]={0x18c27e0,0x18c34f0,0x18c4050,0x18c4d50};
    void *current=*(void**)((char*)screen+0x568);int found=0;
    for(unsigned i=0;i<4;i++) {
        void *p=*(void**)((char*)screen+0x4e8+i*8);
        if(!object_ok(p,0x3c8)||*(void**)((char*)p+0x3b0)!=actor)return 0;
        void **v=*(void***)p;
        if(!readable(v,0x588,base,0)||!readable(v[0x578/8],1,base,1)||!readable(v[0x580/8],1,base,1))return 0;
        if(v[0x578/8]!=base+0x18c23b0||v[0x580/8]!=base+random_rvas[i])return 0;
        panels[i]=p;refresh[i]=v[0x578/8];randomize[i]=v[0x580/8];
        if(p==current)found=1;
    }
    return found;
}
static int refresh_current_panel(void) {
    void *panels[4],*refresh[4],*randomize[4];
    if(!panel_methods(panels,refresh,randomize))return 0;
    void *current=*(void**)((char*)screen+0x568);
    for(unsigned i=0;i<4;i++)if(current==panels[i]) {
        ((void(*)(void*))refresh[i])(panels[i]);return 1;
    }
    return 0;
}
static int cosmetic_assets_ok(const int32_t *v) {
    void *gui=*(void**)(base+0xa8a6e18);
    if(!object_ok(gui,0x9b0))return 0;
    /* The material setters copy and bounds-check these same arrays. Reject
       out-of-range preset colors before the native renderer can normalize. */
    const unsigned fields[]={15,16,17,20,21};
    const unsigned arrays[]={0x288,0x2a8,0x298,0x2b8,0x2b8};
    for(unsigned i=0;i<5;i++) {
        EngineArray *a=(EngineArray*)((char*)gui+arrays[i]);
        if(!camera_array_ok(a,4)||v[fields[i]]>=a->count)return 0;
    }
    EngineArray *tails=(EngineArray*)((char*)gui+0x2c8),*fur=(EngineArray*)((char*)gui+0x2f8);
    if(!camera_array_ok(tails,0x28)||!camera_array_ok(fur,0x28)||v[12]>=tails->count||v[14]>=fur->count)return 0;
    /* Pattern/marking identifiers come from the loaded native catalog, not
       arbitrary positions in a user-authored vector. */
    for(unsigned i=0;i<2;i++) {
        EngineArray *a=(EngineArray*)((char*)gui+0x970+i*0x10);
        if(!camera_array_ok(a,4))return 0;
        int found=v[18+i]==0;for(int j=0;j<a->count;j++)if(((int32_t*)a->data)[j]==v[18+i])found=1;
        if(!found)return 0;
    }
    return 1;
}
static const char *cosmetic_export(int use_original) {
    static char response[512];const char *error=preview_library_error();if(error)return error;
    const Custom *data=use_original?&original:comparing_original?&compared_edit:
        (Custom*)((char*)*(void**)((char*)actor+0x2b8)+0x118);
    if(!custom_ok(data))return "ERROR Invalid cosmetic preview";
    int32_t values[COSMETIC_COUNT];cosmetic_read(data,values);
    if(!cosmetic_values_ok(values))return "ERROR Cosmetic preset is outside this build's supported range";
    size_t n=(size_t)snprintf(response,sizeof(response),"OK COSMETICS");
    for(unsigned i=0;i<COSMETIC_COUNT;i++)n+=(size_t)snprintf(response+n,sizeof(response)-n," %d",values[i]);
    return response;
}
/* Synchronize the native selectors after an imported preview. The panel's
   v578 callback refreshes navigation, not the values shown by its controls. */
static int cosmetic_sync_controls(void *editor,void *preview) {
    if(!object_ok(editor,0x6a0)||!object_ok(preview,0x3c8))return 0;
    void *mesh=*(void**)((char*)preview+0x2b8);
    if(!object_ok(mesh,0x210)||!custom_ok((Custom*)((char*)mesh+0x118)))return 0;
    void *nature=*(void**)((char*)editor+0x4e8),*colors=*(void**)((char*)editor+0x500);
    if(!object_ok(nature,0x410)||!object_ok(colors,0x408))return 0;
    void *options[6],*color_options[5];void *setters[6];
    static const unsigned color_offsets[]={0x3c8,0x3d0,0x3d8,0x3e0,0x3f8};
    for(unsigned i=0;i<6;i++) {
        options[i]=*(void**)((char*)nature+0x3c8+i*8);
        if(!object_ok(options[i],0x538)||!readable(*(void**)options[i],0x5e0,base,0))return 0;
        setters[i]=(*(void***)options[i])[0x5d8/8];
        if(!readable(setters[i],1,base,1)||!camera_array_ok((EngineArray*)((char*)options[i]+0x460),8))return 0;
    }
    for(unsigned i=0;i<5;i++){color_options[i]=*(void**)((char*)colors+color_offsets[i]);if(!object_ok(color_options[i],0x490))return 0;}
    Custom keep;copy_custom(&keep,(Custom*)((char*)mesh+0x118));int32_t v[COSMETIC_COUNT];cosmetic_read(&keep,v);
    int indices[]={v[7]-v[0],v[9]-v[2],0,0,v[10]-v[5],v[8]-v[1]};
    indices[2]=((int(*)(const void*))(base+0x17b44f0))(keep.b+0x3c)-v[3];
    indices[3]=((int(*)(const void*))(base+0x17b45e0))(keep.b+0x40)-v[4];
    for(unsigned i=0;i<6;i++){
        int count=*(int*)((char*)options[i]+0x468),index=indices[i];
        if(count>0){if(index<0)index=0;if(index>=count)index=count-1;((void(*)(void*,int))setters[i])(options[i],index);}
    }
    static const unsigned color_values[]={15,16,17,20,21};
    for(unsigned i=0;i<5;i++)((void(*)(void*,int))(base+0x18c1c80))(color_options[i],v[color_values[i]]);
    for(unsigned k=0;k<2;k++) {
        void *p=*(void**)((char*)editor+0x4f0+k*8);
        if(!object_ok(p,0x430))continue;
        void *grid=*(void**)((char*)p+0x418);
        if(!object_ok(grid,0x3e0))continue;
        EngineArray *items=(EngineArray*)((char*)grid+0x3d0);
        void *nav=*(void**)((char*)grid+0x3c8);
        if(!camera_array_ok(items,8)||!object_ok(nav,0xa8)||!readable(*(void**)nav,0x308,base,0))continue;
        void *select=(*(void***)nav)[0x300/8];int columns=*(int*)((char*)nav+0xa0);
        if(!readable(select,1,base,1)||columns<1||columns>128)continue;
        for(int i=0;i<items->count;i++) {
            void *item=((void**)items->data)[i];unsigned offset=k?0x420:0x428;
            if(object_ok(item,offset+4)&&*(int*)((char*)item+offset)==v[18+k]) {
                ((void(*)(void*,unsigned char,int,int))select)(nav,1,i/columns,i%columns);
                *(int*)((char*)p+0x428)=v[18+k];break;
            }
        }
    }
    void *design=*(void**)((char*)colors+0x3e8);
    if(object_ok(design,0x490)&&readable(*(void**)design,0x5b8,base,0)) {
        void *select=(*(void***)design)[0x5b0/8];
        if(readable(select,1,base,1))((void(*)(void*,int))select)(design,v[23]);
    }
    /* UI setters must never become a cosmetic mutation or an implicit save. */
    apply_preview(mesh,&keep,0);destroy_custom(&keep);return 1;
}
static const char *cosmetic_import(const char *text) {
    const char *error=preview_library_error();if(error)return error;
    if(comparing_original)return "ERROR Return to edited preview before loading a preset";
    int32_t values[COSMETIC_COUNT];if(!cosmetic_parse(text,values)||!cosmetic_assets_ok(values))return "ERROR Invalid cosmetic preset for this build";
    void *panels[4],*refresh[4],*randomize[4];if(!panel_methods(panels,refresh,randomize))return "ERROR Editor panels are unavailable";
    Custom edited;copy_custom(&edited,(Custom*)((char*)*(void**)((char*)actor+0x2b8)+0x118));
    cosmetic_write(&edited,values);apply_preview(*(void**)((char*)actor+0x2b8),&edited,0);destroy_custom(&edited);cosmetic_force_all=1;
    cosmetic_sync_controls(screen,actor);refresh_current_panel();return "OK PREVIEW_LOADED";
}
static const char *cosmetic_compare(int show_original) {
    const char *error=preview_library_error();if(error)return error;
    if(show_original!=0&&show_original!=1)return "ERROR Invalid comparison mode";
    if(show_original==comparing_original)return show_original?"OK COMPARING_ORIGINAL":"OK EDITED_PREVIEW";
    void *component=*(void**)((char*)actor+0x2b8);
    if(show_original) {
        copy_custom(&compared_edit,(Custom*)((char*)component+0x118));comparing_original=1;
        apply_preview(component,&original,0);
    }else {
        apply_preview(component,&compared_edit,0);destroy_custom(&compared_edit);
        memset(&compared_edit,0,sizeof(compared_edit));comparing_original=0;cosmetic_sync_controls(screen,actor);refresh_current_panel();
    }
    return show_original?"OK COMPARING_ORIGINAL":"OK EDITED_PREVIEW";
}
static const char *cosmetic_randomize(void) {
    const char *error=preview_library_error();if(error)return error;
    if(comparing_original)return "ERROR Return to edited preview before randomizing";
    void *panels[4],*refresh[4],*randomize[4];if(!panel_methods(panels,refresh,randomize))return "ERROR Editor panels are unavailable";
    for(unsigned i=0;i<6;i++) {
        void *control=*(void**)((char*)panels[0]+0x3c8+i*8);
        if(!object_ok(control,0x470))return "ERROR Nature options are not initialized";
        EngineArray *options=(EngineArray*)((char*)control+0x460);
        if(!camera_array_ok(options,8)||options->count<2)return "ERROR Nature randomizer needs at least two choices";
    }
    for(unsigned i=1;i<3;i++) {
        void *grid=*(void**)((char*)panels[i]+0x418);
        if(!object_ok(grid,0x3d0))return "ERROR Pattern grid is not initialized";
        void *nav=*(void**)((char*)grid+0x3c8);
        if(!object_ok(nav,0xa8))return "ERROR Pattern navigation is not initialized";
        void *rows=*(void**)((char*)nav+0x98);int columns=*(int*)((char*)nav+0xa0);
        if(!readable(rows,12,NULL,0)||columns<1||columns>128||*(int*)((char*)rows+8)<1||*(int*)((char*)rows+8)>128||
           columns*(*(int*)((char*)rows+8))<2)return "ERROR Pattern randomizer needs at least two choices";
    }
    for(unsigned i=0;i<7;i++)if(!object_ok(*(void**)((char*)panels[3]+0x3c8+i*8),0x490))return "ERROR Color options are not initialized";
    /* Match the original four-panel action, without changing the active tab.
       Restore every non-cosmetic field even if a native panel normalizes it. */
    void *component=*(void**)((char*)actor+0x2b8);Custom before,edited;
    copy_custom(&before,(Custom*)((char*)component+0x118));
    for(unsigned i=0;i<4;i++)((void(*)(void*))randomize[i])(panels[i]);
    copy_custom(&edited,(Custom*)((char*)component+0x118));
    int32_t values[COSMETIC_COUNT];cosmetic_read(&edited,values);destroy_custom(&edited);
    if(!cosmetic_values_ok(values)) {apply_preview(component,&before,0);destroy_custom(&before);return "ERROR Native randomizer returned unsupported values";}
    cosmetic_write(&before,values);apply_preview(component,&before,0);destroy_custom(&before);
    refresh_current_panel();return "OK RANDOMIZED_PREVIEW";
}
static void cosmetic_release(void) {
    if(comparing_original)destroy_custom(&compared_edit);
    memset(&compared_edit,0,sizeof(compared_edit));comparing_original=0;
}
