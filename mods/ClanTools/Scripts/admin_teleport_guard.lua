-- Read-only encounter clearance. Never move encounter actors or change overlaps.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={radius=300,height=300}
local function position(value)
 local out={X=value.X,Y=value.Y,Z=value.Z}
 for _,key in ipairs({'X','Y','Z'})do
  local n=out[key];assert(type(n)=='number'and n==n and math.abs(n)<=1000000,'Encounter position is unavailable.')
 end
 return out
end
function M.check(snapshot,destination)
 local ok,result=pcall(function()
  assert(snapshot and snapshot.offline==true and snapshot.phase==4 and not snapshot.combat,'Teleport requires offline exploration.')
  assert(type(FindAllOf)=='function','Encounter discovery is unavailable.')
  local target=position(destination)
  local playerId=valid(snapshot.pawn)and snapshot.pawn:GetAddress()or nil
  for _,actor in ipairs(FindAllOf('SwtAdventureCharacter')or{})do
   if valid(actor)then
    local controller=actor.Controller
    local isPlayer=(playerId and actor:GetAddress()==playerId)or(valid(controller)and controller:IsPlayerController()==true)
    if not isPlayer then
    local level=actor:GetLevel()
    if valid(level)and level.bIsVisible==true then
     local world=level.OwningWorld
     assert(valid(world),'Encounter owning world is unavailable.')
     if world:GetFullName()==snapshot.worldId and valid(actor.PreyGenerator)then
      local p=position(actor:K2_GetActorLocation())
      if (p.X-target.X)^2+(p.Y-target.Y)^2<=M.radius^2 and math.abs(p.Z-target.Z)<=M.height then
       return false
      end
     end
    end
    end
   end
  end
  return true
 end)
 if not ok then return false,'Cannot verify encounter clearance. Wait for the world to finish loading and retry.'end
 if not result then return false,'An encounter is too close to this destination. Move away from it normally before teleporting here.'end
 return true
end
return M
