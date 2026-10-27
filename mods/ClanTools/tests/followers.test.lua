local M=dofile('mods/ClanTools/Scripts/followers.lua')
local function eq(a,b)assert(a==b,tostring(a)..' ~= '..tostring(b))end
local function fixture()
    local pawn={IsValid=function()return true end,GetAddress=function()return 100 end}
    local s={offline=true,phase=4,clan=1,worldId='WorldA',pawn=pawn}
    local cats={{role=7,clan=1,living=true},{role=8,clan=1,living=true},{role=9,clan=2,living=true}}
    local made={};local ctx={verified=true,snapshot=function()return s end,getCats=function()return cats end,validate=function()return true end}
    ctx.spawn=function(_,cat,i)
        local f={alive=true,role=cat.role,moves=0}
        function f:IsValid()return self.alive end
        function f:follow(target,distance)eq(target,pawn);self.moves=self.moves+1;self.distance=distance;return true end
        function f:stay()self.stops=(self.stops or 0)+1;return true end
        function f:distance_to()return self.currentDistance or 400 end
        function f:update_appearance(_,cat)self.appearanceUpdates=(self.appearanceUpdates or 0)+1;self.custom=cat.custom;return true end
        function f:destroy()self.alive=false;return true end
        made[#made+1]=f;return f
    end
    return M.new(ctx),ctx,s,cats,made
end
local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('empty follower selection does not inspect the world or clan roster',function()
    local f,c=fixture();assert(f.select({}))
    c.snapshot=function()error('Empty followers queried the world')end
    c.getCats=function()error('Empty followers read the roster')end
    for i=1,100 do assert(f.tick(i))end
end)
test('unknown session and unverified navigation cannot spawn',function()
    local f,c,s,cats,made=fixture();s.offline=nil;eq(f.select({7}),false);eq(#made,0)
    s.offline=true;c.verified=false;eq(f.select({7}),false);eq(#made,0)
end)
test('selection rejects duplicates other clans and more than two',function()
    local f,c,s,cats,made=fixture()
    eq(f.select({7,7}),false);eq(f.select({9}),false);eq(f.select({7,8,9}),false);eq(#made,0)
end)
test('partial spawn failure cleans already allocated owned companions',function()
    local f,c,s,cats,made=fixture();local spawn=c.spawn
    c.spawn=function(a,b,i)if i==2 then error('second follower failed')end;return spawn(a,b,i)end
    eq(f.select({7,8}),false);eq(made[1].alive,false);eq(f.state().active,0)
end)
test('phase and world changes dismiss all owned followers',function()
    for _,change in ipairs({function(s)s.phase=5 end,function(s)s.worldId='WorldB'end,function(s)s.offline=false end})do
        local f,c,s,cats,made=fixture();eq(f.select({7,8}),true);change(s);f.tick(1)
        eq(made[1].alive,false);eq(made[2].alive,false);eq(f.state().active,0)
    end
end)
test('navigation requests are throttled and cats must remain living',function()
    local f,c,s,cats,made=fixture();f.select({7});f.tick(1);eq(made[1].moves,2)
    f.tick(1.1);eq(made[1].moves,2);f.tick(2);eq(made[1].moves,3)
    cats[1].living=false;f.tick(3);eq(made[1].alive,false)
end)
test('cleanup failure preserves ownership and can be retried',function()
    local f,c,s,cats,made=fixture();f.select({7});local destroy=made[1].destroy
    made[1].destroy=function()error('cleanup failed')end
    eq(f.shutdown(),false);eq(f.state().active,1);eq(f.select({8}),false)
    made[1].destroy=destroy;eq(f.shutdown(),true);eq(made[1].alive,false)
end)
test('stay stops immediately and follow resumes normal path requests',function()
    local f,c,s,cats,made=fixture();f.select({7,8});eq(f.command('stay'),true);eq(made[1].stops,1)
    f.tick(1);eq(made[1].moves,1);eq(made[2].stops,2);eq(f.state().mode,'stay')
    eq(f.command('follow'),true);f.tick(2);eq(made[1].moves,2);eq(f.state().mode,'follow')
end)
test('regroup uses closer navigation then resumes ordinary distance',function()
    local f,c,s,cats,made=fixture();f.select({7});eq(f.set_distance(350),true);eq(f.command('regroup'),true)
    f.tick(1);eq(made[1].distance,60);eq(f.state().mode,'regroup')
    made[1].currentDistance=150;f.tick(2);eq(f.state().mode,'follow');f.tick(3);eq(made[1].distance,350)
end)
test('regroup timeout and transition reset do not retain stale stay commands',function()
    local f,c,s,cats,made=fixture();f.select({7});f.command('regroup');f.tick(1);f.tick(14);eq(f.state().mode,'follow')
    f.command('stay');s.combat=true;f.tick(15);eq(f.state().mode,'follow');eq(f.state().active,0)
end)
test('commands refuse missing followers and unsafe sessions; distance is bounded',function()
    local f,c,s,cats,made=fixture();eq(f.command('stay'),false);f.select({7});s.offline=false;eq(f.command('stay'),false)
    for _,v in ipairs({0,99,601,200.5,'200'})do eq(f.set_distance(v),false)end
    eq(f.set_distance(600),true);eq(f.state().distance,600)
end)
test('appearance edits refresh owned followers without respawning or losing Stay',function()
    local f,c,s,cats,made=fixture();cats[1].custom='coat=old';assert(f.select({7}));assert(f.command('stay'))
    assert(f.tick(1));eq(made[1].appearanceUpdates,nil)
    cats[1].custom='coat=new';assert(f.tick(2));eq(made[1].appearanceUpdates,1);eq(made[1].custom,'coat=new')
    eq(#made,1);eq(made[1].alive,true);eq(f.state().mode,'stay')
    assert(f.tick(3));eq(made[1].appearanceUpdates,1)
end)
test('failed appearance refresh dismisses owned actors safely',function()
    local f,c,s,cats,made=fixture();cats[1].custom='old';assert(f.select({7}))
    made[1].update_appearance=function()return false end;cats[1].custom='new'
    eq(f.tick(1),false);eq(made[1].alive,false);eq(f.state().active,0)
end)
print(n..' follower model tests passed.')
