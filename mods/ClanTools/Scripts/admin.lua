-- Offline admin backend. Invoke every entry point on the game thread.
-- Movement changes are temporary. Optional progression transactions use native
-- game save pathways, backups and separately verified capabilities.
local folder = debug.getinfo(1, 'S').source:gsub('^@', ''):match('^(.*[/\\])')
local catalog = dofile(folder .. 'admin_catalog.lua')
local teleportGuard = dofile(folder .. 'admin_teleport_guard.lua')
local M = {}
local function finite(x) return type(x) == 'number' and x == x and math.abs(x) < math.huge end
local function vector(v)
    assert(v ~= nil, 'A position is required.')
    local r = { X = v.X or v.x, Y = v.Y or v.y, Z = v.Z or v.z }
    for _, k in ipairs({'X', 'Y', 'Z'}) do
        assert(finite(r[k]) and math.abs(r[k]) <= 1000000, 'Coordinates must be finite and within the supported world bounds.')
    end
    return r
end
local function distance(a, b)
    return math.sqrt((a.X-b.X)^2 + (a.Y-b.Y)^2 + (a.Z-b.Z)^2)
end
local valid=dofile(folder..'runtime_valid.lua').valid
local function identity(x)
    local ok, id = pcall(function() return x:GetAddress() end)
    return ok and id or x
end
local function count(t) local n=0; for _ in pairs(t) do n=n+1 end; return n end
local function lookup(list, id)
    for _, item in ipairs(list) do if item.id == id then return item end end
    error('Unknown catalog entry.')
end
local function copyCatalog(list)
    local out={}; for i,e in ipairs(list) do out[i]={id=e.id,label=e.label} end; return out
end

