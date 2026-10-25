/* A local harness; no game process or save files are accessed. */
#include "../native/appearance_bridge.c"
#undef NDEBUG
#include <assert.h>
#include <stdlib.h>
static void *test_assign_string(Str *s,const wchar_t *p,int32_t count) {
    wchar_t *copy=calloc((size_t)count+1,2);assert(copy);
    if(count)memcpy(copy,p,(size_t)count*2);free(s->data);
    s->data=copy;s->count=s->capacity=count+1;return s;
}
static void *test_copy(Custom *out,const Custom *in) {
    memcpy(out,in,sizeof(*out));
    for(unsigned i=0;i<6;i++) {
        unsigned off=i<2?0x70+i*16:0x98+(i-2)*16;
        Str *d=(Str*)(out->b+off);const Str *s=(const Str*)(in->b+off);d->data=NULL;
        test_assign_string(d,s->data,s->count?s->count-1:0);
    }return out;
}
static void test_destroy(Custom *p) {
    for(unsigned i=0;i<6;i++) {unsigned off=i<2?0x70+i*16:0x98+(i-2)*16;free(((Str*)(p->b+off))->data);}
}
static void *last_freed;
static void test_free(void *p){last_freed=p;free(p);}
int main(void) {
    assert(!initialize()); /* Refuses the test executable before using RVAs. */
    unsigned char guarded_screen[0x6a0]={0};
    void **owned_vtable=VirtualAlloc(NULL,0x6d8,MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE);
    assert(owned_vtable);base=(unsigned char*)GetModuleHandleW(NULL);
    unsigned char binding[0x28]={0};*(void**)binding=base;
    for(unsigned off=0x4d8;off<=0x538;off+=8)*(void**)(guarded_screen+off)=binding;
    assert(*(void**)(guarded_screen+0x580)==NULL);
    assert(editor_tree_error(guarded_screen)==NULL); /* HoldButtonBack is an output. */
    *(void**)(guarded_screen+0x520)=NULL;
    assert(strstr(editor_tree_error(guarded_screen),"+0x520"));
    *(void**)(guarded_screen+0x520)=binding;
    screen=guarded_screen;screen_index=23;screen_clone=owned_vtable+1;active=1;
    *(void***)guarded_screen=screen_clone;*(int32_t*)(guarded_screen+0xc)=23;
    assert(object_ok(screen,sizeof(guarded_screen)));
    *(int32_t*)(guarded_screen+0xc)=24;assert(!object_ok(screen,sizeof(guarded_screen)));
    *(int32_t*)(guarded_screen+0xc)=23;*(uint32_t*)(guarded_screen+8)=0x10000;
    assert(!object_ok(screen,sizeof(guarded_screen)));
    *(uint32_t*)(guarded_screen+8)=0;active=0;assert(!object_ok(screen,sizeof(guarded_screen)));
    VirtualFree(owned_vtable,0,MEM_RELEASE);screen=NULL;screen_clone=NULL;base=NULL;
    Custom before={0},edited={0},result={0};
    before.b[0]=4;before.b[1]=7;before.b[4]=123;before.b[0x90]=1;
    float size=1.0f;memcpy(before.b+0x94,&size,4);
    test_assign_string((Str*)(before.b+0x70),L"Original",8);
    test_assign_string((Str*)(before.b+0x80),L"feather",7);
    test_assign_string((Str*)(before.b+0x98),L"OldCollar",9);
    test_copy(&edited,&before);edited.b[0]=1;edited.b[1]=2;edited.b[4]=7;edited.b[0x90]=0;
    test_assign_string((Str*)(edited.b+0x70),L"WrongName",9);
    test_assign_string((Str*)(edited.b+0x98),L"Necklace",8);
    *(int32_t*)(edited.b+0x48)=11;*(int32_t*)(edited.b+0x54)=7;
    copy_custom=test_copy;assign_string=test_assign_string;
    merge_appearance(&result,&before,&edited,&before);
    assert(result.b[0]==4&&result.b[1]==7&&result.b[4]==123&&result.b[0x90]==1);
    assert(!wcscmp(((Str*)(result.b+0x70))->data,L"Original"));
    assert(!wcscmp(((Str*)(result.b+0x80))->data,L"feather"));
    assert(!wcscmp(((Str*)(result.b+0x98))->data,L"OldCollar"));
    assert(((Str*)(result.b+0x98))->data!=((Str*)(before.b+0x98))->data);
    assert(*(int32_t*)(result.b+0x48)==11&&*(int32_t*)(result.b+0x54)==7);
    assert(custom_ok(&result));assert(!custom_equal(&before,&result));assert(custom_equal(&result,&result));
    test_destroy(&before);test_destroy(&edited);test_destroy(&result);
    /* A valid NPC Chubby9 is outside the native creator's0..6 body list.
       Simulate constructor normalization plus hidden wardrobe/scar changes. */
    Custom saved={0},initial={0},preview={0},committed={0};
    saved.b[0]=4;saved.b[1]=7;memcpy(saved.b+0x94,&size,4);
    *(int32_t*)(saved.b+0x28)=9;*(int32_t*)(saved.b+0xe8)=3;
    test_assign_string((Str*)(saved.b+0x98),L"OriginalCollar",14);
    test_copy(&initial,&saved);*(int32_t*)(initial.b+0x28)=6;
    *(int32_t*)(initial.b+0x44)=6;*(int32_t*)(initial.b+0xe8)=0;
    test_assign_string((Str*)(initial.b+0x98),L"",0);
    test_copy(&preview,&initial);
    merge_appearance(&committed,&saved,&preview,&initial);
    assert(custom_equal(&committed,&saved)); /* No-input Apply is exact no-op. */
    test_destroy(&committed);
    *(int32_t*)(preview.b+0x5c)=4; /* Explicit eye-only edit. */
    merge_appearance(&committed,&saved,&preview,&initial);
    assert(*(int32_t*)(committed.b+0x28)==9&&*(int32_t*)(committed.b+0x44)==0);
    assert(*(int32_t*)(committed.b+0x5c)==4&&*(int32_t*)(committed.b+0xe8)==3);
    assert(!wcscmp(((Str*)(committed.b+0x98))->data,L"OriginalCollar"));
    test_destroy(&committed);
    *(int32_t*)(preview.b+0x28)=5;*(int32_t*)(preview.b+0x44)=5;
    *(float*)(preview.b+0x94)=2.0f;*(int32_t*)(preview.b+0xe8)=5;
    test_assign_string((Str*)(preview.b+0x98),L"ChangedCollar",13);
    merge_appearance(&committed,&saved,&preview,&initial);
    assert(*(int32_t*)(committed.b+0x28)==5&&*(int32_t*)(committed.b+0x44)==5);
    assert(*(int32_t*)(committed.b+0xe8)==3);
    assert(*(float*)(committed.b+0x94)==1.0f);
    assert(!wcscmp(((Str*)(committed.b+0x98))->data,L"OriginalCollar"));
    test_destroy(&saved);test_destroy(&initial);test_destroy(&preview);test_destroy(&committed);
    unsigned char helper[0x348]={0},saved_camera[0x38];
    EngineArray *queue=(EngineArray*)(helper+0x310);
    queue->data=calloc(2,8);queue->count=1;queue->capacity=2;
    *(float*)(helper+0x320)=1.5f;*(float*)(helper+0x324)=2.5f;
    *(uint64_t*)(helper+0x328)=0x12345678;
    /* Initially unbound weakrefs are legitimate and must restore exactly. */
    memcpy(saved_camera,helper+0x310,sizeof(saved_camera));assert(camera_array_ok(queue,8));
    camera_take_runtime(helper);assert(queue->data==NULL&&queue->count==0);
    assert(*(uint64_t*)(helper+0x328)==0&&*(uint64_t*)(helper+0x340)==0);
    queue->data=calloc(3,8);queue->count=1;queue->capacity=3;
    void *temporary=queue->data;free_engine=test_free;camera_restore_runtime(helper);
    assert(last_freed==temporary&&!memcmp(saved_camera,helper+0x310,sizeof(saved_camera)));free(queue->data);
    EngineArray invalid={0};invalid.count=2;assert(!camera_array_ok(&invalid,8));
    puts("PASS native unsupported-build guard, appearance-only merge, deep string ownership, comparison");
    puts("PASS private camera queue ownership, null weakrefs and exact state restoration");
    puts("PASS owned editor vtable validity, stale index and pending-destruction refusal");
    puts("PASS authored binding guards allow uninitialized HoldButtonBack and report missing fields");
    puts("PASS no-input normalized NPC preservation, eye-only delta, explicit body/fur edit and untouched wardrobe/scars");
    Custom identity={0};memset(identity.b,0x33,sizeof(identity));Custom only_cosmetics=identity;
    int32_t preset[COSMETIC_COUNT]={0},roundtrip[COSMETIC_COUNT]={0};
    for(unsigned i=0;i<COSMETIC_COUNT;i++)preset[i]=(int32_t)i;
    preset[22]=1;preset[23]=1;cosmetic_write(&only_cosmetics,preset);cosmetic_read(&only_cosmetics,roundtrip);
    assert(!memcmp(preset,roundtrip,sizeof(preset)));
    for(unsigned off=0;off<sizeof(Custom);off++) {
        int allowed=(off>=0x0c&&off<0x64)||off==0x64||(off>=0x68&&off<0x6c);
        if(!allowed)assert(identity.b[off]==only_cosmetics.b[off]);
    }
    const char *good="0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 1 1";
    assert(cosmetic_parse(good,preset));assert(!cosmetic_parse("1 2",preset));
    assert(!cosmetic_parse("-1 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 1 1",preset));
    assert(!cosmetic_parse("256 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 1 1",preset));
    assert(!cosmetic_parse("0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 1 1 extra",preset));
    assert(!cosmetic_parse("0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 2 1",preset));
    assert(!cosmetic_parse("0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 1 17",preset));
    comparing_original=1;assert(strstr(capture_preview(),"Return to edited"));assert(strstr(apply_edit(),"Return to edited"));comparing_original=0;
    assert(strstr(cosmetic_compare(1),"ERROR"));assert(strstr(cosmetic_randomize(),"ERROR"));
    puts("PASS cosmetic-only preset byte whitelist, exact schema/ranges and original-comparison commit refusal");
    return 0;
}
