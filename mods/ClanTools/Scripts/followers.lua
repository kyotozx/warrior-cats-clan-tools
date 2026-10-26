-- Optional owned exploration visuals. Root must verify spawn, animation and
-- navigation before enabling; this does not alter the game's combat party.
local M={}
local classPath='/Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_WalkingNPC_Character_Base.BP_WalkingNPC_Character_Base_C'
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local motion=dofile(folder..'follower_motion.lua')
local idle=dofile(folder..'follower_idle.lua')
local function same(a,b)return valid(a)and valid(b)and a:GetAddress()==b:GetAddress()end
local function guard(s)
    assert(s and s.offline==true and s.phase==4 and not s.combat,'Followers require offline exploration.')
    assert(valid(s.pawn),'The player is unavailable.')
    local w=s.pawn:GetWorld()
    assert(valid(w) and w:GetFullName()=='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P','Followers support the campaign world only.')
    assert(w.AuthorityGameMode:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Gameplay/Blueprints/Modes/BP_WrcGameplayGameMode.BP_WrcGameplayGameMode_C','Unsupported campaign mode.')
    assert(StaticFindObject('/Script/Engine.Default__KismetSystemLibrary'):IsStandalone(s.pawn)==true,'Followers cannot run in network sessions.')
    return s
end
function M.appearanceAdapter(directory,library)
    local prefix=directory:gsub('[/\\]$','')..'/'
    local native=assert(package.loadlib(prefix..(library or'follower-appearance.dll'),'ClanFollowers_appearance'))
    local nonce=0
    return function(snapshot,actor,role)
        guard(snapshot)
        assert(actor:GetClass():GetFullName()=='BlueprintGeneratedClass '..classPath,'Unsupported follower class.')
        local component=actor.MeshCustomizationComponent
        assert(valid(component) and same(component:GetOwner(),actor),'Follower customization component unavailable.')
        nonce=nonce+1
        local f=assert(io.open(prefix..'follower-request.txt','w'))
        f:write(string.format('%d %x %x %x %x %d %d\n',nonce,actor:GetAddress(),component:GetAddress(),actor:GetClass():GetAddress(),component:GetClass():GetAddress(),role,snapshot.clan));f:close()
        native()
        f=assert(io.open(prefix..'follower-status.txt','r'));local text=f:read('*a');f:close()
        assert(tonumber(text:match('nonce=(%d+)'))==nonce,'Stale follower appearance result.')
        assert(text:match('status=([^\r\n]+)')=='APPLIED',text)
        return true
    end
end
-- Explicit probe adapter: never called automatically, and only creates its own
-- actor. The ordinary lifecycle below calls it only with ctx.verified=true.
function M.spawn_probe(snapshot,cat,index,applyAppearance,createNameplate)
    local s=guard(snapshot)
    assert(type(cat.role)=='number' and cat.role>0 and cat.role<255 and cat.living==true and cat.clan==s.clan,'Choose a living cat from the active clan.')
    assert(index==1 or index==2,'At most two followers are supported.')
    local class=StaticFindObject(classPath);if not valid(class)then class=LoadAsset(classPath)end
    assert(valid(class),'Walking cat class unavailable.')
    local stats=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    local p=s.pawn:K2_GetActorLocation();local f=s.pawn:GetActorForwardVector();local r=s.pawn:GetActorRightVector()
    local side=index==1 and -1 or 1
    local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
    local profile=s.pawn.CapsuleComponent:GetCollisionProfileName()
    local color={R=0,G=0,B=0,A=0};local location
    -- Resolve a loaded floor before spawning. Copying player Z can place the
    -- other side of the formation inside a slope, causing a fall through terrain.
    for _,behind in ipairs({180,100,60})do
        local x,y=p.X-f.X*behind+r.X*side*90,p.Y-f.Y*behind+r.Y*side*90
        local hit={}
        local ok=system:LineTraceSingleByProfile(s.pawn,{X=x,Y=y,Z=p.Z+300},{X=x,Y=y,Z=p.Z-400},profile,false,{s.pawn},0,hit,true,color,color,0)
        if ok==true and hit.Time>0 and hit.Time<1 and hit.Distance>0 and hit.PenetrationDepth==0 and hit.ImpactNormal.Z>=.72 then
            location={X=hit.ImpactPoint.X,Y=hit.ImpactPoint.Y,Z=hit.ImpactPoint.Z+s.pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()+10};break
        end
    end
    assert(location,'[FOLLOWER_NAVIGATION] No safe floor beside the player.')
    local transform={Rotation={X=0,Y=0,Z=0,W=1},Translation=location,Scale3D={X=1,Y=1,Z=1}}
    local actor=stats:BeginDeferredActorSpawnFromClass(s.pawn,class,transform,2,s.pawn,0)
    assert(valid(actor),'Follower spawn failed.')
    local controller,controllerLifeSpanSet,nameplate
    local function controllerOwned(c)
        if not valid(c)then return end
        assert(c:IsPlayerController()==false,'Refusing to control a player controller.')
        local controlled=c.Pawn
        assert(not valid(controlled)or same(controlled,actor),'Follower controller was reassigned to another pawn.')
    end
    local function destroy()
        controllerOwned(controller)
        if valid(actor)and valid(actor.Controller)then
            assert(same(actor.Controller,controller),'Follower acquired an unexpected controller.')
            controllerOwned(actor.Controller)
        end
        local errors={}
        local function attempt(fn)local ok,e=pcall(fn);if not ok then errors[#errors+1]=tostring(e)end end
        if nameplate then attempt(function()assert(nameplate.destroy())end)end
        if valid(controller)then attempt(function()controller:StopMovement()end)end
        if valid(actor)then attempt(function()
            actor.bAddsToRemovedLocalData=false
            -- Preserve PawnPendingDestroy lifecycle before the pawn disappears.
            -- UnPossess first would detach the controller from that lifecycle.
            actor:DetachFromControllerPendingDestroy()
            if valid(actor)then actor:K2_DestroyActor()end
        end)end
        if valid(controller)and not controllerLifeSpanSet then attempt(function()
            assert(controller:IsPlayerController()==false,'Refusing to retire a player controller.')
            controller:UnPossess()
            -- AController.K2_DestroyActor deliberately does nothing. Its owned
            -- actor lifespan invokes native destruction; schedule only once so
            -- cleanup retries cannot perpetually postpone expiration.
            controller:SetLifeSpan(0.05);controllerLifeSpanSet=true
        end)end
        assert(#errors==0,table.concat(errors,'; '))
        local actorValid,controllerValid=valid(actor),valid(controller)
        assert(not actorValid and not controllerValid,'Follower cleanup pending (actor='..tostring(actorValid)..', controller='..tostring(controllerValid)..'). Resume gameplay briefly if paused.')
    end
    local ok,err=pcall(function()
        actor.bAddsToRemovedLocalData=false
        -- The native customization path only accepts Cat/BossCat characters.
        -- This is our deferred visual actor, not a quest or original clan actor.
        actor.CharacterType=1
        -- Empty quest identity remains untouched: no narrative role assignment,
        -- no addition to quest/player party arrays, no original actor borrowed.
        if valid(actor.InteractComponent)then actor.InteractComponent:SetGenerateOverlapEvents(false);actor.InteractComponent:SetCollisionEnabled(0)end
        stats:FinishSpawningActor(actor,transform,0)
        assert(valid(actor),'Follower was destroyed during initialization.')
        controller=actor.Controller
        if not valid(controller)then actor:SpawnDefaultController();controller=actor.Controller end
        assert(valid(controller),'Follower AI controller unavailable.')
        controllerOwned(controller)
        assert(same(controller.Pawn,actor),'Follower controller does not possess its owned pawn.')
        if valid(controller.BrainComponent)then controller.BrainComponent:StopLogic('ClanTools owned follower')end
        for _,name in ipairs({'QuestComponent','QuestMoveComponentHandler','TurnBasedCombatComponent'})do
            local c=actor[name];if valid(c)then c:Deactivate();c:SetComponentTickEnabled(false)end
        end
        if valid(actor.InteractComponent)then actor.InteractComponent:SetGenerateOverlapEvents(false);actor.InteractComponent:SetCollisionEnabled(0)end
        actor.CapsuleComponent:SetGenerateOverlapEvents(false)
        -- Owned visual companions never push pawns. World geometry still blocks
        -- their capsules; separation steering keeps their bodies apart visually.
        actor.CapsuleComponent:SetCollisionResponseToChannel(2,0)
        local movement=actor.CharacterMovement
        movement.MaxWalkSpeed=250;movement.MaxAcceleration=650
        movement.BrakingDecelerationWalking=800;movement.GroundFriction=6
        movement.bRequestedMoveUseAcceleration=true
        movement.NavMovementProperties.bUseAccelerationForPaths=true
        movement.bOrientRotationToMovement=true;movement.bUseControllerDesiredRotation=false
        movement.RotationRate={Pitch=0,Yaw=360,Roll=0};actor.bUseControllerRotationYaw=false
        assert(applyAppearance(s,actor,cat.role)==true,'Follower appearance failed.')
        if createNameplate then nameplate=createNameplate(actor,cat,s)end
    end)
    if not ok then pcall(destroy);error(err)end
    local owned={actor=actor,controller=controller,role=cat.role}
    local idleTiming=idle.new(actor:GetAddress()+cat.role*7919+index*104729)
    function owned:update_idle()
        if not valid(actor)then return end
        local mesh=actor.Mesh
        if not valid(mesh)then return end
        local anim=mesh:GetAnimInstance()
        if not valid(anim)then return end
        local v=actor:GetVelocity()
        idleTiming.tick(anim,v.X*v.X+v.Y*v.Y>25 or actor.CharacterMovement.MovementMode~=1)
    end
    local planner=motion.new(index);local peers={};local lastGoal,lastTime,lastRequest;local waiting=false
    function owned:set_peers(list)peers=list end
    function owned:IsValid()return valid(actor)end
    function owned:update_label(s,currentCat)if nameplate then return nameplate.update(s,currentCat)end;return true end
    function owned:stay()
        assert(valid(actor)and valid(controller),'Follower controller unavailable.')
        controllerOwned(controller);assert(same(controller.Pawn,actor),'Follower AI possession changed.')
        if not waiting then controller:StopMovement()end
        waiting=true;lastGoal=nil;planner.reset();return true
    end
    function owned:distance_to(target)
        assert(valid(actor)and valid(target),'Follower position unavailable.')
        local a,b=actor:K2_GetActorLocation(),target:K2_GetActorLocation()
        return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2+(a.Z-b.Z)^2)
    end
    function owned:follow(target,distance,now)
        assert(valid(actor)and valid(controller)and valid(target),'Follower navigation unavailable.')
        controllerOwned(controller)
        assert(same(controller.Pawn,actor),'Follower AI possession changed.')
        local time=now or os.clock();local dt=lastTime and time-lastTime or .2;lastTime=time
        local positions,ignored={},{actor,target}
        for _,other in ipairs(peers)do if other~=owned and valid(other.actor)then positions[#positions+1]=other.actor:K2_GetActorLocation();ignored[#ignored+1]=other.actor end end
        local plan=planner.plan(target:K2_GetActorLocation(),target:GetActorForwardVector(),actor:K2_GetActorLocation(),positions,distance,dt)
        if plan.stop then
            if not waiting then controller:StopMovement()end;waiting=true;lastGoal=nil;return true
        end
        local goal
        for _,candidate in ipairs({plan.goal,plan.center})do
            local hit={}
            local ok=system:LineTraceSingleByProfile(actor,{X=candidate.X,Y=candidate.Y,Z=candidate.Z+300},{X=candidate.X,Y=candidate.Y,Z=candidate.Z-400},profile,false,ignored,0,hit,true,color,color,0)
            if ok==true and hit.Time>0 and hit.Time<1 and hit.Distance>0 and hit.PenetrationDepth==0 and hit.ImpactNormal.Z>=.72 then
                goal={X=hit.ImpactPoint.X,Y=hit.ImpactPoint.Y,Z=hit.ImpactPoint.Z};break
            end
        end
        if not goal then if not waiting then controller:StopMovement()end;waiting=true;lastGoal=nil;return true end
        actor.CharacterMovement.MaxWalkSpeed=plan.speed
        if not waiting and lastGoal and (goal.X-lastGoal.X)^2+(goal.Y-lastGoal.Y)^2<30^2 and time-(lastRequest or 0)<1 then return true end
        local result=controller:MoveToLocation(goal,30,false,true,true,false,nil,true)
        if result==0 then
            -- Exact enum Failed0 / AlreadyAtGoal1 / RequestSuccessful2.
            -- Some campaign terrain has no navmesh. Engine direct movement
            -- still preserves CharacterMovement ground and capsule collision.
            -- Live probe:133cm movement at250cm/s with collision enabled.
            result=controller:MoveToLocation(goal,30,false,false,false,false,nil,true)
        end
        if result~=1 and result~=2 then if not waiting then controller:StopMovement()end;waiting=true;lastGoal=nil;return true end
        lastGoal=goal;lastRequest=time;waiting=false
        return true
    end
    function owned:destroy()destroy();return true end
    return owned
end
function M.new(ctx)
    assert(type(ctx.snapshot)=='function'and type(ctx.getCats)=='function'and type(ctx.spawn)=='function','Follower context is required.')
    local owned,roles,session,lastUpdate={}, {},nil,-math.huge
    local api={error=nil};local closed=false
    local mode,distance,regroupDeadline='follow',150,nil
    local function snapshot()
        local s=ctx.snapshot();if ctx.validate then assert(ctx.validate(s)==true,'Follower world rejected.')else guard(s)end
        assert(s and s.offline==true and s.phase==4 and not s.combat and valid(s.pawn),'Followers require offline exploration.')
        assert(s.worldId~=nil,'Follower world identity is unavailable.');return s
    end
    local function identity(s)return tostring(s.worldId)..':'..tostring(s.pawn:GetAddress())..':'..tostring(s.profile)..':'..tostring(s.slot)..':'..tostring(s.chapter)end
    function api.reset()
        local retained,errors={},{}
        for _,f in ipairs(owned)do local ok,e=pcall(function()assert(f:destroy()~=false)end);if not ok then retained[#retained+1]=f;errors[#errors+1]=tostring(e)end end
        owned=retained;roles={};session=nil;mode='follow';regroupDeadline=nil
        if #errors>0 then api.error=table.concat(errors,'; ');return false,api.error end
        api.error=nil;return true,'Exploration followers dismissed.'
    end
    function api.select(requested)
        local ok,msg=pcall(function()
            assert(not closed and not api.error,'Followers are unavailable until cleanup succeeds.')
            assert(ctx.verified==true,'Exploration follower navigation and animation have not been verified.')
            local s=snapshot();assert(type(requested)=='table'and #requested<=2,'Choose up to two followers.')
            local candidates={};for _,c in ipairs(ctx.getCats())do if c.living==true and c.clan==s.clan then candidates[c.role]=c end end
            local selected,seen={},{}
            for _,role in ipairs(requested)do assert(candidates[role]and not seen[role],'Choose different living clan cats.');seen[role]=true;selected[#selected+1]=candidates[role]end
            assert(api.reset());session=identity(s)
            for i,cat in ipairs(selected)do
                local follower=assert(ctx.spawn(s,cat,i));owned[#owned+1]=follower;roles[#roles+1]=cat.role
                assert(follower:IsValid(),'Follower initialization failed.')
                if mode=='stay'then follower:stay()else follower:follow(s.pawn,mode=='regroup'and 60 or distance)end
            end
            for _,f in ipairs(owned)do if f.set_peers then f:set_peers(owned)end end
            lastUpdate=-math.huge
            return 'Exploration followers enabled.'
        end)
        if not ok then local cleared,cleanup=api.reset();return false,tostring(msg)..(cleared and ''or(' '..cleanup))end
        return true,msg
    end
    function api.command(value)
        local ok,why=pcall(function()
            assert(not closed and not api.error,'Followers are unavailable.');snapshot()
            assert(value=='follow'or value=='stay'or value=='regroup','Unknown follower command.')
            assert(#owned>0,'Enable followers and return to exploration first.')
            -- Stop immediately before changing the mode. Never teleport the
            -- visual actors: native navigation retains terrain/collision safety.
            for _,f in ipairs(owned)do assert(f:stay()~=false,'Follower stop failed.')end
            mode=value;regroupDeadline=nil;lastUpdate=-math.huge;return true
        end)
        if not ok then return false,tostring(why)end
        return true,value=='stay'and'Your companions will wait here.'or value=='regroup'and'Your companions are regrouping nearby.'or'Your companions are following you.'
    end
    function api.set_distance(value)
        if type(value)~='number'or value%1~=0 or value<100 or value>600 then return false,'Follow distance must be between 100 and 600 cm.'end
        distance=value;lastUpdate=-math.huge;return true
    end
    function api.tick(now)
        if closed then return false,'Followers are shut down.'end
        if #owned==0 then return not api.error,api.error end
        local ok,s=pcall(snapshot)
        if not ok or (session and identity(s)~=session)then return api.reset()end
        if api.error then return false,api.error end
        local time=now or (ctx.clock and ctx.clock())or os.clock()
        if mode=='regroup'and not regroupDeadline then regroupDeadline=time+12 end
        if mode=='regroup'and time>=regroupDeadline then mode='follow';regroupDeadline=nil end
        if time-lastUpdate<0.2 then return true end;lastUpdate=time
        local eligible={};for _,cat in ipairs(ctx.getCats())do if cat.living==true and cat.clan==s.clan then eligible[cat.role]=cat end end
        local arrived=mode=='regroup'
        for i,f in ipairs(owned)do
            if not eligible[roles[i]]or not f:IsValid()then return api.reset()end
            local moved,err=pcall(function()
                if f.update_idle then f:update_idle()end
                if f.update_label then assert(f:update_label(s,eligible[roles[i]])~=false,'Follower nameplate unavailable.')end
                if mode=='stay'then return f:stay()end
                if mode=='regroup'and f:distance_to(s.pawn)>200 then arrived=false end
                return f:follow(s.pawn,mode=='regroup'and 60 or distance,time)
            end)
            if not moved then api.reset();return false,tostring(err)end
        end
        if arrived then mode='follow';regroupDeadline=nil end
        return true
    end
    function api.state()local copy={};for i,r in ipairs(roles)do copy[i]=r end;return {supported=ctx.verified==true,active=#owned,roles=copy,error=api.error,mode=mode,distance=distance}end
    function api.shutdown()local ok,msg=api.reset();if ok then closed=true end;return ok,msg end
    return api
end
return M
