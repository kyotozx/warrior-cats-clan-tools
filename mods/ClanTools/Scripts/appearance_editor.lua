-- Adapter for the game's actual customization screen. The transaction module
-- installs its save/flow guards before this adapter creates any preview widget.
-- Call open/close/release on the game thread; only release after native END.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
local function checked(fn,...)
    assert(type(fn)=='function','Appearance callback is unavailable')
    local ok,err=fn(...);assert(ok,err or 'Appearance operation failed');return ok
end
function M.new(ctx)
    assert(type(ctx.valid)=='function','Appearance editor requires the shared engine-validity helper')
    local function valid(o)return ctx.valid(o)end
    local api={};local active
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    local widgets=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local cameras=(ctx.appearanceCameraFactory or dofile(folder..'appearance_camera.lua')).new(ctx)
    local presentation=(ctx.appearancePresentationFactory or dofile(folder..'appearance_presentation.lua')).new(ctx)
    local rotation=(ctx.appearanceRotationFactory or dofile(folder..'appearance_rotation.lua')).new(ctx)
    local function findTagged(tag)
        for _,actor in ipairs(FindAllOf('GuiCatCustomActor')or{})do
            if valid(actor)and actor:ActorHasTag(FName(tag))then return actor end
        end
    end
    local function restoreCamera(h)
        checked(h.callbacks.detachScreen)
        cameras:restore(h)
        if valid(h.pc)and valid(h.viewTarget)then
            h.pc:SetViewTargetWithBlend(h.viewTarget,0,0,0,false)
        end
        presentation:restore(h)
        if ctx.restoreAppearanceInput then ctx.restoreAppearanceInput(h)end
    end
    function api:open(cat,callbacks)
        if active then return nil,'An appearance preview is already open'end
        local h={cat=cat,callbacks=callbacks};active=h
        local ok,err=pcall(function()
            local s=assert(ctx.snapshot(),'Load an offline clan first')
            assert(s.offline==true and valid(s.pawn)and valid(s.pc),'Player context unavailable')
            assert(not findTagged('Cat'),'A game creation preview is already active')
            local reference=assert(findTagged('InventoryCat'),'Open the pause menu before editing appearances')
            local gui=FindFirstOf('WrcGuiManager');assert(valid(gui)and valid(gui.CatCustomClass),'Game preview assets unavailable')
            local helper
            local referenceWorld=reference:GetWorld()
            for _,candidate in ipairs(FindAllOf('WrcCameraViewHelper')or{})do
                if valid(candidate)and candidate:ActorHasTag(FName('SelectCatCamHelper'))then
                    local world=candidate:GetWorld()
                    if valid(world)and valid(referenceWorld)and world:GetAddress()==referenceWorld:GetAddress()then helper=candidate;break end
                end
            end
            assert(valid(helper),'Game preview camera unavailable')
            local firstHelper=FindFirstOf('WrcCameraViewHelper')
            assert(valid(firstHelper)and firstHelper:GetAddress()==helper:GetAddress(),'Multiple game camera helpers are active')
            h.pc=s.pc;h.viewTarget=s.pc:GetViewTarget();h.context=s
            assert(valid(h.viewTarget),'The current camera cannot be restored')
            local transform=reference:GetTransform()
            h.actor=gameplay:BeginDeferredActorSpawnFromClass(s.pawn,gui.CatCustomClass,transform,1,s.pawn,0)
            assert(valid(h.actor),'Could not create the appearance preview')
            h.actor:SetActorEnableCollision(false)
            gameplay:FinishSpawningActor(h.actor,transform,0)
            assert(valid(h.actor),'Appearance preview failed to initialize')
            -- Only this owned actor receives the tag searched by native init.
            h.actor.Tags={FName('Cat')}
            assert(h.actor:ActorHasTag(FName('Cat')),'Could not identify the appearance preview')
            if valid(h.actor.CaptureComponent)then
                h.actor.CaptureComponent.bCaptureEveryFrame=false
                h.actor.CaptureComponent.bCaptureOnMovement=false
            end
            h.actor:ForceBestLOD();h.actor:TurnOnExtraLight();h.actor:PlayMontageSit()
            checked(callbacks.ready,h.actor:GetAddress())
            cameras:prepare(h,helper,reference)
            checked(callbacks.cameraReady,helper:GetAddress())
            cameras:attach(h,callbacks)
            local class=LoadAsset('/Game/Art/UXD/Blueprints/Screens/WBP_GuiScreenCustomization.WBP_GuiScreenCustomization_C')
            assert(valid(class),'Game customization screen unavailable')
            h.widget=widgets:Create(s.gameState,class,s.pc)
            assert(valid(h.widget),'Could not create the game customization screen')
            -- Save/tutorial guards already exist from BEGIN. Install the
            -- per-instance transition guard BEFORE mount: AddToViewport may
            -- invoke the game's NativeConstruct. INIT then verifies that
            -- result and only initializes manually if no CatRef was assigned.
            checked(callbacks.screenReady,h.widget:GetAddress())
            h.widget:AddToViewport(1000010)
            checked(callbacks.initializeScreen,h.widget:GetAddress())
            if cameras.reframe then cameras:reframe(h)end
            for _,name in ipairs({'mcGuiFooter','HoldButtonBack','mcGuiScreenStep','canvasPanelTitle'})do
                local control=h.widget[name];if valid(control)then control:SetVisibility(2)end
            end
            presentation:open(h)
            assert(type(ctx.attachAppearanceControls)=='function','Appearance controls unavailable')
            h.controls=assert(ctx.attachAppearanceControls(h.widget,cat,callbacks),'Appearance controls failed to open')
            rotation.start(h)
            if ctx.onAppearanceOpened then ctx.onAppearanceOpened(h)end
        end)
        if not ok then h.error=tostring(err);return nil,h.error end
        return h
    end
    function api:close(handle)
        local h=handle or active
        if not h then return true end
        if h.closed then return true end
        -- Any failure leaves owned objects alive and native guards installed;
        -- the controller can retry cleanup rather than invalidating callbacks.
        local ok,err=pcall(function()
            rotation.stop()
            if h.controls and h.controls.close then h.controls.close()end
            if valid(h.widget)then h.widget:SetVisibility(2)end
            restoreCamera(h)
            if valid(h.widget)then h.widget:RemoveFromParent()end
            h.closed=true
            if ctx.onAppearanceClosed then ctx.onAppearanceClosed(h)end
            checked(h.callbacks.closed)
        end)
        if not ok then return false,tostring(err)end
        return true
    end
    function api:release(handle)
        local h=handle or active;if not h then return true end
        assert(h.closed,'Close the appearance screen before releasing its preview')
        -- Called only after END restored the native vtable and hooks.
        presentation:restore(h,true)
        cameras:release(h)
        if valid(h.actor)then h.actor:K2_DestroyActor()end
        if active==h then active=nil end
        h.actor=nil;h.widget=nil;h.controls=nil;return true
    end
    function api:state()return active end
    function api:tick()if active and not active.closed then presentation:tick(active);if cameras.tick then cameras:tick(active)end end end
    return api
end
return M
