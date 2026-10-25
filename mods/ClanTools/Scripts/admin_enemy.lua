-- Real game encounter generator, configured before BeginPlay.
-- Enable only after root-owned live probes confirm spawning AND cleanup.
local M={}
local generatorPath='/Game/Gameplay/Blueprints/WorldElements/BP_Enemy_Generator.BP_Enemy_Generator_C'
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
-- Recovery helper accepts only a generator the caller itself just created.
function M.track_owned(generator,protectedPlayer,cleanupProbe)
    assert(valid(generator),'Owned generator unavailable.')
    assert(valid(protectedPlayer),'Original player identity is required for encounter cleanup.')
    local generatorId=generator:GetAddress()
    local children={}
    local wrapper={generator=generator};local cleanupError=false;local ownedWorld
    local protectedId=valid(protectedPlayer)and protectedPlayer:GetAddress()or nil
    local function audit(message)print('[ClanTools] [EnemyCleanup] '..message)end
    local enemyClass='BlueprintGeneratedClass /Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_Exploration_Character_Base.BP_Exploration_Character_Base_C'
    local function isProtected(actor)
        if actor:GetAddress()==protectedId then return true end
        local controller=actor.Controller
        return valid(controller)and controller:IsPlayerController()==true
    end
    local function inspectNativeChildren()
        if not valid(generator)then return end
        cleanupProbe=cleanupProbe or dofile(folder..'admin_enemy_cleanup.lua').new()
        assert(cleanupProbe(generator,protectedPlayer)==true,'Native encounter ownership could not be verified.')
    end
    local function assertOwnedEnemy(actor)
        assert(valid(actor),'Owned enemy is no longer available.')
        assert(actor:GetAddress()~=protectedId,'Refusing to destroy the player.')
        assert(actor:GetClass():GetFullName()==enemyClass,'Unexpected actor references the owned encounter generator; cleanup blocked.')
        local controller=actor.Controller
        assert(not valid(controller)or controller:IsPlayerController()==false,'Refusing to destroy a player-controlled pawn.')
        assert(valid(generator)and valid(actor.PreyGenerator)and actor.PreyGenerator:GetAddress()==generatorId,'Enemy ownership changed; cleanup blocked.')
    end
    local function collect()
        -- UE4SS cannot marshal TArray<TWeakObjectPtr> elements in this build.
        -- Both actual prey families instead expose a direct PreyGenerator field.
        for _,family in ipairs({'SwtAdventureCharacter','WrcPouncePrey'})do
            for _,actor in ipairs(FindAllOf(family) or {})do
                if valid(actor)and not isProtected(actor)then
                    local owner=actor.PreyGenerator
                    local ok,id=pcall(function()return owner:GetAddress()end)
                    if ok and id==generatorId then
                        assertOwnedEnemy(actor)
                        children[actor:GetAddress()]={actor=actor,quest=family=='SwtAdventureCharacter'}
                    end
                end
            end
        end
    end
    function wrapper:IsValid()
        if valid(generator) or cleanupError then return true end
        for _,child in pairs(children)do if valid(child.actor)then return true end end
        return false
    end
    function wrapper:GetAddress()return generatorId end
    function wrapper:CanCleanup()
        local source=valid(generator)and generator or nil
        if not source then for _,child in pairs(children)do if valid(child.actor)then source=child.actor;break end end end
        if not source then return true end
        local ok,allowed=pcall(function()
            if valid(generator)or not valid(ownedWorld)then
                local level=source:GetLevel();if not valid(level)then return false end
                ownedWorld=level.OwningWorld
            end
            if not valid(ownedWorld)then return false end
            local state=ownedWorld.GameState
            if not valid(state)or state.CurrentPhase~=4 or valid(state.Director)then return false end
            local player=state.MainCharacter;if not valid(player)then return false end
            local controller=player.Controller
            return valid(controller)and controller:IsPlayerController()==true and valid(controller.Pawn)and controller.Pawn:GetAddress()==player:GetAddress()
        end)
        return ok and allowed==true
    end
    function wrapper:K2_DestroyActor()
        if not self:CanCleanup()then return 'deferred'end
        -- Verify the complete ownership set before touching anything. Destroying
        -- the generator itself can run native child callbacks, so an ambiguous
        -- child must block generator destruction as well.
        local ownershipOK,ownershipError=pcall(function()
            collect()
            for _,child in pairs(children)do if valid(child.actor)then assertOwnedEnemy(child.actor)end end
            inspectNativeChildren()
        end)
        if not ownershipOK then
            if not cleanupError then audit('Ownership refused: '..tostring(ownershipError))end
            cleanupError=true;error(ownershipError)
        end
        local errors={}
        local function attempt(fn)local ok,err=pcall(fn);if not ok then errors[#errors+1]=tostring(err)end end
        if valid(generator)then attempt(function()generator.SpawnQuantity=0 end)end
        for _,child in pairs(children)do
            local actor=child.actor
            if valid(actor)then attempt(function()
                assertOwnedEnemy(actor)
                audit('Destroy child '..actor:GetFullName()..' address='..tostring(actor:GetAddress())..' generator='..tostring(generatorId)..' protectedPlayer='..tostring(protectedId))
                if child.quest then actor.bAddsToRemovedLocalData=false end
                actor:K2_DestroyActor()
            end)end
        end
        if #errors==0 and valid(generator)then attempt(function()
            inspectNativeChildren()
            audit('Destroy generator '..generator:GetFullName()..' address='..tostring(generatorId)..' protectedPlayer='..tostring(protectedId))
            generator:K2_DestroyActor()
        end)end
        cleanupError=#errors>0
        assert(not cleanupError,table.concat(errors,'; '))
        local survivors={}
        for id,child in pairs(children)do if valid(child.actor)then survivors[id]=child end end
        children=survivors
        if valid(generator) or next(children)then return 'deferred' end
        return true
    end
    function wrapper:get_children()
        collect();local out={};for _,child in pairs(children)do if valid(child.actor)then out[#out+1]=child.actor end end;return out
    end
    return wrapper
end
function M.spawn(snapshot,entry,position,cleanupProbe,options)
    options=options or{}
    assert(snapshot.offline==true and snapshot.phase==4 and not snapshot.combat,'Enemy spawning requires offline exploration.')
    assert(options.training==nil or type(options.training)=='boolean','Invalid encounter mode.')
    assert(entry and type(entry.setupTag)=='string' and entry.setupTag:match('^Gameplay%.Combat%.Generator%.Fixed%.'),'Unsupported encounter setup.')
    local pawn=snapshot.pawn;assert(valid(pawn),'Player unavailable.')
    local class=StaticFindObject(generatorPath)
    if not valid(class) then class=LoadAsset(generatorPath) end
    assert(valid(class),'Enemy generator class unavailable.')
    local statics=StaticFindObject('/Script/Engine.Default__GameplayStatics')
    assert(valid(statics),'Gameplay statics unavailable.')
    local transform={Rotation={X=0,Y=0,Z=0,W=1},Translation=position,Scale3D={X=1,Y=1,Z=1}}
    local generator=statics:BeginDeferredActorSpawnFromClass(pawn,class,transform,2,pawn,0)
    assert(valid(generator),'The game did not create an enemy generator.')
    local wrapper=M.track_owned(generator,pawn,cleanupProbe)
    local ok,err=pcall(function()
        generator.SpawnQuantity=1
        generator.bAvailableAtStart=true
        generator.bIsQuestEncounter=false
        generator.bIsBossFight=false
        generator.bCheckBonding=false
        generator.bUseQuestCombatTag=false
        if options.training then
            -- Native CombatManager maps TrainingGrounds (5) to the game's
            -- Spar director. Its finish handler omits XP and inventory rewards.
            generator.CombatType=5
            assert(generator.CombatType==5,'The generator refused training mode.')
        end
        local tag=FName(entry.setupTag)
        assert(tag:ToString()==entry.setupTag,'The encounter tag is not available.')
        for _,clan in ipairs({'ThunderClan','ShadowClan','RiverClan','WindClan'})do
            local setup=generator[clan..'CombatTags']
            for _,rank in ipairs({'Apprentice','Warrior','Deputy','Leader'})do setup[rank..'Setup'].TagName=tag end
        end
        statics:FinishSpawningActor(generator,transform,0)
        assert(valid(generator),'Enemy generator was destroyed during initialization.')
        -- bAvailableAtStart lets BeginPlay start the normal asynchronous spawn.
        -- Do not call UpdateGenerator immediately as an empty array may mean
        -- initialization is still pending, which could queue a duplicate spawn.
    end)
    if not ok then pcall(function()wrapper:K2_DestroyActor()end);error(err) end
    return wrapper
end
function M.spawn_training(snapshot,entry,position,cleanupProbe)
    return M.spawn(snapshot,entry,position,cleanupProbe,{training=true})
end
return M
