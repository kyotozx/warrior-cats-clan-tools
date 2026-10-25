local M=dofile('mods/ClanTools/Scripts/admin_map_travel.lua');local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function near(a,b)assert(math.abs(a-b)<0.000001,tostring(a)..' != '..tostring(b))end
local bounds={MapWidth=2000,MapHeight=1000,WorldMinX=-10000,WorldMaxX=30000,WorldMinY=-20000,WorldMaxY=60000}
local function fixture()
 local pawn={GetAddress=function()return 1 end};local s={offline=true,phase=4,worldId='world',profile='p',slot=0,pawn=pawn,pc={Pawn=pawn}}
 local calls={};local t=100;local floorZ=20;local cap={available=true,noclip=false}
 local ctx={snapshot=function()return s end,valid=function(o)return o~=nil end,mapTime=function()return t end,mapTravelVerified=true,
  admin={capabilities=function()return cap end,action=function(action,args)calls[#calls+1]={action=action,args=args};return true,'Teleported'end},
  mapAdapter={inspect=function()return{world={X=100,Y=200}}end,ground=function(_,p)return{X=p.X,Y=p.Y,Z=floorZ}end}}
 return M.new(ctx),s,ctx,calls,function(v)t=v end,function(v)floorZ=v end,cap
end
test('native projection swaps axes and reverses world X exactly',function()
 local a=M.world_to_map(bounds,{X=30000,Y=-20000});near(a.X,0);near(a.Y,0)
 local b=M.world_to_map(bounds,{X=-10000,Y=60000});near(b.X,2000);near(b.Y,1000)
 local p={X=1234,Y=5678};local q=M.map_to_world(bounds,M.world_to_map(bounds,p));near(q.X,p.X);near(q.Y,p.Y)
end)
test('outside map nonfinite and zero-size bounds are rejected',function()
 assert(not pcall(M.map_to_world,bounds,{X=-1,Y=1}));assert(not pcall(M.map_to_world,bounds,{X=1,Y=1001}));assert(not pcall(M.map_to_world,bounds,{X=0/0,Y=0}))
 assert(not pcall(M.map_to_world,{MapWidth=0,MapHeight=1,WorldMinX=0,WorldMaxX=1,WorldMinY=0,WorldMaxY=1},{X=0,Y=0}))
end)
test('canvas slot inversion follows native pan and zoom without opaque FGeometry',function()
 local a={min={X=.5,Y=.5},max={X=.5,Y=.5},left=-.19047500193119,top=-29.000003814697,right=3828.9523925781,bottom=1788.2855224609,align={X=.5,Y=.5}}
 local origin,size=M.canvas_rect(a,{X=0,Y=0})
 local unit={scale={X=1,Y=1},translation={X=0,Y=0},pivot={X=.5,Y=.5}}
 local point=M.canvas_inverse({X=0,Y=0},origin,size,unit)
 local zoom={scale={X=2.6599998474121,Y=2.6599998474121},translation={X=0,Y=0},pivot={X=.5,Y=.5}}
 point=M.canvas_inverse(point,{X=0,Y=0},size,zoom)
 unit.translation={X=-1210,Y=-1430};point=M.canvas_inverse(point,{X=0,Y=0},{X=4096,Y=4096},unit)
 near(point.X,3124.5478034368);near(point.Y,2335.0450189291)
 unit.scale.X=0;assert(not pcall(M.canvas_inverse,point,{X=0,Y=0},size,unit))
end)
test('preview is read only and confirmed travel consumes its token',function()
 local a,s,ctx,calls=fixture();local ok,p=a.preview();assert(ok and #calls==0);p.position.Z=999
 assert(a.travel(p.token));assert(#calls==1 and calls[1].args.position.Z==20);assert(not a.travel(p.token));assert(#calls==1)
end)
test('unknown build changed session expired preview and noclip do not teleport',function()
 local a,s,ctx,calls,time,ground,cap=fixture();local ok,p=a.preview();assert(ok);ctx.mapTravelVerified=false;assert(not a.travel(p.token));ctx.mapTravelVerified=true
 s.profile='other';assert(not a.travel(p.token));s.profile='p';time(131);assert(not a.travel(p.token));assert(#calls==0)
 cap.noclip=true;assert(not a.preview());assert(#calls==0)
end)
test('ground is checked again and changed or missing terrain blocks mutation',function()
 local a,s,ctx,calls,time,ground=fixture();local ok,p=a.preview();assert(ok);ground(50);assert(not a.travel(p.token));assert(#calls==0)
 ctx.mapAdapter.ground=function()error('Terrain not streamed')end;assert(not a.preview());assert(not a.travel(p.token));assert(#calls==0)
end)
test('admin encounter clearance rejection is respected and reports its reason',function()
 local a,s,ctx,calls=fixture();local ok,p=a.preview();assert(ok)
 ctx.admin.action=function()return false,'An encounter is too close'end;local success,why=a.travel(p.token);assert(not success and why:match('encounter'));assert(#calls==0)
end)
test('combat unpossession and reset discard access to old targets',function()
 local a,s,ctx,calls=fixture();local ok,p=a.preview();assert(ok);s.combat=true;assert(not a.travel(p.token));s.combat=false;s.pc.Pawn=nil;assert(not a.travel(p.token));s.pc.Pawn=s.pawn;a.reset();assert(not a.travel(p.token));assert(#calls==0)
end)
print(passed..' map travel tests passed (projection/model; live geometry and physics pending).')

