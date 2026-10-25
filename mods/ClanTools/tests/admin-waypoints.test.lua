local M=dofile('mods/ClanTools/Scripts/admin_waypoints.lua');local Admin=dofile('mods/ClanTools/Scripts/admin.lua');local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local raw;local ctx={waypoint_read=function()return raw end,waypoint_write=function(value)raw=value;return true end}
 return M.new(ctx),ctx,function()return raw end,{profile='user',slot=0,worldId='world'}
end
test('waypoints survive fresh module reload and remain profile slot world scoped',function()
 local a,ctx,raw,s=fixture();a.save(s,'Camp',{X=1,Y=2,Z=3});local b=M.new(ctx);assert(b.list(s).Camp.Z==3)
 s.profile='other';assert(not b.list(s).Camp);s.profile='user';s.slot=1;assert(not b.list(s).Camp);s.slot=0;s.worldId='other';assert(not b.list(s).Camp)
 s.worldId='world';assert(b.list(s).Camp.X==1);b.delete(s,'Camp');assert(not M.new(ctx).list(s).Camp)
end)
test('failed persistence leaves original in-memory and persisted bookmarks intact',function()
 local a,ctx,raw,s=fixture();a.save(s,'Camp',{X=1,Y=2,Z=3});local original=raw();ctx.waypoint_write=function()return false end
 assert(not pcall(a.save,s,'Camp',{X=9,Y=8,Z=7}));assert(raw()==original and a.list(s).Camp.X==1)
end)
test('bad coordinates names and over-cap entries rejected before saving',function()
 local a,ctx,raw,s=fixture();assert(not pcall(a.save,s,'../unsafe',{X=1,Y=2,Z=3}));assert(not pcall(a.save,s,'Camp',{X=0/0,Y=2,Z=3}));assert(not raw())
 for i=1,20 do a.save(s,'Point '..i,{X=i,Y=2,Z=3})end
 assert(not pcall(a.save,s,'Extra',{X=1,Y=2,Z=3}));assert(a.save(s,'Point 1',{X=5,Y=2,Z=3}))
end)
test('corrupt storage fails closed without overwriting it',function()
 local writes=0;local a=M.new{waypoint_read=function()return '{bad'end,waypoint_write=function()writes=writes+1 end}
 assert(not pcall(a.list,{profile='user',slot=0,worldId='world'}));assert(writes==0)
end)
test('returned positions are detached from stored state',function()
 local a,ctx,raw,s=fixture();a.save(s,'Camp',{X=1,Y=2,Z=3});local rows=a.list(s);rows.Camp.X=9;assert(a.list(s).Camp.X==1)
end)
print(passed..' waypoint persistence tests passed (model storage).')
