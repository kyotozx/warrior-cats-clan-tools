local d=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local mode,restores,paused=nil,0,false;local gs={GetAddress=function()return 1 end}
function FName(s)return s end
local a={OnStartCinematicNight=function()end,StopCinematicNight=function()end,GetLevel=function()return{bIsVisible=true}end,ApplyStraight=function(_,v)mode=v end,DoZoneDetectionFunction=function()restores=restores+1 end}
function FindAllOf()return{a}end
function StaticFindObject()return{IsGamePaused=function()return paused end,GetGameState=function()return gs end}end
local s={offline=true,combat=false,phase=4,worldId='a',gs=1};local ctx={valid=function(o)return o~=nil end,snapshot=function()return s end,ui={opened=true}}
local api=dofile(d..'../Scripts/sky_tools.lua').new(ctx)
api.set('Night');api.tick(s);assert(not mode and api.status().pending)
ctx.ui.opened=false;paused=true;api.tick(s);assert(not mode)
paused=false;api.tick(s);assert(mode==4 and api.status().applied)
api.set('Day');api.tick(s);assert(mode==1 and restores==1)
s.combat=true;api.tick(s);assert(restores==2 and api.status().mode=='Automatic');assert(not pcall(api.set,'Night'))
s.combat=false;api.set('Night');api.tick(s);s.worldId='b';api.tick(s);assert(restores==3)
assert(api.shutdown());print('PASS sky waits for resume and restores on combat and world changes')
