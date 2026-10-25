-- Refresh loaded quest NPC visuals through the game's existing role-update
-- handler, keeping its current role unchanged. Never call the Dead(12) branch.
local M={}
local function stringValue(v)
 if type(v)=='string'then return v end
 return v:ToString()
end
local function identity(a,b)
 return a.ClanType==b.ClanType and a.Role==b.Role and a.Gender==b.Gender
  and stringValue(a.PrefixNameId)==stringValue(b.PrefixNameId)
  and stringValue(a.SuffixNameId)==stringValue(b.SuffixNameId)
  and stringValue(a.CombatStats.TagName)==stringValue(b.CombatStats.TagName)
end
M.sameIdentity=identity
function M.new(ctx)
 local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local class=StaticFindObject('/Script/SwtAdventure.SwtAdventureQuestActor')
 local update=StaticFindObject('/Script/SwtAdventure.SwtAdventureQuestActor:UpdatedRole')
 local api={}
 function api:refresh(cat,h)
  if not h or not ctx.valid(h.actor)or not ctx.valid(h.actor.CustomizableMeshComponent)then return 0,'Preview is unavailable'end
  local s=ctx.snapshot()
  if not s or not s.offline or not ctx.valid(s.gameState)or not ctx.valid(update)then return 0,'Campaign is unavailable'end
  local data=h.actor.CustomizableMeshComponent.CustomData
  local count,skipped=0,0
  for _,actor in ipairs(FindAllOf('SwtAdventureQuestActor')or{})do
   if ctx.valid(actor)and actor:IsA(class)and actor.narrativeRole==cat.role then
    local state=gameplay:GetGameState(actor)
    local role=actor.GiverRole
    if ctx.valid(state)and state:GetAddress()==s.gameState:GetAddress()
      and role>=1 and role<=8 and ctx.valid(actor.MeshCustomizationComponent)
      and identity(data,actor.DefaultCustomData)and data.Role==role then
     -- UFunction marshalling makes the by-value FCatCustomData copy consumed by
     -- native UpdatedRole; passing raw FString-owning memory would be unsafe.
     update(actor,cat.role,role,data)
     count=count+1
    else skipped=skipped+1 end
   end
  end
  return count,skipped
 end
 return api
end
return M
