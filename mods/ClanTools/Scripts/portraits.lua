-- Genuine game portraits with a private capture actor and a distinct render
-- target per cached cat. No shared HUD portrait index or global RT is changed.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local appearance=dofile(dir..'appearance.lua')
local M={}
function M.new(ctx)
    assert(type(ctx.valid)=='function','Portraits require the shared engine-validity helper')
    local function valid(o)return ctx.valid(o)end
    local command=ctx.native or appearance.nativeTransport(ctx.nativeDir or ctx.root..'bin/',ctx.appearanceDllName)
    local api={error=nil};local actor,profile,busy,retainer;local cache,queue,pending={},{},{}
    local wanted,serial={},0
    local cacheLimit=32
    local rendering=StaticFindObject('/Script/Engine.Default__KismetRenderingLibrary')
    local materials=StaticFindObject('/Script/Engine.Default__KismetMaterialLibrary')
    local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    local widgets=StaticFindObject('/Script/UMG.Default__WidgetBlueprintLibrary')
    local function retain(entry,s)
        -- Viewport -> WidgetTree -> Image.Brush -> MID -> texture is an actual
        -- UObject reference chain. Lua userdata alone does not prevent UE GC.
        if not valid(retainer)then
            local class=LoadAsset('/Game/Art/UXD/Blueprints/Controls/gui_common/WBP_GuiClanScreenBackground.WBP_GuiClanScreenBackground_C')
            retainer=widgets:Create(s.gameState,class,s.pc)
            assert(valid(retainer),'Could not retain portrait cache')
            retainer:SetVisibility(2);retainer:AddToViewport(-10000)
        end
        local image=StaticConstructObject(StaticFindObject('/Script/UMG.Image'),retainer.WidgetTree)
        assert(valid(image),'Could not retain portrait material')
        image:SetBrushFromMaterial(entry.material)
        retainer.WidgetTree.RootWidget:AddChild(image)
        entry.retainer=image
    end
    local function token(s)return s.profile..':'..tostring(s.slot)..':'..tostring(s.gs)..':'..tostring(s.worldId)end
    local function release(entry)
        if entry and valid(entry.retainer)then pcall(function()entry.retainer:RemoveFromParent()end)end
        if entry and valid(entry.target)then pcall(function()rendering:ReleaseRenderTarget2D(entry.target)end)end
    end
    local function destroyActor()
        if valid(actor)then pcall(function()actor:K2_DestroyActor()end)end
        actor=nil
    end
    local function prune()
        local count=0;local old={}
        for key,entry in pairs(cache)do count=count+1;if not wanted[key]then old[#old+1]={key=key,entry=entry}end end
        table.sort(old,function(a,b)return a.entry.used<b.entry.used end)
        for _,row in ipairs(old)do if count<=cacheLimit then break end;release(row.entry);cache[row.key]=nil;count=count-1 end
    end
    function api:cancelPending()
        -- Destroy the capture owner before releasing an in-flight target.
        -- Completed textures stay retained for reopening the same page.
        destroyActor()
        if busy then release(busy)end
        busy=nil;queue={};pending={};wanted={}
        prune()
    end
    function api:beginView()self:cancelPending()end
    function api:clear()
        self:cancelPending()
        for _,entry in pairs(cache)do release(entry)end
        if valid(retainer)then pcall(function()retainer:RemoveFromParent()end)end
        retainer=nil
        actor=nil;busy=nil;cache={};queue={};pending={};profile=nil;self.error=nil
    end
    local function ownedActor(s)
        if valid(actor)then return actor end
        if ctx.createPortraitActor then actor=ctx.createPortraitActor(s);assert(valid(actor),'Portrait actor unavailable');return actor end
        local gui=FindFirstOf('WrcGuiManager');assert(valid(gui),'Game portrait assets unavailable')
        local class=gui.CatCustomClass;assert(valid(class),'Game cat preview class unavailable')
        local position=s.pawn:K2_GetActorLocation()
        -- Keep our visible mesh out of the playable area, with its own lights.
        local transform={Rotation={X=0,Y=0,Z=0,W=1},Translation={X=position.X,Y=position.Y,Z=position.Z+100000},Scale3D={X=1,Y=1,Z=1}}
        actor=gameplay:BeginDeferredActorSpawnFromClass(s.pawn,class,transform,1,s.pawn,0)
        assert(valid(actor),'Could not spawn portrait preview')
        actor:SetActorEnableCollision(false)
        -- Disable automatic captures before BeginPlay when native components
        -- already exist. Blueprint construction may finish creating them later.
        if valid(actor.CaptureComponent)then
            actor.CaptureComponent.bCaptureEveryFrame=false
            actor.CaptureComponent.bCaptureOnMovement=false
        end
        gameplay:FinishSpawningActor(actor,transform,0)
        assert(valid(actor),'Portrait preview failed to initialize')
        assert(valid(actor.CaptureComponent),'Portrait capture component unavailable')
        actor.CaptureComponent.bCaptureEveryFrame=false
        actor.CaptureComponent.bCaptureOnMovement=false
        -- These methods are reflected on AGuiCatCustomActor.
        actor:ForceBestLOD();actor:SetAnimClassHUD();actor:TurnOnExtraLight();actor:PlayMontageSit()
        return actor
    end
    function api:get(cat,onReady)
        local s=ctx.snapshot();if not s then return nil end
        local current=token(s);if profile and current~=profile then self:clear()end;profile=current
        local key=current..':'..cat.role..':'..tostring(cat.custom or cat.revision or '')
        wanted[key]=true;serial=serial+1
        local hit=cache[key]
        if hit and valid(hit.material)and valid(hit.target)then hit.used=serial;return hit.material end
        if hit then release(hit);cache[key]=nil end
        if not pending[key]then
            local request={key=key,role=cat.role,skin=cat.skin,context=current,callbacks={},used=serial};pending[key]=request;queue[#queue+1]=request
        end
        if onReady then pending[key].callbacks[#pending[key].callbacks+1]=onReady end
        return nil
    end
    function api:tick()
        if not busy and #queue==0 then destroyActor();return end
        local s=ctx.snapshot();if not s then if profile then self:clear()end;return end
        if profile and token(s)~=profile then self:clear();return end
        if self.error then return end
        local ok,err=pcall(function()
            if not busy then
                if #queue==0 then return end
                busy=table.remove(queue,1)
                if busy.context~=token(s)then pending[busy.key]=nil;busy=nil;return end
                local a=ownedActor(s);local capture=a.CaptureComponent
                assert(valid(capture),'Game portrait capture is unavailable')
                local result,message=command(busy.skin and string.format('SKIN_PORTRAIT %x %s',a:GetAddress(),busy.skin)or string.format('PORTRAIT %d %x',busy.role,a:GetAddress()))
                assert(result,message)
                local size=tonumber(ctx.portraitSize)or 512
                size=math.max(128,math.min(1024,math.floor(size)))
                busy.target=rendering:CreateRenderTarget2D(s.gameState,size,size,2,{R=0,G=0,B=0,A=0},false,false)
                assert(valid(busy.target),'Could not allocate portrait render target')
                capture.TextureTarget=busy.target
                capture.bCaptureEveryFrame=false;capture.bCaptureOnMovement=false
                capture.PrimitiveRenderMode=2
                capture:ClearShowOnlyComponents();capture:ShowOnlyActorComponents(a,true)
                busy.capture=capture;busy.frames=0;busy.stage='warmup';return
            end
            busy.frames=busy.frames+1
            if busy.stage=='warmup' and busy.frames>=3 then
                -- Wait for skeletal pose/material streaming before the capture.
                busy.capture:CaptureScene();busy.stage='render';busy.frames=0;return
            end
            if busy.stage=='render' and busy.frames>=2 then
                local gui=FindFirstOf('WrcGuiManager');assert(valid(gui),'Portrait material unavailable')
                busy.material=materials:CreateDynamicMaterialInstance(s.gameState,gui.MaterialCatFaceRT,FName('None'),0)
                assert(valid(busy.material),'Could not create game portrait material')
                busy.material:SetTextureParameterValue(FName('SampleRT'),busy.target)
                retain(busy,s)
                local done=busy;busy=nil;pending[done.key]=nil;cache[done.key]=done
                for _,callback in ipairs(done.callbacks)do pcall(callback,done.material)end
                done.callbacks=nil;done.capture=nil
                prune()
                if #queue==0 then destroyActor()end
            end
        end)
        if not ok then
            self.error=tostring(err)
            self:cancelPending()
            if ctx.log then ctx.log('Portrait rendering: '..self.error)end
        end
    end
    function api:invalidate(role)
        self:cancelPending()
        for key,entry in pairs(cache)do if not role or entry.role==role then release(entry);cache[key]=nil end end
    end
    function api:retry()self.error=nil end
    return api
end
return M
