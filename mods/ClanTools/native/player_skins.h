/* Cosmetic-only skin exchange. Creator commands never call a save writer. */
static const char *skin_values_response(const Custom *data) {
    static char response[512];int32_t v[COSMETIC_COUNT];
    if(!custom_ok(data))return "ERROR Invalid skin data";
    cosmetic_read(data,v);if(!cosmetic_values_ok(v))return "ERROR Unsupported skin values";
    size_t n=(size_t)snprintf(response,sizeof(response),"OK COSMETICS");
    for(unsigned i=0;i<COSMETIC_COUNT;i++)n+=(size_t)snprintf(response+n,sizeof(response)-n," %d",v[i]);
    return response;
}
static const char *player_skin_read(void) {
    Custom data;int ok=read_player(&data,-1);
    const char *r=ok?skin_values_response(&data):"ERROR Load a player character first";
    destroy_custom(&data);return r;
}
static const char *player_skin_refresh(uintptr_t address) {
    void *pawn=(void*)address;
    if(!same_context()||role!=0||!applied||!object_ok(pawn,0x868)||!class_is(pawn,0x1712c80))return "ERROR Invalid player refresh context";
    void *mesh=*(void**)((char*)pawn+0x860);
    if(!object_ok(mesh,0x210))return "ERROR Player mesh unavailable";
    Custom data;int ok=read_player(&data,slot);
    if(ok&&custom_ok(&data))apply_preview(mesh,&data,0);
    destroy_custom(&data);return ok?"OK PLAYER_REFRESHED":"ERROR Player appearance could not reload";
}
static const char *skin_external_command(const char *command,const char *line) {
    unsigned id;char verb[24],tail;unsigned long long address;int used=0;
    if(sscanf(line,"%u %23s %llx %n",&id,verb,&address,&used)!=3||used<=0)return "ERROR Invalid skin request";
    void *cat=(void*)(uintptr_t)address,*creator=NULL,*panel=NULL;
    if(!strcmp(command,"CREATOR_READ")||!strcmp(command,"CREATOR_LOAD")) {
        if(active)return "ERROR Finish the current appearance transaction";
        creator=cat;
        if(!object_ok(creator,0x6a0)||!class_is(creator,0x1853070))return "ERROR Invalid creator screen";
        cat=*(void**)((char*)creator+0x488);
        panel=*(void**)((char*)creator+0x568);int found=0;
        for(unsigned i=0;i<4;i++)if(panel==*(void**)((char*)creator+0x4e8+i*8))found=1;
        if(!found||!object_ok(panel,0x3c8)||*(void**)((char*)panel+0x3b0)!=cat||
           !readable(*(void**)panel,0x580,base,0)||(*(void***)panel)[0x578/8]!=base+0x18c1cb0)
            return "ERROR Creator controls are not initialized";
    }
    if(cat==actor||!object_ok(cat,0x3c8)||!class_is(cat,0x18388c0))return "ERROR Invalid skin preview actor";
    void *mesh=*(void**)((char*)cat+0x2b8);
    if(!object_ok(mesh,0x210)||!custom_ok((Custom*)((char*)mesh+0x118)))return "ERROR Skin preview is unavailable";
    if(!strcmp(command,"CREATOR_READ")) {
        if(sscanf(line+used," %c",&tail)==1)return "ERROR Trailing skin input";
        return skin_values_response((Custom*)((char*)mesh+0x118));
    }
    int32_t v[COSMETIC_COUNT];
    if(!cosmetic_parse(line+used,v)||!cosmetic_assets_ok(v))return "ERROR Invalid skin for this game build";
    Custom edited;copy_custom(&edited,(Custom*)((char*)mesh+0x118));cosmetic_write(&edited,v);
    apply_preview(mesh,&edited,0);destroy_custom(&edited);
    if(panel){cosmetic_sync_controls(creator,cat);((void(*)(void*))(base+0x18c1cb0))(panel);}
    return "OK SKIN_PREVIEW_LOADED";
}
