-- Per-owned-cat idle timing. Native animation still selects/plays the actions;
-- never restart montages or slow locomotion to desynchronise companions.
local M={}
function M.new(seed)
 local state=math.floor(seed or 1)%2147483646+1
 local previous,instance,armed=nil,nil,false
 local function random()
  state=(state*48271)%2147483647
  return state/2147483647
 end
 local api={}
 function api.tick(anim,moving)
  if not anim then previous=nil;instance=nil;armed=false;return end
  local id=anim:GetAddress()
  if id~=instance then instance=id;previous=nil;armed=false end
  local remaining=anim.TimeUntilNextBreak
  if type(remaining)~='number'or remaining~=remaining then return end
  -- Native setup resets the countdown when returning to idle and after each
  -- break. Replace each new interval once; never refresh it every tick.
  local reset=previous==nil or remaining>(previous or remaining)+.05
  if moving then armed=false
  elseif not armed or reset then
   local delay=4.5+random()*8.5
   anim.IdleBreakDelayTime=delay
   anim.TimeUntilNextBreak=delay
   remaining=delay;armed=true
  end
  previous=remaining
 end
 return api
end
return M
