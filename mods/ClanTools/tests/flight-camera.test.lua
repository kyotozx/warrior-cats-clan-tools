local M=dofile('mods/ClanTools/Scripts/flight_camera.lua')
local function fixture()
 local yaw,native=12,0
 local camera={GetAddress=function()return 1 end,K2_GetActorRotation=function()return{pitch=4,Yaw=yaw,Roll=2}end,
 K2_SetActorRotation=function(_,r)assert(r.pitch==4 and r.Roll==2);yaw=r.Yaw end}
 camera.AdventureArmComponent={K2_GetComponentRotation=function()return{Yaw=yaw+native}end}
 local pc={GetViewTarget=function()return camera end,IsLookInputIgnored=function()return false end}
 local s={offline=true,phase=4,worldId='a',pc=pc,pawn={GetAddress=function()return 9 end},gameState={CameraActor=camera}}
 local api=M.new({valid=function(o)return type(o)=='table'and not o.dead end})
 return api,s,camera,function()return yaw end,function(n)native=n end
end
do
 local a,s,c,y=fixture();a.tick(s,1,.016);a.tick(s,1,.016);assert(math.abs(y()-13.6)<.001)
 a.tick(s,-1,.016);assert(math.abs(y()-12)<.001);a.reset();assert(y()==12)
end
do
 local a,s,c,y,n=fixture();a.tick(s,1,.016);n(1.6);a.tick(s,1,.016);assert(math.abs(y()-12)<.001,'Native yaw is not doubled')
 a.tick(s,0,.016);assert(y()==12)
end
do
 local a,s,c,y=fixture();a.tick(s,1,.016);a.tick(s,1,.016)
 s.combat=true;a.tick(s,1,.016);assert(y()==12,'Combat restores the borrowed camera')
 s.combat=false;c.SplineActor={};a.tick(s,1,.016);a.tick(s,1,.016);assert(y()==12,'Scripted camera owns input')
 c.SplineActor=nil;s.pc.GetViewTarget=function()return{GetAddress=function()return 2 end}end;a.tick(s,1,.016);assert(y()==12)
end
print('PASS flight yaw, native compensation, original pitch/roll, restoration and camera ownership guards')
