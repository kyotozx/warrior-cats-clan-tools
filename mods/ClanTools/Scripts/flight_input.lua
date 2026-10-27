-- Game-thread flight controls. Native horizontal movement/camera stay in charge.
-- Vertical controls deliberately avoid native Pounce, Crouch and Camera Reset.
local M={}
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
M.tooltip='Move: WASD / left stick. Camera: arrows / right stick. Up: V / RB (R1). Down: B / L3. Release movement to stop.'
local vertical={up={'V','Gamepad_RightShoulder'},down={'B','Gamepad_LeftThumbstick'}}
local defaults={{key='W',command=60,kind=1,scale_bits=1065353216},{key='S',command=60,kind=1,scale_bits=3212836864},
 {key='D',command=61,kind=1,scale_bits=1065353216},{key='A',command=61,kind=1,scale_bits=3212836864},
 {key='Gamepad_LeftY',command=60,kind=1,scale_bits=1065353216},{key='Gamepad_LeftX',command=61,kind=1,scale_bits=1065353216}}
function M.new(ctx)
 assert(ctx.snapshot and ctx.valid and ctx.admin,'Flight input needs the active admin context.')
 local api={tooltip=M.tooltip};local handle,closed,activeId,lastError,lastLoggedError=nil,false,nil,nil,nil
 local blocked,keys,bindings,conflicts={},{},{},{};local running=false;local pausedPawn
 local camera=(ctx.flightCameraFactory or dofile(folder..'flight_camera.lua')).new(ctx)
 local cameraBindings={};local lastCameraTime;local invertX=false
 local function key(name)
  if not keys[name]then keys[name]={KeyName=(ctx.make_name or FName)(name)}end
  return keys[name]
 end
 local function reset()activeId=nil;blocked={};bindings={};conflicts={};cameraBindings={};lastCameraTime=nil end
 local function paused(s)
  if ctx.is_ui_open and ctx.is_ui_open()then return true end
  if ctx.ui and ctx.ui.opened or ctx.appearanceActive then return true end
  if ctx.is_paused then return ctx.is_paused(s)~=false end
  return StaticFindObject('/Script/Engine.Default__GameplayStatics'):IsGamePaused(s.pawn)~=false
 end
 local function value(pc,name)
  if name:match('^Gamepad_')and(name:match('[XY]$')or name:match('Axis$'))then
   local v=pc:GetInputAnalogKeyState(key(name))
   assert(type(v)=='number'and v==v and math.abs(v)<=1.1,'Invalid controller input value.')
   return math.abs(v)<0.18 and 0 or math.max(-1,math.min(1,v))
  end
  return pc:IsInputKeyDown(key(name))and 1 or 0
 end
 local function refreshBindings()
  local rows=defaults
  if ctx.keybinds and ctx.keybinds.bindings then
   local actual,why=ctx.keybinds.bindings()
   assert(type(actual)=='table',why or'Flight controls could not read the active bindings.')
   rows=actual
  end
  bindings={};conflicts={};local seen={};local reserved={}
  cameraBindings={}
  invertX=false
  if ctx.read and ctx.json and ctx.saveDir then
   local s=ctx.snapshot();local raw=ctx.read(ctx.saveDir..'WrcGame.json')
   if raw and s then
    local saved=ctx.json.decode(raw);local profile=saved[s.profile]
    local settings=profile and profile.Shared and profile.Shared.PlayerSettingsData
    if settings and settings['0']then invertX=settings['0'].InvertXCameraAxis==true end
   end
  end
  for _,list in pairs(vertical)do for _,name in ipairs(list)do reserved[name]=true end end
  for _,row in ipairs(rows)do
   if row.key and row.command==63 and row.kind==1 then
    local id='camera:'..row.key..':'..tostring(row.scale_bits)
    if not seen[id]then
     local scale=string.unpack('<f',string.pack('<I4',row.scale_bits or 1065353216))
     assert(scale==scale and math.abs(scale)<=4,'Unsupported camera axis scale.')
     cameraBindings[#cameraBindings+1]={key=row.key,scale=scale};seen[id]=true
    end
   end
   if row.key and(row.command==60 or row.command==61)then
    local id=row.command..':'..row.key..':'..tostring(row.scale_bits)
    if not seen[id]then
     local scale=string.unpack('<f',string.pack('<I4',row.scale_bits or 1065353216))
     assert(scale==scale and math.abs(scale)<=4,'Unsupported movement axis scale.')
     bindings[#bindings+1]={key=row.key,command=row.command,scale=scale};seen[id]=true
    end
   end
   -- Only exploration actions can conflict here. Menu, photo and animation
   -- tool mappings use these same physical buttons in other control modes.
   if reserved[row.key]and(row.command>=60 and row.command<=65 or row.command>=67 and row.command<=81 or row.command==91)then
    conflicts[row.key]=row.label or('command '..row.command)
   end
  end
  assert(#bindings>0,'Native movement bindings are unavailable.')
  if next(conflicts)and ctx.log then
   local names={};for name,action in pairs(conflicts)do names[#names+1]=name..' ('..action..')'end;table.sort(names)
   ctx.log('Flight: conflicting vertical controls are disabled: '..table.concat(names,', ')..'. Change those gameplay bindings in Controls.')
  end
 end
 local function tick()
  if closed then return false,'Flight input is shut down.'end
  if ctx.admin.flightActive and not ctx.admin.flightActive()then camera.reset();reset();pausedPawn=nil;return true end
  local s=ctx.snapshot()
  if not s or s.offline~=true or s.phase~=4 or s.combat or not ctx.valid(s.pawn)or not ctx.valid(s.pc)then camera.reset();reset();pausedPawn=nil;return true end
  if not ctx.valid(s.pc.Pawn)or s.pc.Pawn:GetAddress()~=s.pawn:GetAddress()then camera.reset();reset();pausedPawn=nil;return true end
  local c=ctx.admin.capabilities()
  if not c.available or not(c.flight or c.noclip)or not(c.actions.vertical_input and c.actions.vertical_input.enabled)then camera.reset();reset();return true end
  local id=table.concat({s.worldId or'',s.profile or'',tostring(s.slot),tostring(s.pawn:GetAddress()),tostring(s.pc:GetAddress())},'|')
  if paused(s)or s.pc:IsMoveInputIgnored()then
   -- A single brake while entering a menu prevents paused momentum resuming
   -- when the menu closes. Never mutate a different/combat pawn here.
   if activeId==id and pausedPawn~=id and ctx.admin.flightInput then
    local ok,why=ctx.admin.flightInput(0,false);assert(ok,why);pausedPawn=id
   end
   reset();return true
  end
  pausedPawn=nil
  if activeId~=id then
   refreshBindings();activeId=id
   for _,list in pairs(vertical)do for _,name in ipairs(list)do if value(s.pc,name)>0 then blocked[name]=true end end end
   return true -- held controls must release after closing a menu/transition
  end
  local axes={[60]=0,[61]=0}
  for _,row in ipairs(bindings)do axes[row.command]=axes[row.command]+value(s.pc,row.key)*row.scale end
  local amount={up=0,down=0}
  for direction,list in pairs(vertical)do for _,name in ipairs(list)do
   local v=value(s.pc,name)
   if blocked[name]then if v==0 then blocked[name]=nil end;v=0 end
   if not conflicts[name]then amount[direction]=math.max(amount[direction],v)end
  end end
  local axis=math.max(-1,math.min(1,amount.up-amount.down))
  local horizontal=math.abs(axes[60])>0.01 or math.abs(axes[61])>0.01
  local ok,why=ctx.admin.flightInput(axis,horizontal);assert(ok,why)
  local yaw=0;for _,row in ipairs(cameraBindings)do yaw=yaw+value(s.pc,row.key)*row.scale end
  if invertX then yaw=-yaw end
  local now=ctx.flightClock and ctx.flightClock()or os.clock()
  camera.tick(s,yaw,lastCameraTime and now-lastCameraTime or .016);lastCameraTime=now
  return true
 end
 function api.tick()
  if running then return true end;running=true
  local ok,a,b=pcall(tick);running=false
  if not ok or a==false then
   pcall(camera.reset)
   reset();local reason=tostring(ok and b or a);lastError=reason
   if lastLoggedError~=reason then lastLoggedError=reason;if ctx.log then ctx.log('Flight input: '..reason)end end
   return false,reason
  end
  lastError=nil;return a,b
 end
 function api.start()
  if closed then return false,'Flight input is shut down.'end
  if handle then return true end
  handle=LoopInGameThreadWithDelay(16,function()if not closed then api.tick()end end)
  return handle~=nil
 end
 function api.stop()
  if handle then CancelDelayedAction(handle);handle=nil end
  camera.reset();reset();return true
 end
 function api.shutdown()api.stop();closed=true;return true end
 function api.state()
  local copy={};for k,v in pairs(conflicts)do copy[k]=v end
  return{running=handle~=nil,active=activeId~=nil,error=lastError,conflicts=copy,tooltip=M.tooltip}
 end
 return api
end
return M
