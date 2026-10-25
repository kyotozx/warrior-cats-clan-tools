-- Resolve named markers from currently loaded actors; never store coordinates.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local valid=dofile(folder..'runtime_valid.lua').valid
local M={};local clans={'ThunderClan','ShadowClan','RiverClan','WindClan'}
local expectedWorld='World /Game/Art/Maps/Gameplay/L_WorldMap_01_P.L_WorldMap_01_P'
local function position(v)
 local out={X=v.X,Y=v.Y,Z=v.Z}
 for _,k in ipairs({'X','Y','Z'})do local n=out[k];assert(type(n)=='number'and n==n and math.abs(n)<=1000000,'Invalid destination position.')end
 return out
end
function M.new(ctx)
 local api={}
 local function snapshot(s)
  s=s or ctx.snapshot();assert(s and s.offline==true and s.phase==4 and not s.combat and valid(s.pawn),'Named travel requires offline exploration.')
  assert(s.worldId==expectedWorld,'Named travel supports the campaign world only.');return s
 end
 local function sameWorld(actor,s)
  if not valid(actor)then return false end
  local level=actor:GetLevel();if not valid(level)or level.bIsVisible~=true then return false end
  local world=level.OwningWorld;return valid(world)and world:GetFullName()==s.worldId
 end
 local function entries(s)
  local out,seen={},{}
  for _,actor in ipairs(FindAllOf('SwtQuestPlayerStart')or{})do
   if sameWorld(actor,s)then
    local clan=actor.Clan
    if clans[clan]and actor:GetClass():GetFullName():match('%.BP_QuestPlayerStart_C$')then
     seen[clan]=seen[clan]or{};seen[clan][#seen[clan]+1]=actor
    end
   end
  end
  for clan=1,4 do local matches=seen[clan]
   -- Duplicate active markers are ambiguous during streaming; never pick one.
   if matches and #matches==1 then
    out[#out+1]={id='clan_spawn:'..clan,label=clans[clan]..' spawn point',clan=clan,kind='clan_spawn',position=position(matches[1]:K2_GetActorLocation())}
   end
  end
  return out
 end
 function api.list(s)return entries(snapshot(s))end
 function api.resolve(id,s)
  assert(type(id)=='string'and id:match('^clan_spawn:[1-4]$'),'Unknown named destination.')
  for _,entry in ipairs(entries(snapshot(s)))do if entry.id==id then return entry end end
  error('Destination is unloaded or ambiguous. Refresh the location list.')
 end
 return api
end
return M
