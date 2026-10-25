-- Pure Lua model tests; these do not prove native engine behavior.
local Admin=dofile('mods/ClanTools/Scripts/admin.lua')
local passed=0
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function test(name,fn)
    local ok,err=xpcall(fn,debug.traceback)
    if not ok then io.stderr:write('FAIL '..name..'\n'..err..'\n');os.exit(1) end
    passed=passed+1;print('PASS '..name)
end
local nextId=0
local function object(fields)
    nextId=nextId+1;fields=fields or {};fields.id=nextId;fields.valid=true
    function fields:IsValid()return self.valid end
    function fields:GetAddress()return self.id end
    function fields:K2_DestroyActor()self.valid=false end
    return fields
end
local function fixture()
    local movement=object{MovementMode=1,CustomMovementMode=0,MaxFlySpeed=600,MaxWalkSpeed=175,MaxAcceleration=175,BrakingDecelerationFlying=0,BrakingFriction=0,BrakingFrictionFactor=2,bUseSeparateBrakingFriction=false}
    function movement:SetMovementMode(mode,custom) self.MovementMode=mode;self.CustomMovementMode=custom end
    function movement:StopMovementImmediately()self.stops=(self.stops or 0)+1 end
    local pawn=object{CharacterMovement=movement,collision=true,pos={X=10,Y=20,Z=30},writes=0}
    function pawn:GetActorEnableCollision()return self.collision end
    function pawn:SetActorEnableCollision(value)self.collision=value;self.writes=self.writes+1 end
    function pawn:K2_GetActorLocation()return self.pos end
    function pawn:K2_SetActorLocation(pos,sweep,hit,teleport)
        self.pos={X=pos.X,Y=pos.Y,Z=pos.Z};self.writes=self.writes+1;return true
    end
    local state={offline=true,phase=4,worldId='WorldA',profile='test-profile',slot=0,pawn=pawn}
    local made={}
    local waypointBytes
    local ctx={waypoint_read=function()return waypointBytes end,waypoint_write=function(raw)waypointBytes=raw;return true end,snapshot=function() return state end,
        verified={movement=true,collision=true,teleport=true,spawn_item=true},
        adapters={validate_world=function()return true end,teleport_clearance=function()return true end,spawn_item=function(_,entry,pos)
            local actor=object{entry=entry,pos=pos};made[#made+1]=actor;return actor
        end}}
    return Admin.new(ctx),state,pawn,movement,ctx,made
end
test('offline unknown and online block all gameplay mutations',function()
    for _,offline in ipairs({false,'unknown'}) do
        local m,s,p=fixture();s.offline=offline
        local ok,msg=m.action('flight',{enabled=true});eq(ok,false);assert(msg:match('offline'))
        eq(p.writes,0);eq(p.CharacterMovement.MovementMode,1)
    end
end)
test('combat and unavailable pawn blocked',function()
    local m,s,p=fixture();s.phase=5;eq(m.action('teleport',{X=100,Y=100,Z=100}),false);eq(p.writes,0)
    s.phase=4;p.valid=false;eq(m.action('flight'),false)
end)
test('features require runtime verification',function()
    local m,s,p,c,ctx=fixture();ctx.verified.movement=nil
    eq(m.action('flight'),false);eq(c.MovementMode,1)
    eq(m.capabilities().actions.spawn_enemy.supported,false)
    eq(m.action('heal'),false)
end)
test('flight enables and restores original movement',function()
    local m,s,p,c=fixture();c.MovementMode=6;c.CustomMovementMode=9
    eq(m.action('flight',{enabled=true}),true);eq(c.MovementMode,5)
    eq(m.action('flight',{enabled=false}),true);eq(c.MovementMode,6);eq(c.CustomMovementMode,9)
    eq(c.MaxFlySpeed,600)
    eq(c.MaxAcceleration,175);eq(c.BrakingDecelerationFlying,0);eq(c.BrakingFriction,0)
    eq(c.BrakingFrictionFactor,2);eq(c.bUseSeparateBrakingFriction,false)
end)

test('flight tuning accelerates and brakes without changing native camera',function()
    local m,s,p,c=fixture();m.action('flight',{enabled=true})
    eq(c.MaxAcceleration,2400);eq(c.BrakingDecelerationFlying,3000);eq(c.BrakingFriction,8)
    eq(c.BrakingFrictionFactor,1);eq(c.bUseSeparateBrakingFriction,true);eq(c.stops,1)
    m.tick();eq(c.stops,1) -- reapplication does not interrupt held movement
    m.reset();eq(c.stops,2);eq(c.MaxAcceleration,175);eq(c.BrakingFrictionFactor,2)
end)

test('shared flight noclip keeps tuning until both toggles are disabled',function()
    local m,s,p,c=fixture();m.action('flight',{enabled=true});m.action('noclip',{enabled=true})
    m.action('flight',{enabled=false});eq(c.BrakingDecelerationFlying,3000)
    m.action('noclip',{enabled=false});eq(c.BrakingDecelerationFlying,0);eq(c.bUseSeparateBrakingFriction,false)
end)

test('release brakes only when all native movement controls are neutral',function()
    local m,s,p,c,ctx=fixture();ctx.verified.vertical_input=true;m.action('flight',{enabled=true})
    local submitted=0;ctx.adapters.vertical_input=function(_,axis)submitted=submitted+axis;return true end
    local stopped=c.stops;eq(m.flightInput(0,true),true);eq(c.stops,stopped)
    eq(m.flightInput(1,false),true);eq(submitted,1);eq(c.stops,stopped)
    c.Velocity={X=100,Y=50,Z=75};eq(m.flightInput(0,true),true);eq(c.Velocity.Z,0);eq(c.Velocity.X,100);eq(c.Velocity.Y,50)
    eq(m.flightInput(0,false),true);eq(c.stops,stopped+1)
    eq(m.flightInput(2,false),false);eq(c.stops,stopped+1)
    s.combat=true;eq(m.flightInput(0,false),false);eq(c.MovementMode,1);eq(c.MaxAcceleration,175)
end)

test('unknown flight tuning fails before mutating movement mode',function()
    local m,s,p,c=fixture();c.BrakingFriction=nil
    eq(m.action('flight',{enabled=true}),false);eq(c.MovementMode,1);eq(c.MaxAcceleration,175)
end)
test('speed does not overwrite jump movement mode',function()
    local m,s,p,c=fixture();eq(m.action('speed',{multiplier=2}),true);eq(c.MaxWalkSpeed,350)
    c.MovementMode=3;m.tick();eq(c.MovementMode,3)
    m.reset();eq(c.MaxWalkSpeed,175);eq(c.MovementMode,3)
end)
test('noclip and flight share mode until both disabled',function()
    local m,s,p,c=fixture();m.action('flight',{enabled=true});m.action('noclip',{enabled=true})
    eq(p.collision,false);eq(c.MovementMode,5)
    m.action('flight',{enabled=false});eq(c.MovementMode,5)
    m.action('fly_up',{step=50});eq(p.pos.Z,80)
    m.action('noclip',{enabled=false});eq(p.collision,true);eq(c.MovementMode,1);eq(p.pos.Z,30)
end)
test('noclip restores initially disabled collision without forcing true',function()
    local m,s,p=fixture();p.collision=false;m.action('noclip',{enabled=true});m.reset();eq(p.collision,false)
end)
test('vertical movement requires flight and rejects excessive steps',function()
    local m,s,p=fixture();eq(m.action('fly_up'),false);eq(p.writes,0)
    m.action('flight');eq(m.action('fly_up',{step=501}),false);eq(p.pos.Z,30)
    eq(p.CharacterMovement.MovementMode,1)
end)
test('teleport return swaps bounded positions',function()
    local m,s,p=fixture();eq(m.action('teleport',{X=200,Y=300,Z=400}),true);eq(p.pos.X,200)
    eq(m.action('return_position'),true);eq(p.pos.X,10)
    eq(m.action('return_position'),true);eq(p.pos.X,200)
end)
test('invalid coordinates never call teleport',function()
    for _,x in ipairs({math.huge,0/0,1000001,'200'}) do
        local m,s,p=fixture();eq(m.action('teleport',{X=x,Y=0,Z=0}),false);eq(p.writes,0)
    end
end)
test('waypoints are named, capped and separated by world',function()
    local m,s,p=fixture();m.action('save_waypoint',{name='Camp'})
    m.action('teleport',{X=200,Y=300,Z=400});m.action('teleport_waypoint',{name='Camp'});eq(p.pos.X,10)
    eq(m.capabilities().waypoints[1].name,'Camp')
    s.worldId='WorldB';m.tick();eq(#m.capabilities().waypoints,0);eq(m.action('return_position'),false)
    local m2=fixture();for i=1,20 do eq(m2.action('save_waypoint',{name='Point '..i}),true) end
    eq(m2.action('save_waypoint',{name='Point 21'}),false)
end)

test('temporary reset and fresh admin instance preserve user waypoints',function()
    local m,s,p,c,ctx=fixture();eq(m.action('save_waypoint',{name='Camp'}),true)
    m.action('flight',{enabled=true});eq(m.reset(),true);eq(#m.capabilities().waypoints,1)
    local fresh=Admin.new(ctx);eq(#fresh.capabilities().waypoints,1)
    p.pos={X=100,Y=200,Z=300};eq(fresh.action('teleport_waypoint',{name='Camp'}),true);eq(p.pos.X,10)
    eq(fresh.action('delete_waypoint',{name='Camp'}),true);eq(#Admin.new(ctx).capabilities().waypoints,0)
end)
test('world/pawn change restores captured old pawn only',function()
    local m,s,p,c=fixture();m.action('flight');m.action('speed',{multiplier=2})
    local replacement=object{CharacterMovement=object{MovementMode=1}}
    s.pawn=replacement;m.tick();eq(c.MovementMode,1);eq(c.MaxWalkSpeed,175)
    eq(replacement.CharacterMovement.MovementMode,1)
end)
test('online transition restores all temporary state',function()
    local m,s,p,c=fixture();m.action('noclip');m.action('fly_up');s.offline=false;m.tick()
    eq(c.MovementMode,1);eq(p.collision,true);eq(p.pos.Z,30);eq(m.capabilities().available,false)
end)
test('spawn whitelist, cap and cleanup',function()
    local m,s,p,c,ctx,made=fixture()
    eq(m.action('spawn_item',{id='SmallHealingHerb',quantity=2}),true);eq(#made,2)
    assert(made[1].entry.class:match('BP_Pickup_SmallHealingHerb_C$'));eq(made[1].pos.X,130)
    m.action('clear_spawned');eq(made[1].valid,false);eq(m.capabilities().spawned,0)
    eq(m.action('spawn_item',{id='/Script/Engine.Actor'}),false);eq(#made,2)
    eq(m.action('spawn_item',{id='SmallHealingHerb',quantity=11}),false)
end)
test('partial spawn failures remove earlier actors',function()
    local m,s,p,c,ctx,made=fixture();local original=ctx.adapters.spawn_item
    ctx.adapters.spawn_item=function(...) if #made==1 then error('forced spawn failure') end;return original(...) end
    eq(m.action('spawn_item',{id='SmallHealingHerb',quantity=2}),false)
    eq(made[1].valid,false);eq(m.capabilities().spawned,0)
end)
test('cleanup failure blocks further edits and preserves retry state',function()
    local m,s,p,c,ctx,made=fixture();m.action('spawn_item',{id='SmallHealingHerb'})
    ctx.adapters.destroy=function()error('forced destroy failure')end
    eq(m.reset(),false);eq(m.capabilities().available,false);eq(m.action('flight'),false)
    ctx.adapters.destroy=function(actor)actor:K2_DestroyActor();return true end
    eq(m.reset(),true);eq(made[1].valid,false)
end)
test('optional verified god adapter restores captured original state',function()
    local m,s,p,c,ctx=fixture();local god=false
    ctx.verified.god=true;ctx.adapters.read_god=function()return god end
    ctx.adapters.god=function(_,value)god=value;return true end
    eq(m.action('god',{enabled=true}),true);eq(god,true)
    m.reset();eq(god,false)
end)
test('native debug god flag preserves other bits and restores original byte',function()
    local m,s,p,c,ctx=fixture();s.cheats=object{GodMode=12};ctx.verified.god=true
    eq(m.action('god',{enabled=true}),true);eq(s.cheats.GodMode,13)
    eq(m.action('god',{enabled=false}),true);eq(s.cheats.GodMode,12)
    m.action('god',{enabled=true});m.reset();eq(s.cheats.GodMode,12)
end)
test('world validation independently blocks a falsely offline snapshot',function()
    local m,s,p,c,ctx=fixture();ctx.adapters.validate_world=function()return false end
    eq(m.action('flight'),false);eq(c.MovementMode,1)
end)
test('enemy cleanup defers during combat then completes on safe return',function()
    local m,s,p,c,ctx=fixture();local enemy=object{}
    function enemy:CanCleanup()return s.phase==4 end
    ctx.verified.spawn_enemy=true;ctx.adapters.spawn_enemy=function()return enemy end
    eq(m.action('spawn_enemy',{id='WeakMice'}),true)
    m.action('flight');s.phase=5;m.tick()
    eq(c.MovementMode,1);eq(enemy.valid,true);eq(m.capabilities().cleanupPending,true)
    eq(m.shutdown(),false)
    s.phase=4;eq(m.capabilities().available,false)
    m.tick();eq(enemy.valid,false);eq(m.capabilities().cleanupPending,false)
    eq(m.shutdown(),true)
end)
test('shutdown removes actors and restores movement',function()
    local m,s,p,c,ctx,made=fixture();m.action('flight');m.action('spawn_item',{id='SmallHealingHerb'})
    eq(m.shutdown(),true);eq(c.MovementMode,1);eq(made[1].valid,false)
    eq(m.action('flight'),false)
end)
test('smooth vertical input has a distinct gate and uses native movement direction',function()
    local m,s,p,c,ctx=fixture();local axes={}
    function p:AddMovementInput(direction,axis,force)eq(direction.X,0);eq(direction.Y,0);eq(direction.Z,1);eq(force,false);axes[#axes+1]=axis end
    m.action('flight');eq(m.verticalInput(1),false);eq(#axes,0)
    ctx.verified.vertical_input=true;eq(m.verticalInput(.5),true);eq(m.verticalInput(-1),true);eq(#axes,2)
    eq(m.verticalInput(2),false);eq(m.verticalInput(0/0),false);eq(m.verticalInput(0),true);eq(#axes,2)
    s.combat=true;eq(m.verticalInput(1),false);eq(c.MovementMode,1);eq(#axes,2)
end)
test('named teleport requires its own gate and preserves return position',function()
    local _,s,p,c,ctx=fixture()
    ctx.destinations={list=function()return{{id='clan_spawn:4',label='WindClan spawn point'}}end,resolve=function(id)assert(id=='clan_spawn:4');return{label='WindClan spawn point',position={X=150,Y=200,Z=350}}end}
    local m=Admin.new(ctx);local ok,list=m.destinations();eq(ok,true);eq(#list,1)
    eq(m.action('teleport_destination',{id='clan_spawn:4'}),false);eq(p.writes,0)
    ctx.verified.named_destinations=true;eq(m.action('teleport_destination',{id='clan_spawn:4'}),true);eq(p.pos.X,150);eq(m.capabilities().hasReturn,true)
    eq(m.action('return_position'),true);eq(p.pos.X,10);eq(p.pos.Z,30)
end)
test('completed noclip cannot re-enable native combat collision later',function()
 local m,s,p=fixture();assert(m.action('noclip'));assert(m.action('noclip',{enabled=false}));p.collision=false;s.phase=5
 local writes=p.writes;assert(m.tick());eq(p.collision,false);eq(p.writes,writes)
end)
test('active noclip defers relocation and collision until native possession returns',function()
 local m,s,p=fixture();assert(m.action('noclip'));p.pos.Z=200;s.phase=5;s.pc=object{}
 local writes=p.writes;assert(m.tick());eq(p.collision,false);eq(p.pos.Z,200);eq(p.writes,writes);eq(m.shutdown(),false)
 s.phase=4;assert(m.tick());eq(p.collision,false);eq(p.pos.Z,200)
 s.pc.Pawn=p;assert(m.tick());eq(p.collision,true);eq(p.pos.Z,30);eq(m.capabilities().available,true)
end)
test('teleport and flight alone never acquire collision restoration ownership',function()
 local m,s,p=fixture();assert(m.action('flight'));assert(m.action('teleport',{X=100,Y=100,Z=100}));p.collision=false;s.phase=5
 local writes=p.writes;assert(m.tick());eq(p.collision,false);eq(p.writes,writes)
end)
test('teleport encounter rejection occurs before player mutation',function()
 local m,s,p,c,ctx=fixture();ctx.adapters.teleport_clearance=function()return false,'Encounter nearby.'end
 local ok,why=m.action('teleport',{X=100,Y=100,Z=100});eq(ok,false);assert(why:match('Encounter nearby'));eq(p.writes,0);eq(p.pos.X,10)
end)
print(string.format('%d admin model tests passed.',passed))
