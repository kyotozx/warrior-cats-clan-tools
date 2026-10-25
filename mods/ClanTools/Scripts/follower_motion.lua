-- Distance-based leader trail: turning in place never spins the formation.
-- Engine navigation owns actual movement; this module only proposes goals.
local M={}
local function copy(p)return{X=p.X,Y=p.Y,Z=p.Z}end
local function distance(a,b)return math.sqrt((a.X-b.X)^2+(a.Y-b.Y)^2)end
local function clamp(v,a,b)return math.max(a,math.min(b,v))end
function M.new(index)
 assert(index==1 or index==2)
 local trail,previous,heading,goal,stopped={},nil,nil,nil,false
 local api={}
 function api.plan(player,forward,position,peers,followDistance,dt)
  dt=clamp(dt or .2,.05,.5)
  if not previous or distance(player,previous)>2500 or math.abs(player.Z-previous.Z)>600 then
   local n=math.sqrt(forward.X^2+forward.Y^2);heading=n>.01 and{X=forward.X/n,Y=forward.Y/n}or{X=1,Y=0}
   trail={copy(player),{X=player.X-heading.X*900,Y=player.Y-heading.Y*900,Z=player.Z}}
   goal=nil;previous=copy(player);stopped=false
  end
  local traveled=distance(player,previous);local speed=traveled/dt
  if traveled>6 then
   heading={X=(player.X-previous.X)/traveled,Y=(player.Y-previous.Y)/traveled}
   table.insert(trail,1,copy(player));previous=copy(player)
   while #trail>100 do table.remove(trail)end
  end
  local behind=math.max(80,followDistance or 150)+(index-1)*65
  local remaining=behind;local center=copy(trail[#trail]);local tangent=heading
  for i=1,#trail-1 do
   local a,b=trail[i],trail[i+1];local length=distance(a,b)
   if length>.01 then
    if remaining<=length then
     local t=remaining/length;center={X=a.X+(b.X-a.X)*t,Y=a.Y+(b.Y-a.Y)*t,Z=a.Z+(b.Z-a.Z)*t}
     tangent={X=(a.X-b.X)/length,Y=(a.Y-b.Y)/length};break
    end
    remaining=remaining-length
   end
  end
  local side=index==1 and -1 or 1;local width=75
  local desired={X=center.X-tangent.Y*side*width,Y=center.Y+tangent.X*side*width,Z=center.Z}
  -- Gentle local separation, with a stable slot-side tie break when overlapping.
  local separating=false
  for _,p in ipairs(peers or{})do
   local d=distance(position,p)
   if d<115 and math.abs(position.Z-p.Z)<90 then
    local x,y=position.X-p.X,position.Y-p.Y
    if d<1 then x,y=-tangent.Y*side,tangent.X*side;d=1 end
    local force=math.max(70,150-d)
    desired.X=position.X+x/d*force;desired.Y=position.Y+y/d*force;separating=true
   end
  end
  -- Bound retargeting velocity rather than snapping the goal around sharp turns.
  if goal and not separating then
   local d=distance(desired,goal);local step=math.max(180,speed+100)*dt
   if d>step then local t=step/d;desired.X=goal.X+(desired.X-goal.X)*t;desired.Y=goal.Y+(desired.Y-goal.Y)*t end
  end
  goal=copy(desired)
  local error=distance(position,goal)
  if separating then stopped=false
  elseif stopped then if error>85 then stopped=false end elseif error<38 then stopped=true end
  local cruise=clamp(speed+math.max(0,error-100)*.6,110,600)
  local arrival=math.sqrt(2*550*math.max(0,error-25))
  return{goal=copy(goal),center=center,stop=stopped,speed=stopped and 0 or clamp(math.min(cruise,arrival),55,600),error=error}
 end
 function api.reset()trail={};previous=nil;heading=nil;goal=nil;stopped=false end
 return api
end
return M
