local M=dofile('mods/ClanTools/Scripts/admin_waypoints.lua');local Admin=dofile('mods/ClanTools/Scripts/admin.lua');local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local raw;local ctx={characterKey=function(s)return s.profile..'_'..s.slot..'_'..(s.generation or'generation1')end,waypoint_read=function()return raw end,waypoint_write=function(value)raw=value;return true end}
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
 local writes=0;local a=M.new{characterKey=function()return'user_0_generation1'end,waypoint_read=function()return '{bad'end,waypoint_write=function()writes=writes+1 end}
 assert(not pcall(a.list,{profile='user',slot=0,worldId='world'}));assert(writes==0)
end)
test('returned positions are detached from stored state',function()
 local a,ctx,raw,s=fixture();a.save(s,'Camp',{X=1,Y=2,Z=3});local rows=a.list(s);rows.Camp.X=9;assert(a.list(s).Camp.X==1)
end)
print(passed..' waypoint persistence tests passed (model storage).')
test('recreated slot cannot see earlier character waypoints; missing identity never writes',function()
 local a,ctx,raw,s=fixture();s.generation='old';a.save(s,'Old Camp',{X=1,Y=2,Z=3})
 s.generation='new';assert(not a.list(s)['Old Camp']);a.save(s,'New Camp',{X=9,Y=8,Z=7})
 s.generation='old';assert(a.list(s)['Old Camp']and not a.list(s)['New Camp'])
 local previous=raw();ctx.characterKey=function()return nil,'Missing generation'end
 assert(not pcall(a.save,s,'Forbidden',{X=1,Y=2,Z=3}));assert(raw()==previous)
end)
test('ambiguous profile slot bookmarks are preserved without reuse',function()
 local bytes='{"version":1,"profiles":{"user":{"0":{"world":{"Old Camp":{"X":1,"Y":2,"Z":3}}}}}}'
 local ctx={characterKey=function()return'user_0_generation1'end,waypoint_read=function()return bytes end,waypoint_write=function(v)bytes=v;return true end}
 local a=M.new(ctx);local s={profile='user',slot=0,worldId='world'}
 assert(not a.list(s)['Old Camp']);a.save(s,'New Camp',{X=4,Y=5,Z=6})
 assert(dofile('mods/ClanTools/Scripts/json.lua').decode(bytes).profiles.user['0'].world['Old Camp'].X==1)
end)
