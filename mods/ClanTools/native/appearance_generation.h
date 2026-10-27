/* Read the existing character generation without invoking JSON getters: those
 * getters insert missing profile, slot, Meta and Hash fields. Layouts are from
 * the guarded GetProfileData/GetJsonRoot, map lookup and JSON constructors.
 * Called synchronously on the game thread by the Lua controller. */
static uint32_t (*generation_key_hash)(int32_t,const wchar_t*);
static const char *generation_stage;
static char generation_failure[128];
static int generation_key_equal(const wchar_t *a,const wchar_t *b,size_t length) {
    /* TMap's guarded FString comparison folds ASCII case, just like its hash. */
    for(size_t i=0;i<length;i++) {
        wchar_t x=a[i],y=b[i];
        if(x>=L'a'&&x<=L'z')x-=L'a'-L'A';
        if(y>=L'a'&&y<=L'z')y-=L'a'-L'A';
        if(x!=y)return 0;
    }
    return 1;
}

static void *generation_json_find(void *object,const wchar_t *key) {
    unsigned char *map=object;
    strcpy(generation_failure,"map unavailable");
    if(!readable(map,0x50,NULL,0)||!key||!generation_key_hash)return NULL;
    size_t length=wcslen(key);if(!length||length>128)return NULL;
    int32_t count=*(int32_t*)(map+8),capacity=*(int32_t*)(map+12);
    int32_t free_count=*(int32_t*)(map+0x34),hash_count=*(int32_t*)(map+0x48);
    snprintf(generation_failure,sizeof(generation_failure),"map bounds count=%d capacity=%d free=%d buckets=%d",count,capacity,free_count,hash_count);
    if(count<=0||count>65536||capacity<count||free_count<0||free_count>=count||
       hash_count<=0||hash_count>65536||(hash_count&(hash_count-1)))return NULL;
    unsigned char *entries=*(unsigned char**)map;
    int32_t *buckets=*(int32_t**)(map+0x40);
    if(!buckets){if(hash_count>2){strcpy(generation_failure,"inline bucket bounds");return NULL;}buckets=(int32_t*)(map+0x38);}
    strcpy(generation_failure,"map storage unavailable");
    if(!readable(entries,(size_t)count*0x28,NULL,0)||
       !readable(buckets,(size_t)hash_count*4,NULL,0))return NULL;
    uint32_t hash=generation_key_hash((int32_t)length,key);
    int32_t index=buckets[hash&(uint32_t)(hash_count-1)];
    strcpy(generation_failure,"field absent");
    /* Corrupt cycles and stale indices must fail, never hang the game thread. */
    for(int32_t visited=0;index!=-1&&visited<count;visited++) {
        if(index<0||index>=count){strcpy(generation_failure,"chain index invalid");return NULL;}
        unsigned char *entry=entries+(size_t)index*0x28;
        Str *name=(Str*)entry;
        if(!string_ok(name)){strcpy(generation_failure,"field name invalid");return NULL;}
        if(name->count==(int32_t)length+1&&generation_key_equal(name->data,key,length))
            return *(void**)(entry+0x10);
        index=*(int32_t*)(entry+0x20);
    }
    return NULL;
}
static void *generation_json_child(void *object,const wchar_t *key) {
    unsigned char *value=generation_json_find(object,key);
    if(!value)return NULL;
    if(!readable(value,0x20,NULL,0)){strcpy(generation_failure,"object value unavailable");return NULL;}
    if(*(void**)value!=base+0x7ec2390||*(int32_t*)(value+8)!=6){
        strcpy(generation_failure,"unsupported JSON object representation");return NULL;
    }
    return *(void**)(value+0x10);
}
static int generation_hex(const Str *s,char *out,size_t capacity,size_t exact) {
    if(!string_ok(s)||s->count<2||(size_t)s->count>capacity||
       (exact&&(size_t)s->count!=exact+1))return 0;
    for(int32_t i=0;i<s->count-1;i++) {
        wchar_t ch=s->data[i];
        if(!((ch>=L'0'&&ch<=L'9')||(ch>=L'a'&&ch<=L'f')||(ch>=L'A'&&ch<=L'F')))return 0;
        out[i]=(char)ch;
    }
    out[s->count-1]=0;return 1;
}
static int generation_read_hash(void *root,const wchar_t *profile,int32_t selected,char out[65]) {
    if(selected<0)return 0;
    wchar_t slot_key[16];swprintf(slot_key,16,L"%d",selected);
    generation_stage="profile";
    void *profile_json=generation_json_child(root,profile);
    if(!profile_json)return 0;
    generation_stage="slot";
    void *slot_json=generation_json_child(profile_json,slot_key);
    if(!slot_json)return 0;
    generation_stage="Meta";
    void *meta=generation_json_child(slot_json,L"Meta");
    if(!meta)return 0;
    generation_stage="Hash";
    unsigned char *value=generation_json_find(meta,L"Hash");
    if(!value)return 0;
    if(!readable(value,0x20,NULL,0)){strcpy(generation_failure,"string value unavailable");return 0;}
    /* The loaded save uses FJsonValueString's UTF-16 implementation. Other
       type-2 vtables can store a different string encoding; do not reinterpret. */
    if(*(void**)value!=base+0x98dc480||*(int32_t*)(value+8)!=2){
        strcpy(generation_failure,"unsupported JSON string representation");return 0;
    }
    snprintf(generation_failure,sizeof(generation_failure),"hash format length=%d",((Str*)(value+0x10))->count-1);
    return generation_hex((Str*)(value+0x10),out,65,64);
}
typedef struct {
    void *manager,*save,*config,*root;
    int32_t profile_index,slot;
    wchar_t profile[129];char profile_ascii[129];
} GenerationContext;
static int generation_context(GenerationContext *out) {
    memset(out,0,sizeof(*out));
    out->manager=*(void**)(base+0xa8a6e30);
    if(!object_ok(out->manager,0x170))return 0;
    out->save=*(void**)((char*)out->manager+0x168);
    if(!object_ok(out->save,0xa0)||!current_character_slot(&out->config,&out->slot))return 0;
    out->profile_index=*(int32_t*)((char*)out->save+0x78);
    int32_t count=*(int32_t*)((char*)out->save+0x70);
    Str *profiles=*(Str**)((char*)out->save+0x68);
    if(count<=0||count>128||out->profile_index<0||out->profile_index>=count||
       !readable(profiles,(size_t)count*sizeof(Str),NULL,0))return 0;
    Str *id=&profiles[out->profile_index];
    if(!generation_hex(id,out->profile_ascii,sizeof(out->profile_ascii),0))return 0;
    memcpy(out->profile,id->data,(size_t)id->count*2);
    /* GetJsonRoot(USwtSaveGame*) returns &save->Root at +0x90. The
       SaveManager +0x158 object is only a fallback when no save exists. */
    out->root=*(void**)((char*)out->save+0x90);
    return readable(out->root,0x50,NULL,0);
}
static const char *character_generation(void) {
    static char response[256];GenerationContext before,after;char hash[65];
    if(!generation_context(&before))return "ERROR Character generation context unavailable";
    if(!generation_read_hash(before.root,before.profile,before.slot,hash)) {
        snprintf(response,sizeof(response),"ERROR Character generation %s: %s",generation_stage,generation_failure);return response;
    }
    if(!generation_context(&after)||before.manager!=after.manager||before.save!=after.save||
       before.config!=after.config||before.root!=after.root||before.profile_index!=after.profile_index||
       before.slot!=after.slot||strcmp(before.profile_ascii,after.profile_ascii))
        return "ERROR Character generation context changed";
    snprintf(response,sizeof(response),"OK GENERATION profile=%s slot=%d hash=%s",before.profile_ascii,before.slot,hash);
    return response;
}
