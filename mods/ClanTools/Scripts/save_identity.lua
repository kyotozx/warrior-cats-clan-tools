-- The platform profile and the selected character are different indices.
-- The selected character belongs to GameConfig, not FlowManager. The latter
-- also has readable memory at this offset, but it can silently return zero.
local M={}
function M.new(ctx)
 local registered=false
 local attempted=false
 local class
 return function(instance)
  if not registered then
   if attempted then return nil end
   attempted=true
   local result=ctx.verify()
   if not result or result.action~='CONTEXT_LAYOUT config_slot=340'then return nil end
   RegisterCustomProperty({Name='ClanToolsCurrentCharacterSlot',Type=PropertyTypes.IntProperty,
    BelongsToClass='/Script/SwtAdventure.SwtAdventureGameConfig',OffsetInternal=0x154})
   registered=true
  end
  if not ctx.valid(class)then class=StaticFindObject('/Script/SwtAdventure.SwtAdventureGameConfig')end
  local config=instance.GameConfig
  if not ctx.valid(config)or not ctx.valid(class)or not config:IsA(class)then return nil end
  local slot=config.ClanToolsCurrentCharacterSlot
  if type(slot)~='number'or slot%1~=0 or slot<0 or slot>2147483647 then return nil end
  return slot
 end
end
return M
