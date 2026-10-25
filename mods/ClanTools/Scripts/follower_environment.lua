-- Read-only follower suitability checks. Housing interiors have no usable
-- follower navigation; use the actual exit door's transformed volume.
local M={}
function M.navigation(s)
 local nav=StaticFindObject('/Script/NavigationSystem.Default__NavigationSystemV1')
 local p=s.pawn:K2_GetActorLocation();local f=s.pawn:GetActorForwardVector();local r=s.pawn:GetActorRightVector()
 -- Probe player destination and both intended spawn locations. A nearby floor
 -- may project successfully while an interior or cliff-side spawn does not.
 for _,side in ipairs({0,-1,1})do
  local point=side==0 and{X=p.X,Y=p.Y,Z=p.Z}or{X=p.X-f.X*180+r.X*side*90,Y=p.Y-f.Y*180+r.Y*side*90,Z=p.Z+30}
  local out={}
  if nav:K2_ProjectPointToNavigation(s.pawn,point,out,nil,nil,{X=100,Y=100,Z=250})~=true then return false,'Followers are waiting for navigation terrain.'end
 end
 return true
end
function M.new(ctx)
 local valid=ctx.valid
 local function id(x)if valid(x)then return x:GetAddress()end end
 local function visibleWorld(actor)
  local level=actor:GetLevel();if not valid(level)or level.bIsVisible~=true then return nil end
  return id(level.OwningWorld)
 end
 return function(s)
  assert(valid(s.pawn),'Player unavailable.')
  local world=visibleWorld(s.pawn);assert(world,'Player world unavailable.')
  local mathLib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary');assert(valid(mathLib),'Housing detection unavailable.')
  local position=s.pawn:K2_GetActorLocation()
  for _,door in ipairs(FindAllOf('WrcHousingDoorActor')or{})do
   if valid(door)and visibleWorld(door)==world and door.bIsExit==true then
    local box=door.HotspotsContainerAreaComponent
    if valid(box)then
     local extent=box:GetUnscaledBoxExtent()
     if extent.X>0 and extent.Y>0 and extent.Z>0 and mathLib:IsPointInBoxWithTransform(position,box:K2_GetComponentToWorld(),extent)==true then
      return false,'Followers wait outside dens.'
     end
    end
   end
  end
  if ctx.followerNavPreflight==true then return M.navigation(s)end
  return true
 end
end
return M
