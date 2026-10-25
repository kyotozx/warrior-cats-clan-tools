-- Tests the adapter's ownership and deferred-initialization protocol, not AI.
local module=dofile('mods/ClanTools/Scripts/admin_enemy.lua')
local productionSpawn=module.spawn
local cleanupProbe=function()return true end
module.spawn=function(s,e,p,_,options)return productionSpawn(s,e,p,cleanupProbe,options)end
local catalog=dofile('mods/ClanTools/Scripts/admin_catalog.lua')
local passed=0
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function obj(t)
    t=t or {};t.valid=true
    function t:IsValid()return self.valid end
    function t:GetAddress()return self end
    function t:GetClass()return {GetFullName=function()return self.class or'BlueprintGeneratedClass /Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_Exploration_Character_Base.BP_Exploration_Character_Base_C'end}end
    function t:GetFullName()return 'ModelActor'end
    function t:K2_DestroyActor()self.valid=false end
    return t
end
local function fixture(failFinish,expectTraining)
    cleanupProbe=function()return true end
    local state=obj{CurrentPhase=4};local world=obj{GameState=state}
    local pawn=obj{};local generator=obj{};local children={};local finished=0
    local controller=obj{Pawn=pawn,IsPlayerController=function()return true end};pawn.Controller=controller;state.MainCharacter=pawn
    local level=obj{OwningWorld=world};function generator:GetLevel()return level end
    function generator:GetWorld()return world end
    generator.SpawnedPreys={GetArrayNum=function()return #children end,
        ForEach=function(_,fn)
            for i,child in ipairs(children)do
                fn(i,{get=function()return {Get=function()return child end}end})
            end
        end}
    for _,clan in ipairs({'ThunderClan','ShadowClan','RiverClan','WindClan'})do
        local setup={};generator[clan..'CombatTags']=setup
        for _,rank in ipairs({'Apprentice','Warrior','Deputy','Leader'})do setup[rank..'Setup']={}end
    end
    local statics=obj{}
    function statics:BeginDeferredActorSpawnFromClass(context,class,transform,collision,owner,scale)
        eq(context,pawn);eq(owner,pawn);eq(collision,2);return generator
    end
    function statics:FinishSpawningActor(actor,transform,scale)
        eq(actor,generator);finished=finished+1
        if expectTraining then eq(generator.CombatType,5)else eq(generator.CombatType,nil)end
        for _,clan in ipairs({'ThunderClan','ShadowClan','RiverClan','WindClan'})do
            for _,rank in ipairs({'Apprentice','Warrior','Deputy','Leader'})do
                eq(generator[clan..'CombatTags'][rank..'Setup'].TagName:ToString(),catalog.enemies[1].setupTag)
            end
        end
        if failFinish then error('simulated initialization failure')end
    end
    _G.StaticFindObject=function(path)if path:match('GameplayStatics$')then return statics end;return obj{}end
    _G.FName=function(text)return {ToString=function()return text end}end
    _G.FindAllOf=function(family)if family=='SwtAdventureCharacter'then return children end;return {}end
    local snapshot={offline=true,phase=4,pawn=pawn}
    return snapshot,generator,state,children,function()return finished end
end
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
test('initialization configures all ranks before BeginPlay and remains asynchronous',function()
    local s,g,state,children,fin=fixture()
    local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    eq(fin(),1);eq(g.SpawnQuantity,1);eq(#wrapper:get_children(),0)
    local child=obj{bAddsToRemovedLocalData=true,PreyGenerator=g};children[1]=child
    eq(wrapper:get_children()[1],child);eq(wrapper:IsValid(),true)
    wrapper:K2_DestroyActor();eq(child.valid,false);eq(child.bAddsToRemovedLocalData,false)
    eq(g.SpawnQuantity,0);eq(g.valid,false);eq(wrapper:IsValid(),false)
end)
test('cleanup is denied during combat and unknown world state',function()
    local s,g,state=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    state.CurrentPhase=5;eq(wrapper:CanCleanup(),false)
    state.CurrentPhase=4;eq(wrapper:CanCleanup(),true)
    state.valid=false;eq(wrapper:CanCleanup(),false)
end)
test('cleanup waits for director teardown and actual possession even in phase4',function()
    local s,g,state=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    state.Director=obj{};eq(wrapper:CanCleanup(),false);eq(wrapper:K2_DestroyActor(),'deferred');eq(g.valid,true);eq(g.SpawnQuantity,1)
    state.Director=nil;s.pawn.Controller.Pawn=nil;eq(wrapper:CanCleanup(),false);eq(wrapper:K2_DestroyActor(),'deferred');eq(g.valid,true)
    s.pawn.Controller.Pawn=s.pawn;eq(wrapper:CanCleanup(),true);wrapper:K2_DestroyActor();eq(g.valid,false)
end)
test('cleanup reads level owning world rather than streamed outer world',function()
    local s,g=fixture();function g:GetWorld()return obj{GameState=obj{CurrentPhase=5}}end
    local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100});eq(wrapper:CanCleanup(),true)
