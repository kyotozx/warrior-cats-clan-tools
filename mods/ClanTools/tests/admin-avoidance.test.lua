local M=dofile('mods/ClanTools/Scripts/admin_avoidance.lua');local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local serial=0
local function object(v)serial=serial+1;v=v or{};v.id=serial;v.valid=true;function v:GetAddress()return self.id end;return v end
local function fixture()
 local pawn=object{pos={X=10000,Y=0,Z=0}};function pawn:K2_GetActorLocation()return self.pos end
 local pc=object{Pawn=pawn};local s={offline=true,phase=4,worldId='world',profile='profile',slot=0,pawn=pawn,pc=pc}
 local enemies={};local touched=0
 local function enemy(x)
  local a=object{supported=true,components={}};function a:GetActorEnableCollision()return not self.sleeping end
  for i=1,2 do
   local c=object{mode=i,center={X=x or 0,Y=0,Z=0},radius=100,writes=0}
   c.BodyInstance=setmetatable({},{__index=function(_,key)if key=='CollisionEnabled'then return c.mode end end,__newindex=function(_,key,value)assert(key=='CollisionEnabled');c.mode=value end})
   function c:GetCollisionEnabled()return a.sleeping and 0 or self.mode end
   function c:SetCollisionEnabled(n)self.writes=self.writes+1;touched=touched+1;if self.fail then error('native setter failed')end;if self:GetCollisionEnabled()==n then return end;self.mode=n end
   function c:K2_GetComponentLocation()return self.center end
   a.components[i]={object=c,radius=c.radius}
  end
  enemies[#enemies+1]=a;return a
 end
 local ctx={snapshot=function()return s end,valid=function(o)return o and o.valid==true end,avoidanceVerified=true,
  avoidanceAdapter={validate_world=function()return true end,supported=function(a)return a.supported end,actors=function()return enemies end,components=function(a)return a.components end}}
 return M.new(ctx),s,enemy,enemies,ctx,function()return touched end
end
test('only supported enemies change and original query modes restore',function()
 local a,s,make,list=fixture();local e=make();local other=make();other.supported=false
 assert(a.set_enabled(true));assert(e.components[1].object.mode==0);assert(e.components[2].object.mode==0);assert(other.components[1].object.mode==1)
 assert(a.reset());assert(e.components[1].object.mode==1 and e.components[2].object.mode==2);assert(a.status().count==0)
end)
test('distant actor collision does not mask intrinsic component restoration',function()
 local a,s,make=fixture();local e=make();e.sleeping=true
 assert(a.set_enabled(true));assert(a.reset());assert(e.components[1].object.mode==1 and e.components[2].object.mode==2);assert(not a.status().restoring)
end)
test('restoration near player defers until full query radius is clear',function()
 local a,s,make=fixture();local e=make();assert(a.set_enabled(true));s.pawn.pos.X=200
 local ok,why=a.reset();assert(ok and why:match('Restoring'));assert(a.status().restoring);assert(e.components[1].object.mode==0)
 assert(not a.set_enabled(true));assert(not a.shutdown());s.pawn.pos.X=1000;assert(a.tick());assert(not a.status().restoring);assert(e.components[2].object.mode==2);assert(a.shutdown())
end)
test('combat and unpossession defer collision reactivation',function()
 local a,s,make=fixture();local e=make();a.set_enabled(true);s.combat=true;a.tick();assert(a.status().restoring);assert(e.components[1].object.mode==0)
 s.combat=false;s.pc.Pawn=nil;a.tick();assert(e.components[1].object.mode==0);s.pc.Pawn=s.pawn;a.tick();assert(e.components[1].object.mode==1)
end)
test('new enemies are captured and unloaded actors are forgotten',function()
 local a,s,make=fixture();a.set_enabled(true);local e=make();a.tick();assert(e.components[1].object.mode==0);e.valid=false;a.tick();assert(a.status().count==0)
end)
test('partial native failure retains restoration and can be retried',function()
 local a,s,make=fixture();local e=make();e.components[2].object.fail=true
 assert(not a.set_enabled(true));assert(a.status().restoring);e.components[2].object.fail=false;a.tick();assert(e.components[1].object.mode==1 and e.components[2].object.mode==2);assert(not a.status().restoring)
end)
test('offline validation and verification gate block before any mutation',function()
 local a,s,make,list,ctx,writes=fixture();make();ctx.avoidanceVerified=false;assert(not a.set_enabled(true));assert(writes()==0)
 ctx.avoidanceVerified=true;s.offline=false;assert(not a.set_enabled(true));assert(writes()==0);s.offline=true;s.pc.Pawn=nil;assert(not a.set_enabled(true));assert(writes()==0)
end)
test('world replacement never changes new-world components with old restore records',function()
 local a,s,make=fixture();local e=make();a.set_enabled(true);s.worldId='another';a.tick();assert(a.status().restoring);assert(e.components[1].object.mode==0)
 e.valid=false;a.tick();assert(not a.status().restoring)
end)
test('originally disabled components remain disabled and need no proximity wait',function()
 local a,s,make=fixture();local e=make();for _,c in ipairs(e.components)do c.object.mode=0 end;a.set_enabled(true);s.pawn.pos.X=0
 assert(a.reset());assert(not a.status().restoring);assert(e.components[1].object.mode==0)
end)
test('invalid component radius fails before mutation',function()
 local a,s,make,list,ctx,writes=fixture();local e=make();e.components[2].radius=0/0;assert(not a.set_enabled(true));assert(writes()==0)
end)
print(passed..' avoidance tests passed (model only).')
