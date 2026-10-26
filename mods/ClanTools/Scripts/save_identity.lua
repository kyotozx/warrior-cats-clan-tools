-- The platform profile and the selected character are different indices.
-- Use the same live FlowManager field as the game's current-character reader.
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
   if not result or result.action~='CONTEXT_LAYOUT flow_slot=340'then return nil end
   RegisterCustomProperty({Name='ClanToolsCurrentCharacterSlot',Type=PropertyTypes.IntProperty,
    BelongsToClass='/Script/SwtAdventure.SwtAdventureFlowManager',OffsetInternal=0x154})
   registered=true
  end
  if not ctx.valid(class)then class=StaticFindObject('/Script/SwtAdventure.SwtAdventureFlowManager')end
  local flow=instance.FlowManager
  if not ctx.valid(flow)or not ctx.valid(class)or not flow:IsA(class)then return nil end
  local slot=flow.ClanToolsCurrentCharacterSlot
  if type(slot)~='number'or slot%1~=0 or slot<0 or slot>2147483647 then return nil end
  return slot
 end
end
return M
