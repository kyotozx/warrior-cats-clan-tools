/* Isolated JSON fixtures. No live game, installation or saves are accessed. */
#include "../native/appearance_bridge.c"
#undef NDEBUG
#include <assert.h>
typedef struct { uint64_t words[10]; } JsonMap;
typedef struct { uint64_t words[5]; } JsonEntry;
typedef struct { uint64_t words[4]; } JsonValue;
static uint32_t test_hash(int32_t count,const wchar_t *key){assert(count>0&&key);return 0;}
static Str literal(wchar_t *s){Str out={s,(int32_t)wcslen(s)+1,(int32_t)wcslen(s)+1};return out;}
static void field(JsonMap *map,JsonEntry *entry,wchar_t *key,JsonValue *value) {
    memset(map,0,sizeof(*map));memset(entry,0,sizeof(*entry));
    map->words[0]=(uintptr_t)entry;
    *(int32_t*)((char*)map+8)=*(int32_t*)((char*)map+12)=1;
    *(int32_t*)((char*)map+0x48)=1;
    *(Str*)entry=literal(key);entry->words[2]=(uintptr_t)value;
    *(int32_t*)((char*)entry+0x20)=-1;
}
static JsonValue object_value(JsonMap *map) {
    JsonValue out={{0}};out.words[0]=(uintptr_t)(base+0x7ec2390);
    *(int32_t*)((char*)&out+8)=6;out.words[2]=(uintptr_t)map;return out;
}
int main(void) {
    assert(!initialize());base=(unsigned char*)GetModuleHandleW(NULL);generation_key_hash=test_hash;
    wchar_t profile[]=L"ABC0123456789DEF",slot_name[]=L"0",meta_name[]=L"Meta",hash_name[]=L"Hash";
    wchar_t hash_a[]=L"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    wchar_t hash_b[]=L"abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789";
    JsonMap root,profile_map,slot_map,meta_map;JsonEntry entries[4];
    JsonValue values[4]={object_value(&profile_map),object_value(&slot_map),object_value(&meta_map),{{0}}};
    values[3].words[0]=(uintptr_t)(base+0x98dc480);*(int32_t*)((char*)&values[3]+8)=2;
    *(Str*)((char*)&values[3]+0x10)=literal(hash_a);
    field(&root,&entries[0],profile,&values[0]);field(&profile_map,&entries[1],slot_name,&values[1]);
    field(&slot_map,&entries[2],meta_name,&values[2]);field(&meta_map,&entries[3],hash_name,&values[3]);
    JsonMap saved_maps[]={root,profile_map,slot_map,meta_map};JsonEntry saved_entries[4];JsonValue saved_values[4];
    memcpy(saved_entries,entries,sizeof(entries));memcpy(saved_values,values,sizeof(values));
    char a[65]={0},b[65]={0};assert(generation_read_hash(&root,profile,0,a));
    assert(generation_read_hash(&root,L"abc0123456789def",0,b)&&!strcmp(a,b));
    assert(!strcmp(a,"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"));
    assert(!generation_read_hash(&root,L"0000",0,b));assert(!generation_read_hash(&root,profile,1,b));
    assert(!generation_read_hash(&root,profile,-1,b));
    assert(!memcmp(saved_maps,&root,sizeof(root))&&!memcmp(saved_maps+1,&profile_map,sizeof(profile_map)));
    assert(!memcmp(saved_maps+2,&slot_map,sizeof(slot_map))&&!memcmp(saved_maps+3,&meta_map,sizeof(meta_map)));
    assert(!memcmp(saved_entries,entries,sizeof(entries))&&!memcmp(saved_values,values,sizeof(values)));
    meta_name[0]=L'm';hash_name[0]=L'h';assert(generation_read_hash(&root,profile,0,b));
    meta_name[0]=L'M';hash_name[0]=L'H';
    /* Recreating the same slot yields a new identity without profile/slot changes. */
    *(Str*)((char*)&values[3]+0x10)=literal(hash_b);
    assert(generation_read_hash(&root,profile,0,b)&&strcmp(a,b));
    values[3].words[0]=(uintptr_t)(base+0x7ec2530);assert(!generation_read_hash(&root,profile,0,b));
    values[3].words[0]=(uintptr_t)(base+0x98dc480);
    *(int32_t*)((char*)&values[3]+8)=6;assert(!generation_read_hash(&root,profile,0,b));
    *(int32_t*)((char*)&values[3]+8)=2;hash_b[0]=L'Z';assert(!generation_read_hash(&root,profile,0,b));hash_b[0]=L'a';
    ((Str*)((char*)&values[3]+0x10))->count=64;assert(!generation_read_hash(&root,profile,0,b));
    *(Str*)((char*)&values[3]+0x10)=literal(hash_b);
    values[2].words[0]=0;assert(!generation_read_hash(&root,profile,0,b));values[2]=object_value(&meta_map);
    values[2].words[2]=0;assert(!generation_read_hash(&root,profile,0,b));values[2]=object_value(&meta_map);
    /* Missing fields do not insert defaults, cyclic chains and bad indices terminate. */
    *(int32_t*)((char*)&entries[3]+0x20)=0;assert(!generation_json_find(&meta_map,L"Absent"));
    *(int32_t*)((char*)&meta_map+0x38)=10;assert(!generation_json_find(&meta_map,L"Hash"));
    *(int32_t*)((char*)&meta_map+0x38)=0;*(int32_t*)((char*)&meta_map+0x48)=4;
    assert(!generation_json_find(&meta_map,L"Hash"));
    *(int32_t*)((char*)&meta_map+0x48)=1;*(int32_t*)((char*)&meta_map+8)=65537;
    assert(!generation_json_find(&meta_map,L"Hash"));assert(!generation_json_find(NULL,L"Hash"));
    char id[129];Str idstr=literal(profile);assert(generation_hex(&idstr,id,sizeof(id),0));
    profile[0]=L' ';assert(!generation_hex(&idstr,id,sizeof(id),0));
    puts("PASS native existing-generation lookup, exact profile/slot, slot reuse, no JSON writes, invalid field refusal and bounded corrupt chains");
    return 0;
}
