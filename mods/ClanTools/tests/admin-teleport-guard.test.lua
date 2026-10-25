-- Model validation only; native runtime collection is tested separately.
local Guard=dofile('mods/ClanTools/Scripts/admin_teleport_guard.lua')
local original=FindAllOf
local actors,passed={},0
FindAllOf=function(class)assert(class=='SwtAdventureCharacter');return actors end
local function obj(t)t=t or{};function t:IsValid()return self.valid~=false end;return t end
local function enemy(x,y,z,world)
 local level=obj{bIsVisible=true,OwningWorld=obj{GetFullName=function()return world or'WorldA'end}}
 return obj{PreyGenerator=obj(),GetLevel=function()return level end,K2_GetActorLocation=function()return{X=x,Y=y,Z=z}end},level
end
local s={offline=true,phase=4,worldId='WorldA'}
local target={X=0,Y=0,Z=0}
local function test(name,fn)
 local ok,err=xpcall(fn,debug.traceback)
 if not ok then FindAllOf=original;error(name..': '..err)end
 passed=passed+1;print('PASS '..name)
end
test('loaded nearby encounter blocks landing',function()
 actors={(enemy(300,0,300))};local ok,why=Guard.check(s,target);assert(not ok and why:match('too close'))
end)
test('distant or vertically separated encounters permit landing',function()
 actors={(enemy(301,0,0)),(enemy(0,0,301))};assert(Guard.check(s,target))
end)
test('streamed level owning world governs membership',function()
 actors={(enemy(0,0,0,'OtherWorld'))};assert(Guard.check(s,target))
 local e,l=enemy(0,0,0);l.bIsVisible=false;actors={e};assert(Guard.check(s,target))
end)
test('friendly actors and destroyed wrappers are excluded',function()
 local e=enemy(0,0,0);e.PreyGenerator=nil
 local dead=enemy(0,0,0);dead.valid=false;dead.GetLevel=function()error('stale actor access')end
 actors={e,dead};assert(Guard.check(s,target))
end)
test('inspection failure blocks without touching actors',function()
 local e=enemy(0,0,0);e.GetLevel=function()error('stream transition')end
 actors={e};local ok,why=Guard.check(s,target);assert(not ok and why:match('Cannot verify'))
end)
test('invalid position or unknown session fails closed',function()
 actors={};assert(not Guard.check(s,{X=0/0,Y=0,Z=0}));assert(not Guard.check({phase=4},target))
end)
test('postcombat player generator relation is not an enemy landing obstruction',function()
 local e=enemy(0,0,0);e.Controller=obj{IsPlayerController=function()return true end};actors={e};assert(Guard.check(s,target))
end)
FindAllOf=original
print(passed..' teleport clearance model tests passed.')

