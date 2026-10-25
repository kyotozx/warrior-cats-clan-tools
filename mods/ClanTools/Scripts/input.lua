-- Game-thread input polling. FKey.KeyName is the reflected field in InputCore.hpp.
-- The caller owns pause visibility, focus, and the existing F6 key binding.
local M={}
local names={
 'Gamepad_FaceButton_Top','Gamepad_FaceButton_Bottom','Gamepad_FaceButton_Right',
 'Gamepad_LeftShoulder','Gamepad_RightShoulder',
 'Gamepad_DPad_Up','Gamepad_DPad_Down','Gamepad_DPad_Left','Gamepad_DPad_Right',
 'Up','Down','Left','Right','W','A','S','D','Q','E','Enter','SpaceBar','Escape','BackSpace','PageUp','PageDown',
}
function M.new(ctx)
 assert(type(ctx)=='table','Input context required')
 local api={};local held,blocked,keys={},{},{};local controller,controllerId,session,mode,lastError
 local time,nextRepeat,direction=0,0,nil;local axisDirection
 local repeatDelay=0.38;local repeatInterval=0.12
 local openKeys=ctx.open_keys or {'Gamepad_FaceButton_Top'}
 local function valid(o)
  if not o then return false end
  if ctx.valid then return ctx.valid(o)==true end
  return o:IsValid()==true
 end
 local function key(name)
  if not keys[name]then keys[name]={KeyName=(ctx.make_name or FName)(name)}end
  return keys[name]
 end
 local function report(err)
  err=tostring(err);if lastError~=err and ctx.log then ctx.log('Controller input: '..err)end;lastError=err
 end
 function api.reset()
  held={};blocked={};controller=nil;controllerId=nil;session=nil;mode=nil;direction=nil;axisDirection=nil;nextRepeat=0
 end
 local function callback(name,...)
  local fn=ctx[name];if fn then return fn(...)end
 end
 local function run(s,dt)
  time=time+math.max(0,math.min(tonumber(dt)or 0.1,0.25))
  local opened=ctx.is_open and ctx.is_open()==true
  local pause=not opened and ctx.pause and ctx.pause()or nil
  if not s or not s.pc or s.offline==false or(not opened and not pause)then api.reset();return end
  if not valid(s.pc)then api.reset();return end
  local identity=tostring(s.profile)..':'..tostring(s.slot)..':'..tostring(s.worldId)
  local nextMode=opened and'open'or'pause'
  local addressOK,address=pcall(function()return s.pc:GetAddress()end)
  local id=addressOK and address or s.pc
  local changed=controllerId~=id or session~=identity or mode~=nextMode
  if changed then held={};blocked={};direction=nil;axisDirection=nil;nextRepeat=0 end
  controller=s.pc;controllerId=id;session=identity;mode=nextMode
  local down,pressed={},{}
  local function sample(name)
   if down[name]~=nil then return end
   local k=key(name)
   local value=controller:IsInputKeyDown(k)
   local just=controller:WasInputKeyJustPressed(k)
   assert(type(value)=='boolean'and type(just)=='boolean','PlayerController input did not return booleans')
   down[name]=value
   -- Do not inherit a held attack/confirm key when entering the menu or replacing the PC.
   if changed and value then blocked[name]=true end
   if not value then blocked[name]=nil end
   pressed[name]=not blocked[name]and not held[name]and(value or just)
  end
  for _,name in ipairs(names)do sample(name)end
  for _,name in ipairs(openKeys)do sample(name)end
  local function any(...)
   for _,name in ipairs({...})do if pressed[name]then return true end end;return false
  end
  if not opened then
   local chord,edge=true,false
   for _,name in ipairs(openKeys)do chord=chord and(down[name]or pressed[name]);edge=edge or pressed[name]end
   held=down
   if chord and edge and(not ctx.can_open or ctx.can_open(pause,s))then callback('open',pause)end
   return
  end
  held=down
  -- The game dispatches its own menu command events even while PlayerInput
  -- polling is swallowed by the pause stack. Use one owner to avoid duplicates.
  if ctx.native_commands then return end
  -- Back/confirmation are edges only and take priority over simultaneous navigation.
  if any('Gamepad_FaceButton_Right','Escape','BackSpace')then callback('back');return end
  if any('Gamepad_FaceButton_Bottom','Enter','SpaceBar')then callback('activate');return end
  local previous=any('Gamepad_LeftShoulder','PageUp','Q');local following=any('Gamepad_RightShoulder','PageDown','E')
  if previous~=following then callback('tabcycle',previous and -1 or 1);direction=nil;return end
  local x=controller:GetInputAnalogKeyState(key('Gamepad_LeftX'))
  local y=controller:GetInputAnalogKeyState(key('Gamepad_LeftY'))
  assert(type(x)=='number'and type(y)=='number','PlayerController analog input did not return numbers')
  -- Dominant-axis selection avoids double diagonal steps; hysteresis reduces jitter.
  local magnitude=math.max(math.abs(x),math.abs(y))
  if magnitude<0.35 then axisDirection=nil
  elseif magnitude>=0.60 then
   axisDirection=math.abs(x)>math.abs(y)and(x>0 and'right'or'left')or(y>0 and'up'or'down')
  end
  local chosen
  local pairsByDirection={{'up','Gamepad_DPad_Up','Up','W'},{'down','Gamepad_DPad_Down','Down','S'},
   {'left','Gamepad_DPad_Left','Left','A'},{'right','Gamepad_DPad_Right','Right','D'}}
  for _,entry in ipairs(pairsByDirection)do
   for i=2,#entry do local k=entry[i]
    if(not blocked[k]and down[k])or pressed[k]then chosen=entry[1];break end
   end
   if chosen then break end
  end
  chosen=chosen or axisDirection
  if changed then direction=chosen;nextRepeat=time+repeatDelay;return end
  if chosen~=direction then
   direction=chosen;nextRepeat=time+repeatDelay
   if chosen then callback('nav',chosen)end
  elseif chosen and time>=nextRepeat then callback('nav',chosen);nextRepeat=time+repeatInterval end
 end
 function api.tick(snapshot,dt)
  local ok,err=pcall(run,snapshot,dt)
  if not ok then report(err);api.reset();return false,tostring(err)end
  lastError=nil;return true
 end
 function api.status()return {active=mode~=nil,mode=mode,error=lastError,open_keys=openKeys}end
 function api.shutdown()api.reset();return true end
 return api
end
return M
