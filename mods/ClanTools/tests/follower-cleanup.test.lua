local M=dofile('mods/ClanTools/Scripts/followers.lua')
local count=0
local function test(name,fn)fn();count=count+1;print('PASS '..name)end
local nextId=0
local function object(fields)
 fields=fields or{};fields.valid=true
 nextId=nextId+1;local id=nextId;function fields:GetAddress()return id end
 function fields:IsValid()return self.valid end
 function fields:K2_DestroyActor()self.valid=false end
 return fields
end
local function fixture(detachDestroys)
 local calls={detach=0,lifespan=0,unpossess=0,k2=0}
 local ctrl=object{StopMovement=function()end,IsPlayerController=function()return false end,
 UnPossess=function()calls.unpossess=calls.unpossess+1 end,SetLifeSpan=function(_,n)assert(n==.05);calls.lifespan=calls.lifespan+1 end,
 K2_DestroyActor=function()calls.k2=calls.k2+1 end}
 local class=object{GetFullName=function()return'BlueprintGeneratedClass /Game/Gameplay/Blueprints/Characters/ExplorationCharacters/BP_WalkingNPC_Character_Base.BP_WalkingNPC_Character_Base_C'end}
 local world=object{GetFullName=function()return'World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P'end,
 AuthorityGameMode={GetClass=function()return{GetFullName=function()return'BlueprintGeneratedClass /Game/Gameplay/Blueprints/Modes/BP_WrcGameplayGameMode.BP_WrcGameplayGameMode_C'end}end}}
 local pawn=object{GetWorld=function()return world end,K2_GetActorLocation=function()return{X=0,Y=0,Z=500}end,GetActorForwardVector=function()return{X=1,Y=0,Z=0}end,GetActorRightVector=function()return{X=0,Y=1,Z=0}end}
 pawn.CapsuleComponent={GetCollisionProfileName=function()return 'Pawn' end,GetScaledCapsuleHalfHeight=function()return 25 end}
 local actor=object{Controller=ctrl,GetClass=function()return class end,K2_GetActorLocation=function()return{X=400,Y=0,Z=500}end,CharacterMovement={NavMovementProperties={}},CapsuleComponent={SetGenerateOverlapEvents=function()end,SetCollisionResponseToChannel=function(_,channel,response)assert(channel==2 and response==0);calls.pawnIgnored=true end}}
 ctrl.Pawn=actor
 function actor:DetachFromControllerPendingDestroy()calls.detach=calls.detach+1;if detachDestroys then ctrl.valid=false end end
 StaticFindObject=function(path)
  if path=='/Script/Engine.Default__KismetSystemLibrary'then return{IsStandalone=function()return true end,LineTraceSingleByProfile=function(_,p,start,finish,profile,complex,ignored,debug,hit)hit.Time=.5;hit.Distance=350;hit.PenetrationDepth=0;hit.ImpactNormal={Z=1};hit.ImpactPoint={X=start.X,Y=start.Y,Z=540};return true end}end
  if path=='/Script/Engine.Default__GameplayStatics'then return{BeginDeferredActorSpawnFromClass=function(_,p,c,t)assert(t.Translation.Z==575,'Spawn must use the traced slope, not player height');return actor end,FinishSpawningActor=function()end}end
  return class
 end
 local owned=M.spawn_probe({offline=true,phase=4,clan=1,pawn=pawn},{role=3,clan=1,living=true},1,function()return true end)
 StaticFindObject=nil
 return owned,actor,ctrl,calls,pawn
end
test('pending pawn lifecycle retires owned controller without blueprint destroy',function()
 local owned,actor,controller,calls=fixture(true);assert(owned:destroy());assert(not actor.valid and not controller.valid);assert(calls.detach==1 and calls.k2==0 and calls.lifespan==0)
end)
test('reassigned controller is never unpossessed or retired',function()
 local owned,actor,controller,calls=fixture(false);controller.Pawn=object()
 assert(not pcall(owned.destroy,owned));assert(calls.detach==0 and calls.unpossess==0 and calls.lifespan==0 and actor.valid)
end)
test('player controller is rejected before pending-destroy lifecycle',function()
 local owned,actor,controller,calls=fixture(false);controller.IsPlayerController=function()return true end
 assert(not pcall(owned.destroy,owned));assert(calls.detach==0 and calls.unpossess==0 and calls.lifespan==0 and actor.valid)
end)
test('remaining controller uses lifespan once and retains pending cleanup',function()
 local owned,actor,controller,calls=fixture(false);local ok,why=pcall(function()owned:destroy()end);assert(not ok and tostring(why):find('controller=true',1,true));assert(not actor.valid and controller.valid);assert(calls.lifespan==1 and calls.k2==0)
 assert(not pcall(function()owned:destroy()end));assert(calls.lifespan==1);controller.valid=false;assert(owned:destroy());assert(calls.lifespan==1)
end)
test('failed native path uses direct movement without touching collision',function()
 local owned,actor,controller,calls,pawn=fixture(false);local paths={}
 controller.MoveToLocation=function(_,target,radius,stop,pathfinding)paths[#paths+1]=pathfinding;assert(radius==30);return pathfinding and 0 or 2 end
 assert(owned:follow(pawn,150,1));assert(#paths==2 and paths[1]==true and paths[2]==false);assert(calls.pawnIgnored)
end)
test('native already-at-goal and successful requests do not invoke fallback',function()
 for _,result in ipairs({1,2})do local owned,actor,controller,stats,pawn=fixture(false);local calls=0
 controller.MoveToLocation=function(_,target,radius,stop,pathfinding)assert(pathfinding);calls=calls+1;return result end
 assert(owned:follow(pawn,150,1));assert(calls==1)end
end)
print(count..' follower ownership, navigation and cleanup tests passed (mock lifecycle).')