function M.new(ctx)
    assert(type(ctx)=='table' and type(ctx.snapshot)=='function', 'Admin requires ctx.snapshot().')
    local api, session, move, god = {}, nil, nil, nil
    local flight, noclip, speed = false, false, 1
    local returnPoint, noclipAnchor, waypoints = nil, nil, {}
    local waypointStore=ctx.waypointStore or dofile(folder..'admin_waypoints.lua').new(ctx)
    local waypointScope,waypointError
    local function loadWaypoints(s,force)
        if not s or not s.profile or s.slot==nil then waypoints={};waypointScope=nil;return end
        local scope=table.concat({s.profile,tostring(s.slot),s.worldId},'|')
        if waypointScope==scope and not force then return end
        local rows=waypointStore.list(s);waypoints={}
        for name,p in pairs(rows)do waypoints[name]={world=s.worldId,position=vector(p)}end
        waypointScope=scope;waypointError=nil
    end
    local spawned, closed, resetErrors, cleanupPending = {}, false, {}, false
    local deferredNoclip
    local adapters = ctx.adapters or {}
    local destinations=ctx.destinations or dofile(folder..'admin_destinations.lua').new(ctx)
    local progression=ctx.progression or (ctx.progressionAdapter and dofile(folder..'admin_progression.lua').new(ctx))
    local function verified(feature)
        return ctx.verified and ctx.verified[feature] == true
    end
    local function supported(feature)
        if feature=='spawn_enemy' or feature=='spawn_training' or feature=='heal' then
            return verified(feature) and type(adapters[feature])=='function'
        elseif feature=='god' then
            return verified(feature)
        elseif feature=='spawn_item' then return verified(feature)
        elseif feature=='teleport_destination'then return verified('teleport')and verified('named_destinations')
        elseif feature=='noclip' then return verified('movement') and verified('collision') and verified('teleport')
        elseif feature=='flight' or feature=='speed' then return verified('movement')
        else return verified(feature) end
    end
    local function requireFeature(feature)
        assert(supported(feature), 'This action is unavailable: the game adapter has not been verified.')
    end
    local function getSnapshot()
        local ok, s = pcall(ctx.snapshot)
        if not ok or type(s)~='table' then return nil, 'Game state is unavailable.' end
        if s.offline ~= true then return nil, 'Admin tools require a confirmed offline campaign. Online or unknown session state is blocked.' end
        if s.phase ~= 4 then return nil, 'Admin tools are available only during exploration.' end
        if s.combat then return nil, 'Admin tools are unavailable during combat.' end
        if not valid(s.pawn) then return nil, 'The player is not available.' end
        if s.worldId==nil or s.worldId=='' then return nil, 'The current world is unknown.' end
        local worldOK,worldReason=pcall(function()
            if adapters.validate_world then
                assert(adapters.validate_world(s)==true,'Unsupported game world.')
                return
            end
            local world=s.pawn:GetWorld()
            assert(valid(world),'The current world is unavailable.')
            assert(world:GetFullName()=='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P','Admin tools support the campaign world only.')
            assert(s.pawn:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_Exploration_Character_Player.BP_Exploration_Character_Player_C','Unsupported player class.')
            assert(world.AuthorityGameMode:GetClass():GetFullName()=='BlueprintGeneratedClass /Game/Gameplay/Blueprints/Modes/BP_WrcGameplayGameMode.BP_WrcGameplayGameMode_C','Admin tools support the campaign game mode only.')
            local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
            assert(valid(system) and system:IsStandalone(s.pawn)==true,'Network sessions are not supported.')
        end)
        if not worldOK then return nil,tostring(worldReason) end
        local snapshot={};for key,value in pairs(s) do snapshot[key]=value end
        snapshot.pawnId = s.pawnId or identity(s.pawn)
        return snapshot
    end
    local function teleport(pawn, destination, sweep)
        local target = vector(destination)
        if type(adapters.teleport)=='function' then
            assert(adapters.teleport(pawn, target, sweep)==true, 'Teleport was rejected by the game adapter.')
        else
            local result = pawn:K2_SetActorLocation(target, sweep == true, {}, true)
            assert(result ~= false, 'Teleport was rejected by the game.')
        end
        assert(distance(vector(pawn:K2_GetActorLocation()), target) <= 2, 'Teleport did not reach the requested position.')
    end
    local function attempt(label, fn)
        local ok, err = pcall(fn)
        if not ok then resetErrors[#resetErrors+1]=label .. ': ' .. tostring(err) end
        return ok
    end
    local flightProperties={'MaxAcceleration','BrakingDecelerationFlying','BrakingFriction','BrakingFrictionFactor','bUseSeparateBrakingFriction'}
    local function restoreFlightTuning()
        if not move or not move.flightTuning or not valid(move.component)then return end
        move.component:StopMovementImmediately()
        for _,key in ipairs(flightProperties)do move.component[key]=move.flightTuning[key]end
        move.flightTuning=nil
    end
    local function destroy(actor)
        if not valid(actor) then return true end
        if type(actor)=='table' and actor.CanCleanup and actor:CanCleanup()==false then return 'deferred' end
        if adapters.destroy then assert(adapters.destroy(actor) ~= false, 'Cleanup was rejected.')
        else actor:K2_DestroyActor() end
        -- UObject registration can outlive actor destruction. Engine validity
        -- decides completion; keep ownership until the actor really disappears.
        if valid(actor) then return 'deferred' end
        return true
    end
    local function cleanupActors()
        local survivors={}
        for _, actor in ipairs(spawned) do
            local result
            local ok=attempt('Spawn cleanup',function()result=destroy(actor)end)
            if not ok or result=='deferred' then survivors[#survivors+1]=actor end
        end
        spawned=survivors;cleanupPending=#survivors>0
    end
    local function restoreNoclip(record)
        if not record then return true end
        if not valid(record.pawn)then return true end
        local ok,current=pcall(ctx.snapshot)
        if not ok or not current or current.phase~=4 or current.combat or not valid(current.pawn)then return false end
        if current.worldId~=record.worldId or identity(current.pawn)~=identity(record.pawn)then return true end
        -- Combat setup temporarily unpossesses the exploration pawn. Enabling
        -- collision then can trigger another encounter before setup finishes.
        if current.pc and (not valid(current.pc)or not valid(current.pc.Pawn)or identity(current.pc.Pawn)~=identity(record.pawn))then return false end
        if record.anchor then teleport(record.pawn,record.anchor,false)end
        if record.pawn:GetActorEnableCollision()~=record.collision then record.pawn:SetActorEnableCollision(record.collision)end
        return true
    end
    function api.reset(reason)
        resetErrors={}
        if progression then progression.reset() end
        -- Cleanup uses captured objects, never the pawn from the next session.
        -- It is intentionally possible even when offline/exploration checks fail.
        if session and valid(session.pawn) then
            if noclip and move and move.collision~=nil then
                deferredNoclip={pawn=session.pawn,worldId=session.worldId,anchor=noclipAnchor,collision=move.collision}
            end
            if move then
                if valid(move.component) then
                    attempt('Flight handling',restoreFlightTuning)
                    if move.forcedFlying and move.component.MovementMode==5 then
                        attempt('Movement mode', function() move.component:SetMovementMode(move.mode, move.custom) end)
                    end
                    attempt('Flight speed', function() move.component.MaxFlySpeed=move.flySpeed end)
                    attempt('Walking speed', function() move.component.MaxWalkSpeed=move.walkSpeed end)
                end
            end
            if god then
                attempt('God mode', function()
                    if god.manager then
                        if valid(god.manager) then
                            god.manager.GodMode=god.value
                            assert(god.manager.GodMode==god.value, 'God mode did not restore.')
                        end
                    else assert(adapters.god(session, god.value) ~= false) end
                end)
            end
        end
        if deferredNoclip then attempt('Noclip return',function()if restoreNoclip(deferredNoclip)then deferredNoclip=nil end end)end
        cleanupActors()
        if #resetErrors>0 then
            -- Refuse additional edits after cleanup failure; report it to root.
            -- Keep restoration records so reset/shutdown can retry cleanup.
            closed=true
            return false, 'Admin cleanup failed: ' .. table.concat(resetErrors, '; ')
        end
        flight,noclip,speed=false,false,1
        move,god,noclipAnchor,returnPoint,session=nil,nil,nil,nil,nil
        waypoints={};waypointScope=nil -- persisted bookmarks survive temporary reset
        return true, cleanupPending and 'Temporary changes reset. Enemy cleanup will finish after the active transition or combat.' or (reason or 'Temporary admin changes reset.')
    end
    local function guard()
        assert(not closed, 'Admin tools are shut down. Reload the mod before using them again.')
        assert(not cleanupPending, 'Wait for enemy cleanup to finish before making more admin changes.')
        assert(not deferredNoclip, 'Wait for exploration possession to return before making more admin changes.')
        local s, why = getSnapshot()
        if not s then
            local ok, msg=api.reset(why)
            error(ok and why or msg)
        end
        if session and (session.worldId~=s.worldId or session.pawnId~=s.pawnId) then
            local ok, msg=api.reset('World or player changed.')
            assert(ok,msg)
            error('World or player changed. Previous admin changes were reset; retry in the new world.')
        end
        session=s
        return s
    end
    local function captureMovement(s)
        if move then return end
        local component=s.pawn.CharacterMovement
        assert(valid(component), 'Character movement is unavailable.')
        local mode,custom,fly,walk=component.MovementMode,component.CustomMovementMode,component.MaxFlySpeed,component.MaxWalkSpeed
        assert(type(mode)=='number' and type(custom)=='number' and finite(fly) and finite(walk), 'Movement properties are unavailable.')
        move={component=component,mode=mode,custom=custom,flySpeed=fly,walkSpeed=walk}
    end
    local function applyMovement(s)
        if not move then return end
        assert(valid(move.component), 'Movement component is no longer available.')
        if flight or noclip then
            if not move.flightTuning then
                local original={}
                for _,key in ipairs(flightProperties)do
                    local value=move.component[key]
                    assert(key=='bUseSeparateBrakingFriction'and type(value)=='boolean'or key~='bUseSeparateBrakingFriction'and finite(value), 'Flight handling property is unavailable: '..key)
                    original[key]=value
                end
                move.flightTuning=original
                move.component:StopMovementImmediately()
            end
            -- Ground movement tuning is extremely soft in MOVE_Flying. Keep
            -- engine collision and native camera-relative input, but accelerate
            -- and brake promptly instead of coasting for several seconds.
            move.component.MaxAcceleration=math.max(2400,move.flightTuning.MaxAcceleration)
            move.component.BrakingDecelerationFlying=math.max(3000,move.flightTuning.BrakingDecelerationFlying)
            move.component.BrakingFriction=8
            move.component.BrakingFrictionFactor=1
            move.component.bUseSeparateBrakingFriction=true
            move.forcedFlying=true
            move.component.MaxFlySpeed = math.min(2000, math.max(250, move.flySpeed)*speed)
            move.component:SetMovementMode(5, 0) -- MOVE_Flying from Engine EMovementMode
            assert(move.component.MovementMode==5, 'Flying movement mode was not applied.')
        else
            restoreFlightTuning()
            if move.forcedFlying then
                if move.component.MovementMode==5 then move.component:SetMovementMode(move.mode, move.custom) end
                move.forcedFlying=false
            end
            move.component.MaxFlySpeed=move.flySpeed
        end
        move.component.MaxWalkSpeed=math.min(2000, move.walkSpeed*speed)
    end
    local function toggle(value, old)
        if value==nil then return not old end
        assert(type(value)=='boolean', 'Enabled must be true or false.')
        return value
    end
    local function jump(s, destination)
        assert(not noclip, 'Turn noclip off before teleporting.')
        local target=vector(destination)
        local clear,why=(adapters.teleport_clearance or teleportGuard.check)(s,target)
        assert(clear==true,why or 'Encounter clearance could not be verified.')
        local old=vector(s.pawn:K2_GetActorLocation())
        teleport(s.pawn,target,false)
        returnPoint={world=s.worldId,position=old}
    end
    local function spawn(s, kind, entry, quantity)
        local created={}
        local ok,err=pcall(function()
            for i=1,quantity do
                local p=vector(s.pawn:K2_GetActorLocation())
                p.X=p.X+(kind~='spawn_item' and 350 or 120)+(i-1)*50; p.Z=p.Z+30
                local actor
                if type(adapters[kind])=='function' then actor=adapters[kind](s,entry,p)
                else
                    local world=s.pawn:GetWorld()
                    assert(valid(world), 'The current world is unavailable.')
                    local class=StaticFindObject(entry.class)
                    if not valid(class) then class=LoadAsset(entry.class) end
                    assert(valid(class), 'The pickup class could not be loaded.')
                    actor=world:SpawnActor(class,p,{Pitch=0,Yaw=0,Roll=0})
                end
                assert(valid(actor), 'The game did not create the requested actor.')
                created[#created+1]=actor
                spawned[#spawned+1]=actor -- record before any subsequent validation can fail
            end
        end)
        if not ok then
            for _,a in ipairs(created) do attempt('Partial spawn cleanup',function() destroy(a) end) end
            error(err)
        end
        return quantity
    end
    local handlers={}
    function handlers.flight(s,a)
        requireFeature('flight'); captureMovement(s)
        flight=toggle(a.enabled,flight); applyMovement(s)
        return 'Flight ' .. (flight and 'enabled.' or 'disabled.')
    end
    function handlers.noclip(s,a)
        requireFeature('noclip'); captureMovement(s)
        local enabled=toggle(a.enabled,noclip)
        if enabled==noclip then return 'Noclip state unchanged.' end
        if enabled then
            local collision=s.pawn:GetActorEnableCollision()
            assert(type(collision)=='boolean', 'Collision state could not be read.')
            move.collision=collision
            noclipAnchor=vector(s.pawn:K2_GetActorLocation())
            noclip=true
            s.pawn:SetActorEnableCollision(false)
            assert(s.pawn:GetActorEnableCollision()==false, 'Collision was not disabled.')
        else
            -- Restore at the known pre-noclip location to avoid trapping the player in geometry.
            teleport(s.pawn,noclipAnchor,false)
            s.pawn:SetActorEnableCollision(move.collision)
            assert(s.pawn:GetActorEnableCollision()==move.collision, 'Collision was not restored.')
            noclip=false; noclipAnchor=nil;move.collision=nil
        end
        applyMovement(s)
        return enabled and 'Noclip enabled. Turning it off returns to your starting position.' or 'Noclip disabled; returned to your starting position.'
    end
    function handlers.speed(s,a)
        requireFeature('speed')
        assert(finite(a.multiplier) and a.multiplier>=0.25 and a.multiplier<=4, 'Speed must be between 0.25x and 4x.')
        captureMovement(s); speed=a.multiplier; applyMovement(s)
        return string.format('Movement speed: %.2fx.',speed)
    end
    function handlers.teleport(s,a)
        requireFeature('teleport'); jump(s,vector(a.position or a))
        return 'Teleported. Return is available in this world.'
    end
    function handlers.return_position(s)
        requireFeature('teleport')
        assert(returnPoint and returnPoint.world==s.worldId, 'No return position in this world.')
        local target=returnPoint.position; jump(s,target)
        return 'Returned to the previous position.'
    end
    local function waypointName(a)
        assert(type(a.name)=='string' and #a.name>=1 and #a.name<=32 and a.name:match('^[%w _%-]+$'), 'Waypoint names must use 1 to 32 letters, numbers, spaces, dashes or underscores.')
        return a.name
    end
    function handlers.save_waypoint(s,a)
        local name=waypointName(a)
        loadWaypoints(s)
        assert(waypoints[name] or count(waypoints)<20, 'At most 20 waypoints can be stored.')
        local p=vector(s.pawn:K2_GetActorLocation())
        waypointStore.save(s,name,p);loadWaypoints(s,true)
        return 'Waypoint saved: '..name..'.'
    end
    function handlers.teleport_waypoint(s,a)
        requireFeature('teleport')
        loadWaypoints(s)
        local name=waypointName(a); local point=waypoints[name]
        assert(point and point.world==s.worldId, 'No waypoint with that name in this world.')
        jump(s,point.position); return 'Teleported to '..name..'.'
    end
    function handlers.delete_waypoint(s,a)
        loadWaypoints(s)
        local name=waypointName(a); assert(waypoints[name], 'Waypoint not found.')
        waypointStore.delete(s,name);loadWaypoints(s,true)
        return 'Waypoint deleted.'
    end
    function handlers.teleport_destination(s,a)
        requireFeature('teleport_destination')
        local entry=destinations.resolve(a.id,s);jump(s,entry.position)
        return 'Teleported to '..entry.label..'. Return is available.'
    end
    local function vertical(s,a,direction)
        requireFeature('teleport'); assert(flight or noclip, 'Enable flight or noclip first.')
        local step=a.step or 100
        assert(finite(step) and step>=1 and step<=500, 'Vertical step must be between 1 and 500.')
        local p=vector(s.pawn:K2_GetActorLocation()); p.Z=p.Z+step*direction
        teleport(s.pawn,p,not noclip); return 'Moved vertically.'
    end
    function handlers.fly_up(s,a) return vertical(s,a,1) end
    function handlers.fly_down(s,a) return vertical(s,a,-1) end
    function handlers.spawn_item(s,a)
        requireFeature('spawn_item')
        local entry=lookup(catalog.items,a.id); local quantity=a.quantity or 1
        assert(finite(quantity) and quantity%1==0 and quantity>=1 and quantity<=10, 'Spawn quantity must be 1 to 10.')
        assert(#spawned+quantity<=30, 'Clear spawned actors before spawning more.')
        spawn(s,'spawn_item',entry,quantity)
        return 'Pickup spawned. Collecting it can be saved by the game.'
    end
    function handlers.spawn_enemy(s,a)
        requireFeature('spawn_enemy')
        local entry=lookup(catalog.enemies,a.id)
        assert(#spawned<30, 'Clear spawned actors before spawning more.')
        spawn(s,'spawn_enemy',entry,1);return 'Enemy spawn requested. Initialization may take a moment.'
    end
    function handlers.spawn_training(s,a)
        requireFeature('spawn_training')
        local entry=lookup(catalog.enemies,a.id)
        assert(#spawned<30,'Clear spawned actors before starting another training encounter.')
        spawn(s,'spawn_training',entry,1)
        return 'Training encounter created. No XP or item rewards.'
    end
    function handlers.clear_spawned()
        resetErrors={};cleanupActors()
        assert(#resetErrors==0,'Some spawned actors could not be removed.')
        if cleanupPending then return 'Enemy cleanup will finish after the active transition or combat.' end
        return 'Spawned actors removed. Already collected items are unchanged.'
    end
    function handlers.heal(s)
        requireFeature('heal'); assert(adapters.heal(s)==true,'Healing was not confirmed.');return 'Player healed.'
    end
    function handlers.god(s,a)
        requireFeature('god')
        if not god then
            if type(adapters.read_god)=='function' and type(adapters.god)=='function' then
                local value=adapters.read_god(s);assert(type(value)=='boolean','Original god-mode state is unknown.')
                god={value=value,enabled=false}
            else
                local manager=s.cheats or FindFirstOf('WrcCheatsManager')
                assert(valid(manager),'The cheat manager is unavailable.')
                local value=manager.GodMode
                assert(type(value)=='number' and value%1==0 and value>=0 and value<=15,'Original god-mode flags are unknown.')
                god={value=value,manager=manager,enabled=false}
            end
        end
        god.enabled=toggle(a.enabled,god.enabled)
        if god.manager then
            -- EGodModeTypeFlag::InfiniteLife=1; preserve Combat/Stealth/AvoidCombat.
            local value=god.enabled and (god.value | 1) or god.value
            god.manager.GodMode=value
            assert(god.manager.GodMode==value,'God mode was not confirmed.')
        else assert(adapters.god(s,god.enabled and true or god.value)==true,'God mode was not confirmed.') end
        return 'God mode '..(god.enabled and 'enabled.' or 'restored.')
    end
    function api.action(id,args)
        if id=='reset' then return api.reset('Temporary admin changes reset.') end
        if id=='fill_pile'or id=='set_bond'or id=='restore_bond'or id=='complete_quest'or id=='cancel_quest'then
            if not progression then return false,'Progression adapter is unavailable.' end
            if id~='cancel_quest'then local ok,why=pcall(guard);if not ok then return false,tostring(why)end end
            return progression.action(id,args)
        end
        local handler=handlers[id]
        if not handler then return false,'Unknown admin action.' end
        local ok,result=pcall(function() return handler(guard(),args or {}) end)
        if not ok then
            -- Restore partial mutations after adapter/property failures. Input errors
            -- also reset temporary changes, a predictable conservative failure policy.
            local resetOK,resetMessage=api.reset('Admin action failed.')
            return false,tostring(result)..(resetOK and '' or ' '..resetMessage)
        end
        return true,result
    end
    function api.progressionPreview(kind,args)
        if not progression then return false,'Progression adapter is unavailable.'end
        local ok,why=pcall(guard);if not ok then return false,tostring(why)end
        return progression.preview(kind,args)
    end
    function api.questState()return progression and progression.questState()or{status='unavailable'}end
    function api.flightActive()return not closed and not cleanupPending and(flight or noclip)end
    function api.destinations()
        local s,why=getSnapshot();if not s then return false,why end
        local ok,r=pcall(destinations.list,s);if not ok then return false,tostring(r)end;return true,r
    end
    -- Call each input tick only while gameplay controls are active. This submits
    -- a native movement direction; engine collision/acceleration remain intact.
    function api.verticalInput(axis)
        if not finite(axis)or axis < -1 or axis > 1 then return false,'Vertical input must be between -1 and 1.'end
        if axis==0 then return true end
        local ok,result=pcall(function()
            local s=guard();requireFeature('vertical_input')
            assert(flight or noclip,'Enable flight or noclip first.')
            assert(move and valid(move.component)and move.component.MovementMode==5,'Flying movement is unavailable.')
            if adapters.vertical_input then assert(adapters.vertical_input(s,axis)~=false,'Vertical movement was rejected.')
            else s.pawn:AddMovementInput({X=0,Y=0,Z=1},axis,false)end
            return true
        end)
        if not ok then return false,tostring(result)end;return result
    end
    -- Polling supplies whether any native horizontal binding is held. Do not
    -- replace those bindings or camera input; only arrest leftover momentum
    -- when the player releases every flight movement control.
    function api.flightInput(axis,horizontal)
        if type(horizontal)~='boolean'or not finite(axis)or math.abs(axis)>1 then return false,'Invalid flight input.'end
        local ok,result=pcall(function()
            local s=guard();requireFeature('vertical_input')
            assert(flight or noclip,'Enable flight or noclip first.')
            assert(move and valid(move.component)and move.component.MovementMode==5,'Flying movement is unavailable.')
            if axis==0 and not horizontal then
                move.component:StopMovementImmediately()
            elseif axis==0 and move.lastVertical and move.lastVertical~=0 then
                -- Horizontal input keeps native acceleration nonzero, so the
                -- engine's braking branch alone would not arrest ascent.
                local velocity=vector(move.component.Velocity)
                move.component.Velocity={X=velocity.X,Y=velocity.Y,Z=0}
            elseif axis~=0 then
                if adapters.vertical_input then assert(adapters.vertical_input(s,axis)~=false,'Vertical movement was rejected.')
                else s.pawn:AddMovementInput({X=0,Y=0,Z=1},axis,false)end
            end
            move.lastVertical=axis
            return true
        end)
        if not ok then return false,tostring(result)end;return result
    end
    function api.tick(seconds)
        if closed then return false,'Admin tools are shut down.' end
        local s,why=getSnapshot()
        if not s or (session and (session.worldId~=s.worldId or session.pawnId~=s.pawnId)) then
            return api.reset(why or 'World or player changed.')
        end
        if deferredNoclip then
            local ok,restored=pcall(restoreNoclip,deferredNoclip)
            if not ok then return false,tostring(restored)end
            if restored then deferredNoclip=nil else return true end
        end
        -- The game can override movement as controls change. Only reapply while
        -- the SAME positively offline exploration pawn remains active.
        if move and session then
            local ok,err=pcall(function() if flight or noclip or speed~=1 then applyMovement(s) end end)
            if not ok then api.reset('Movement update failed.');return false,tostring(err) end
        end
        if cleanupPending then
            resetErrors={};cleanupActors()
            if #resetErrors>0 then closed=true;return false,table.concat(resetErrors,'; ') end
        end
        local alive={};for _,a in ipairs(spawned) do if valid(a) then alive[#alive+1]=a end end;spawned=alive
        if progression then progression.tick(seconds)end
        return true
    end
    function api.capabilities()
        local s,why=getSnapshot()
        local waypointOK,waypointWhy=pcall(loadWaypoints,s)
        if not waypointOK then waypointError=tostring(waypointWhy);waypoints={};waypointScope=nil end
        local c={available=s~=nil and not closed and not cleanupPending and not deferredNoclip,reason=closed and 'Admin tools are shut down.' or (deferredNoclip and 'Waiting for exploration possession.'or cleanupPending and 'Waiting for enemy cleanup.' or why),
            flight=flight,noclip=noclip,speed=speed,god=god and god.enabled or false,spawned=#spawned,actions={},waypoints={},
            items=copyCatalog(catalog.items),enemies=copyCatalog(catalog.enemies),hasReturn=returnPoint~=nil,cleanupPending=cleanupPending,waypointError=waypointError}
        for _,id in ipairs({'flight','noclip','speed','teleport','spawn_item','spawn_enemy','spawn_training','heal','god','vertical_input','teleport_destination'}) do
            c.actions[id]={supported=supported(id),enabled=c.available and supported(id),
                reason=not supported(id) and 'Not yet verified for this game build.' or c.reason}
        end
        local pc=progression and progression.capabilities()or{}
        for id,feature in pairs({fill_pile='pile',set_bond='bonds',restore_bond='bonds',complete_quest='quests'})do
            c.actions[id]={supported=pc[feature]==true,enabled=c.available and pc[feature]==true,reason=pc[feature]~=true and'Not yet verified for this game build.'or c.reason}
        end
        for name,p in pairs(waypoints) do c.waypoints[#c.waypoints+1]={name=name,position=vector(p.position)} end
        table.sort(c.waypoints,function(a,b)return a.name<b.name end)
        return c
    end
    function api.shutdown()
        local ok,message=api.reset('Admin tools shut down.')
        if (cleanupPending or deferredNoclip)and ok then return false,'Finish the active combat or transition before disabling admin tools.' end
        closed=true;return ok,message
    end
    return api
end
return M
