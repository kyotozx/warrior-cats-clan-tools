local M=dofile('mods/ClanTools/Scripts/appearance_editor.lua')
local function object(fields)
    fields=fields or{}
    fields.IsValid=function()return true end
    fields.GetAddress=function()return fields.address or 100 end
    return fields
end
local function scenario(failAt)
    local calls={};local function record(s)calls[#calls+1]=s end
    local view=object();local pc=object({GetViewTarget=function()return view end,
        SetViewTargetWithBlend=function(_,v)assert(v==view);record('restoreView')end})
    local world=object({address=200})
    local reference=object({ActorHasTag=function(_,t)return t=='InventoryCat'end,GetTransform=function()return{}end,GetWorld=function()return world end})
    local actor=object({ActorHasTag=function(self,t)return self.Tags[1]==t end,
        SetActorEnableCollision=function()end,ForceBestLOD=function()end,TurnOnExtraLight=function()end,
        PlayMontageSit=function()end,K2_DestroyActor=function()record('destroy')end})
    local widget=object({SetVisibility=function()end,AddToViewport=function()record('viewport')end,
        RemoveFromParent=function()record('remove')end})
    local helper=object({ActorHasTag=function(_,t)return t=='SelectCatCamHelper'end,GetWorld=function()return world end});local gui=object({CatCustomClass=object()})
    local gameplay={BeginDeferredActorSpawnFromClass=function()record('spawn');return actor end,
        FinishSpawningActor=function()end}
    function StaticFindObject(path)
        if path:find('Default__KismetSystemLibrary',1,true)then return{CallFunction=function(_,_,o)return not o.dead end}end
        if path:find('GameplayStatics',1,true)then return gameplay end
        if path:find('WidgetBlueprintLibrary',1,true)then return{Create=function()record('create');return widget end}end
        return{}
    end
    function FindFirstOf(class)if class=='WrcGuiManager'then return gui end;return helper end
    function FindAllOf(class)if class=='WrcCameraViewHelper'then return{helper}end;return{reference}end
    function LoadAsset()return object()end
    function FName(s)return s end
    local callbacks={}
    for _,key in ipairs({'ready','cameraReady','initializeScreen','screenReady','detachScreen','closed'})do
        callbacks[key]=function()record(key);if key==failAt then return nil,'injected failure'end;return true end
    end
    local ctx={valid=function(o)return o and o.IsValid and o:IsValid()and not o.dead end,
        snapshot=function()return{offline=true,pawn=object(),pc=pc,gameState=object()}end,
        attachAppearanceControls=function()record('controls');return{close=function()record('controlsClose')end}end}
    ctx.appearanceCameraFactory={new=function()return {
        prepare=function()record('prepareCameras')end,attach=function()record('attachCameras')end,
        restore=function()record('restoreCameras')end,release=function()record('releaseCameras')end}
    end}
    ctx.appearancePresentationFactory={new=function()return{
        open=function()record('presentationOpen')end,tick=function()record('presentationTick')end,
        restore=function(_,_,final)record(final and 'presentationRelease'or'presentationRestore')end}
    end}
    ctx.appearanceRotationFactory={new=function()return{start=function()record('rotationStart')end,stop=function()record('rotationStop')end}end}
    local api=M.new(ctx)
    return api,callbacks,calls,actor,reference
end
local function index(t,s)for i,v in ipairs(t)do if v==s then return i end end end
do
    local api,cb,calls=scenario();local h=assert(api:open({role=77},cb))
    assert(index(calls,'ready')<index(calls,'create'))
    assert(index(calls,'cameraReady')<index(calls,'initializeScreen'))
    assert(index(calls,'prepareCameras')<index(calls,'cameraReady'))
    assert(index(calls,'attachCameras')<index(calls,'initializeScreen'))
    assert(index(calls,'screenReady')<index(calls,'viewport'))
    assert(index(calls,'viewport')<index(calls,'initializeScreen'))
    api:tick();assert(index(calls,'presentationTick'))
    assert(api:close(h));assert(not index(calls,'destroy'))
    assert(index(calls,'detachScreen')<index(calls,'remove'))
    assert(index(calls,'remove')<index(calls,'closed'))
    api:release(h);assert(index(calls,'closed')<index(calls,'destroy'))
    assert(index(calls,'presentationRestore')<index(calls,'closed'))
    assert(index(calls,'closed')<index(calls,'presentationRelease'))
    assert(api:state()==nil);print('PASS guarded initialization and delayed ownership release')
end
do
    local api,cb,calls=scenario('screenReady');assert(not api:open({role=77},cb))
    assert(not index(calls,'viewport'));assert(not index(calls,'initializeScreen'))
    assert(api:close(nil));api:release(nil)
    print('PASS transition guard failure refuses to mount the native editor')
end
do
    local api,cb,calls=scenario('initializeScreen');assert(not api:open({role=77},cb))
    assert(api:close(nil));assert(not index(calls,'destroy'))
    api:release(nil);assert(index(calls,'destroy'));print('PASS partial open cleanup retains actor until END')
end
do
    local api,cb,calls=scenario('detachScreen');local h=assert(api:open({role=77},cb))
    assert(api:close(h)==false);assert(not index(calls,'closed'));assert(not index(calls,'destroy'))
    print('PASS failed camera restore preserves native guard lifetime')
end
do
    local api,cb,calls,_,reference=scenario();reference.dead=true
    assert(not api:open({role=77},cb));assert(not index(calls,'spawn'))
    print('PASS engine-invalid actors rejected despite valid Lua UObject wrapper')
end