end)
test('failed initialization destroys the unreturned generator',function()
    local s,g=fixture(true)
    eq(pcall(module.spawn,s,catalog.enemies[1],{X=0,Y=0,Z=100}),false)
    eq(g.valid,false);eq(g.SpawnQuantity,0)
end)
test('online snapshots cannot allocate a generator',function()
    local s,g,state,children,fin=fixture();s.offline=false
    eq(pcall(module.spawn,s,catalog.enemies[1],{X=0,Y=0,Z=100}),false);eq(fin(),0)
end)
test('enumeration failure blocks all destruction and preserves retry ownership',function()
    local s,g=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    _G.FindAllOf=function()error('unsupported enumeration')end
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(g.valid,true);eq(g.SpawnQuantity,1);eq(wrapper:IsValid(),true)
    _G.FindAllOf=function()return {}end
    wrapper:K2_DestroyActor();eq(wrapper:IsValid(),false)
end)
test('captured player cannot become a cleanup child even if native generator field matches',function()
    local s,g,state,children=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    s.pawn.PreyGenerator=g;children[1]=s.pawn
    eq(#wrapper:get_children(),0);eq(pcall(function()wrapper:K2_DestroyActor()end),true);eq(s.pawn.valid,true);eq(g.valid,false)
end)
test('unexpected actor class blocks generator callbacks as well as child destruction',function()
    local s,g,state,children=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    local child=obj{PreyGenerator=g,class='BlueprintGeneratedClass PlayerClass'};children[1]=child
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(child.valid,true);eq(g.valid,true)
end)
test('player controller and changed ownership block destruction',function()
    local s,g,state,children=fixture();local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    local child=obj{PreyGenerator=g};children[1]=child;eq(#wrapper:get_children(),1)
    child.Controller=obj{IsPlayerController=function()return true end}
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(child.valid,true);eq(g.valid,true)
    child.Controller=nil;child.PreyGenerator=obj{}
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(child.valid,true);eq(g.valid,true)
end)
test('native weak array containing player blocks all cleanup writes',function()
    local s,g,state,children=fixture();cleanupProbe=function()error('Protected player is a weak child')end
    local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    local child=obj{PreyGenerator=g};children[1]=child;s.pawn.PreyGenerator=g;children[2]=s.pawn
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(g.SpawnQuantity,1);eq(g.valid,true);eq(child.valid,true);eq(s.pawn.valid,true)
end)
test('native weak array is rechecked after child callbacks before generator destruction',function()
    local s,g,state,children=fixture();local calls=0;cleanupProbe=function()calls=calls+1;return calls==1 end
    local wrapper=module.spawn(s,catalog.enemies[1],{X=0,Y=0,Z=100});local child=obj{PreyGenerator=g};children[1]=child
    eq(pcall(function()wrapper:K2_DestroyActor()end),false);eq(calls,2);eq(child.valid,false);eq(g.valid,true);eq(s.pawn.valid,true)
end)
test('training selects original Spar combat before BeginPlay and uses owned cleanup',function()
    local s,g,state,children,fin=fixture(false,true)
    local wrapper=module.spawn_training(s,catalog.enemies[1],{X=0,Y=0,Z=100})
    eq(fin(),1);eq(g.CombatType,5);eq(g.bIsQuestEncounter,false);eq(g.bIsBossFight,false);eq(g.bCheckBonding,false)
    local child=obj{PreyGenerator=g};children[1]=child;wrapper:K2_DestroyActor();eq(child.valid,false);eq(g.valid,false)
end)
test('training spawn cannot allocate during an ongoing combat',function()
    local s,g,state,children,fin=fixture(false,true);s.combat=true
    eq(pcall(module.spawn_training,s,catalog.enemies[1],{X=0,Y=0,Z=100}),false);eq(fin(),0)
end)
print(passed..' enemy adapter model tests passed.')

