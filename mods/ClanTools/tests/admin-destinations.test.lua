local M=dofile('mods/ClanTools/Scripts/admin_destinations.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function object(t)t=t or{};t.valid=true;function t:IsValid()return self.valid end;return t end
local function fixture()
 local worldName='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P'
 local world=object{GetFullName=function()return worldName end}
 local level=object{OwningWorld=world,bIsVisible=true}
 local class=object{GetFullName=function()return'BlueprintGeneratedClass /Game/ActualPath/BP_QuestPlayerStart.BP_QuestPlayerStart_C'end}
 local actors={}
 for i=1,4 do actors[i]=object{Clan=i,pos={X=i*100,Y=200,Z=300},GetLevel=function()return level end,GetClass=function()return class end,K2_GetActorLocation=function(self)return self.pos end}end
 FindAllOf=function(name)assert(name=='SwtQuestPlayerStart');return actors end
 local s={offline=true,phase=4,worldId=worldName,pawn=object{}}
 return M.new({snapshot=function()return s end}),s,actors,level,world
end
test('native clan spawn names use loaded level ownership rather than outer streaming world',function()
 local a,s,actors=fixture();local rows=a.list();assert(#rows==4 and rows[4].id=='clan_spawn:4'and rows[4].label=='WindClan spawn point');assert(a.resolve('clan_spawn:4').position.X==400)
end)
test('resolution rereads coordinates and refuses hidden streamed level',function()
 local a,s,actors,level=fixture();a.list();actors[1].pos.X=150;assert(a.resolve('clan_spawn:1').position.X==150);level.bIsVisible=false;assert(#a.list()==0);assert(not pcall(a.resolve,'clan_spawn:1'))
end)
test('duplicate markers are omitted instead of selecting arbitrary actor',function()
 local a,s,actors=fixture();actors[#actors+1]=actors[1];assert(#a.list()==3);assert(not pcall(a.resolve,'clan_spawn:1'));assert(not pcall(a.resolve,'custom:99'))
end)
test('online unknown combat and nonfinite destinations fail closed',function()
 local a,s,actors=fixture();s.offline=nil;assert(not pcall(a.list));s.offline=true;s.combat=true;assert(not pcall(a.list));s.combat=false;actors[1].pos.Z=math.huge;assert(not pcall(a.list))
end)
FindAllOf=nil
print(passed..' named destination discovery tests passed (mock world markers).')
