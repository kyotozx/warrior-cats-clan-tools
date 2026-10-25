local M=dofile('mods/ClanTools/Scripts/followers_integration.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture(persisted)
 local s={offline=true,phase=4,clan=1,profile='p',slot=0,chapter=1,worldId='world',pawn={GetAddress=function()return 123 end}}
 local cats={{role=2,living=true,clan=1},{role=3,living=true,clan=1},{role=4,living=true,clan=2}}
 local party={{role=2},{role=3}};local active={};local calls={select=0,reset=0,saves=0};local verified=true
 local driver={state=function()return{active=#active,roles=active}end,tick=function()if calls.navigationFailure then return false,'[FOLLOWER_NAVIGATION] No path'end;return true end,reset=function()calls.reset=calls.reset+1;if calls.cleanupFailure then return false,'Cleanup pending'end;active={};return true end,
 select=function(roles)calls.select=calls.select+1;if calls.spawnFailure then return false,'Spawn failed'end;active=roles;return true end,shutdown=function()if calls.cleanupFailure then return false,'Cleanup pending'end;active={};return true end}
 local api=M.new({snapshot=function()return s end,getCats=function()return cats,{valid=true,profile=s.profile,slot=s.slot}end,party={read=function()return party end}},
 {driver=driver,environment=function()return not calls.housing,'Followers wait outside dens.'end,verified=function()return verified end,load=function()return persisted end,save=function(v)calls.saves=calls.saves+1;calls.persisted=v;return true end})
 return api,s,cats,party,calls,function(v)verified=v end
end
test('persisted opt-in waits for stable exploration then follows actual party',function()
 local a,s,c,p,calls=fixture(true);assert(a.tick(0));assert(calls.select==0);assert(a.tick(1));assert(calls.select==1 and a.state().active==2);assert(a.tick(1.5));assert(calls.select==1);p[2]={role=4};assert(a.tick(2));assert(calls.select==2 and a.state().active==1);assert(calls.saves==0)
end)
test('online unknown combat and profile transitions dismiss owned visuals',function()
 local a,s,c,p,calls=fixture(true);a.tick(0);a.tick(1);s.offline=nil;a.tick(2);assert(a.state().active==0);s.offline=true;a.tick(3);a.tick(4);assert(a.state().active==2);s.combat=true;a.tick(5);assert(a.state().active==0);s.combat=false;a.tick(6);a.tick(7);s.profile='other';a.tick(8);assert(a.state().active==0);a.tick(9);assert(a.state().active==2)
end)
test('toggle preference persists without changing native party or save actors',function()
 local a,s,c,p,calls=fixture(false);a.tick(0);a.tick(1);assert(calls.select==0);assert(a.set_enabled(true));assert(calls.persisted==true);a.tick(2);a.tick(3);assert(a.state().active==2);assert(a.set_enabled(false));assert(calls.persisted==false and a.state().active==0 and #p==2)
end)
test('unverified build cannot spawn even with persisted preference',function()
 local a,s,c,p,calls,gate=fixture(true);gate(false);a.tick(0);a.tick(1);assert(calls.select==0);assert(not a.set_enabled(true));assert(a.set_enabled(false))
end)
test('failed spawn does not loop and explicit retry revalidates party',function()
 local a,s,c,p,calls=fixture(true);calls.spawnFailure=true;a.tick(0);assert(not a.tick(1));assert(a.state().error);a.tick(2);a.tick(3);assert(calls.select==1);calls.spawnFailure=false;assert(a.set_enabled(true));a.tick(4);a.tick(5);assert(calls.select==2 and a.state().active==2)
end)
test('shutdown retains cleanup retry and keeps preference',function()
 local a,s,c,p,calls=fixture(true);a.tick(0);a.tick(1);calls.cleanupFailure=true;assert(not a.shutdown());assert(a.state().active==2);calls.cleanupFailure=false;assert(a.shutdown());assert(a.state().active==0 and a.state().enabled);assert(not a.tick(2));assert(calls.saves==0)
end)
test('housing suspends and resumes the selected party without a sticky error',function()
 local a,s,c,p,calls=fixture(true);a.tick(0);a.tick(1);assert(a.state().active==2);calls.housing=true;a.tick(2);assert(a.state().active==0 and a.state().suspended and not a.state().error);a.tick(3);assert(calls.select==1);calls.housing=false;a.tick(4);a.tick(5);assert(a.state().active==2 and not a.state().suspended and not a.state().error)
end)
test('navigation failure cleans up and retries after cooldown',function()
 local a,s,c,p,calls=fixture(true);a.tick(0);a.tick(1);calls.navigationFailure=true;assert(a.tick(2));assert(a.state().active==0 and a.state().suspended);calls.navigationFailure=false;for i=3,6 do a.tick(i)end;assert(calls.select==1);a.tick(7);a.tick(8);assert(a.state().active==2 and not a.state().error)
end)
test('temporary paused cleanup does not latch after housing exit',function()
 local a,s,c,p,calls=fixture(true);a.tick(0);a.tick(1);calls.housing=true;calls.cleanupFailure=true;assert(not a.tick(2));assert(a.state().error);calls.cleanupFailure=false;assert(a.tick(3));assert(not a.state().error);calls.housing=false;a.tick(4);a.tick(5);assert(a.state().active==2 and not a.state().error)
end)
test('legacy preference migrates with default distance and v2 reloads chosen distance',function()
 local json=dofile('mods/ClanTools/Scripts/json.lua');local raw='{"version":1,"enabled":true}';local distance
 local driver={state=function()return{active=0}end,set_distance=function(v)distance=v;return true end}
 local ctx={root='x/',snapshot=function()end,getCats=function()end,party={read=function()end},json=json,
 read=function()return raw end,write=function(_,v)raw=v end}
 local a=M.new(ctx,{driver=driver});assert(a.state().enabled and a.state().distance==150 and distance==150)
 assert(a.set_distance(350));local saved=json.decode(raw);assert(saved.version==2 and saved.enabled and saved.distance==350)
 local b=M.new(ctx,{driver=driver});assert(b.state().distance==350 and distance==350)
end)
test('distance storage failure restores the active controller setting',function()
 local distance=150;local driver={state=function()return{active=0}end,set_distance=function(v)distance=v;return true end}
 local ctx={snapshot=function()end,getCats=function()end,party={read=function()end}}
 local a=M.new(ctx,{driver=driver,load=function()return false end,save=function()error('disk unavailable')end})
 assert(not a.set_distance(350));assert(a.state().distance==150 and distance==150)
end)
print(passed..' follower integration tests passed (mock lifecycle).')
