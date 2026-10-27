-- Rotate only the transaction's private preview, including while the campaign
-- is paused. Read command 66 so custom Q/E/right-stick mappings remain valid.
local M={}
function M.new(ctx)
 local api={};local handle,preview;local keys,rows,blocked={},{},{}
 local last,velocity
 local function key(name)
  keys[name]=keys[name]or{KeyName=(ctx.make_name or FName)(name)};return keys[name]
 end
 local function value(pc,name)
  if name:match('^Gamepad_.*[XY]$')then
   local n=pc:GetInputAnalogKeyState(key(name))
   if math.abs(n)<.18 then return 0 end
   return math.max(-1,math.min(1,n))
  end
  return pc:IsInputKeyDown(key(name))and 1 or 0
 end
 function api.stop()
  if handle then CancelDelayedAction(handle);handle=nil end
  preview=nil;rows={};blocked={};last=nil;velocity=0
 end
 function api.tick(now)
  local h=preview
  if not h or h.closed or not ctx.valid(h.actor)or not ctx.valid(h.pc)or not ctx.valid(h.widget)then return end
  local dt=last and math.max(0,math.min(.05,now-last))or 0;last=now
  if ctx.textPrompt and ctx.textPrompt.active()then
   velocity=0;for _,r in ipairs(rows)do if value(h.pc,r.key)~=0 then blocked[r.key]=true end end;return
  end
  local axis=0
  for _,r in ipairs(rows)do
   local n=value(h.pc,r.key)
   if blocked[r.key]then if n==0 then blocked[r.key]=nil end;n=0 end
   axis=axis+n*r.scale
  end
  axis=math.max(-1,math.min(1,axis))
  velocity=velocity+(axis*110-velocity)*(1-math.exp(-18*dt))
  if axis==0 and math.abs(velocity)<.3 then velocity=0 end
  if velocity~=0 then
   local r=h.actor:K2_GetActorRotation();r.Yaw=(r.Yaw+velocity*dt+180)%360-180
   h.actor:K2_SetActorRotation(r,true)
  end
 end
 function api.start(h)
  api.stop();preview=h;velocity=0
  local bindings=ctx.keybinds and ctx.keybinds.bindings()
  assert(type(bindings)=='table','Appearance rotation bindings are unavailable.')
  local seen,keyboard={},{}
  for _,r in ipairs(bindings)do if r.command==66 and r.kind==1 and r.key then
   local id=r.key..':'..r.scale_bits
   if not seen[id]then
    local scale=string.unpack('<f',string.pack('<I4',r.scale_bits))
    assert(scale==scale and math.abs(scale)<=4,'Invalid appearance rotation binding.')
    rows[#rows+1]={key=r.key,scale=scale};seen[id]=true
    if not r.key:match('^Gamepad_')then keyboard[#keyboard+1]=r.key end
    if value(h.pc,r.key)~=0 then blocked[r.key]=true end
   end
  end end
  assert(#rows>0,'Appearance rotation bindings are unavailable.')
  ctx.appearanceRotationHint=(#keyboard>0 and table.concat(keyboard,' / ')..' or 'or'')..'right stick'
  -- The original preview's tick is suspended by campaign pause. We own both
  -- actor and screen, and disable their native rotation to prevent double input.
  h.actor.DefaultRotationRate=0;h.widget.DefaultRotationRate=0
  local clock=ctx.rotationClock or function()return StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetRealTimeSeconds(h.actor)end
  last=clock()
  handle=LoopInGameThreadWithDelay(16,function()
   local ok,why=pcall(api.tick,clock())
   if not ok then api.stop();if ctx.log then ctx.log('Appearance rotation: '..tostring(why))end end
  end)
  assert(handle,'Could not start appearance rotation.')
  return true
 end
 return api
end
return M
