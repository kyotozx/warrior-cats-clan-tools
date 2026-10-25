local M=dofile('mods/ClanTools/Scripts/follower_environment.lua')
local valid=function(x)return type(x)=='table'and not x.invalid end
local function object(id)return{GetAddress=function()return id end}end
local world=object(1);local level={bIsVisible=true,OwningWorld=world};local doors={};local projections={true,true,true}
local pawn={GetLevel=function()return level end,K2_GetActorLocation=function()return{X=100,Y=200,Z=300}end,GetActorForwardVector=function()return{X=1,Y=0,Z=0}end,GetActorRightVector=function()return{X=0,Y=1,Z=0}end}
local mathLib={IsPointInBoxWithTransform=function(_,_,transform)return transform.contains end}
local calls=0;local nav={K2_ProjectPointToNavigation=function()calls=calls+1;return projections[calls]end}
StaticFindObject=function(path)return path:find('NavigationSystem',1,true)and nav or mathLib end
FindAllOf=function()return doors end
local function door(inside,otherWorld)
 local l={bIsVisible=true,OwningWorld=otherWorld or world}
 return{bIsExit=true,GetLevel=function()return l end,HotspotsContainerAreaComponent={GetUnscaledBoxExtent=function()return{X=50,Y=50,Z=50}end,K2_GetComponentToWorld=function()return{contains=inside}end}}
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('actual same-world housing volume suspends without requiring hotspots',function()doors={door(true)};local ready,reason=M.new({valid=valid})({pawn=pawn});assert(not ready and reason=='Followers wait outside dens.')end)
test('foreign worlds and noncontaining boxes do not suspend',function()doors={door(true,object(2)),door(false)};assert(M.new({valid=valid})({pawn=pawn}))end)
test('navigation checks all intended spawn locations and fails closed',function()doors={};calls=0;projections={true,true,true};assert(M.new({valid=valid,followerNavPreflight=true})({pawn=pawn}));assert(calls==3);calls=0;projections={true,false,true};assert(not M.new({valid=valid,followerNavPreflight=true})({pawn=pawn}));assert(calls==2)end)
print(n..' follower environment tests passed (mock reflected API).')
