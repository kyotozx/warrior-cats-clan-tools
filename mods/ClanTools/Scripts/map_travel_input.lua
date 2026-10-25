-- Map-only keyboard/controller shortcut. The original map keeps input/focus.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local M={}
local shortcuts={'F9','Gamepad_LeftThumbstick'}
function M.new(ctx)
 assert(ctx.snapshot and ctx.valid and ctx.mapTravel,'Native map input context required.')
 local api={};local presenter=ctx.mapTravelPresenter or dofile(folder..'map_travel_overlay.lua').new(ctx)
 local active,handle,closed,running,lastError,lastLog=nil,nil,false,false,nil,nil
 local held,keys,conflicts={},{},{};local pending,message
 local eventHeld,edges={},{};local popupId;local keyHooks={}
 local function key(name)if not keys[name]then keys[name]={KeyName=(ctx.make_name or FName)(name)}end;return keys[name]end
 local function clear()
  if active or pending then ctx.mapTravel.reset()end
  active=nil;pending=nil;held={};eventHeld={};edges={};popupId=nil;conflicts={};message=nil;presenter.hide()
 end
 local function findMap(s)
  if ctx.mapTravelFindPopup then return ctx.mapTravelFindPopup(s)end
  local found
  for _,popup in ipairs(FindAllOf('GuiPopupWorldMap')or{})do
   if ctx.valid(popup)and popup:IsInViewport()and popup:IsVisible()then assert(not found,'Multiple active world maps.');found=popup end
  end
  return found
 end
 local function session(s,popup)
  return table.concat({s.worldId or'',s.profile or'',tostring(s.slot),tostring(s.pawn:GetAddress()),tostring(s.pc:GetAddress()),tostring(popup:GetAddress())},'|')
 end
 local function refreshKeys()
  conflicts={}
  if not(ctx.keybinds and ctx.keybinds.bindings)then return end
  local bindings,why=ctx.keybinds.bindings();assert(type(bindings)=='table',why or'Could not check map shortcut conflicts.')
  for _,row in ipairs(bindings)do
   -- Default L3 is native Common_ButtonStickL (13); the map's handler has no
   -- L3 action. Any additional mapping to either shortcut fails closed.
   if(row.key=='F9'or row.key=='Gamepad_LeftThumbstick')and row.command~=13 then conflicts[row.key]=row.label or('command '..tostring(row.command))end
  end
 end
 local function hint()
  local out={};if not conflicts.F9 then out[#out+1]='F9'end;if not conflicts.Gamepad_LeftThumbstick then out[#out+1]='L3'end
  return #out>0 and table.concat(out,' / ')or nil
 end
 local function show(s)
  local shortcut=hint();local status=ctx.mapTravel.status()
  local title='WORLD MAP TRAVEL';local line,detail
  if not shortcut then line='Map travel shortcuts conflict with your controls.';detail='Change F9 or L3 in Controls to use map travel.'
  elseif pending then line=pending.label;detail='Release, then '..shortcut..' to travel. Move the map to cancel.'
  elseif not status.verified then line='Map travel is waiting for compatibility verification.';detail='Your original map controls remain available.'
  else line='Move the map pointer. '..shortcut..' previews the destination.';detail='Clear, loaded, walkable ground only. Press again to confirm.'end
  if message then line=message:sub(1,112)end
  local ok,why=presenter.show(s,title,line,detail);assert(ok~=false,why)
 end
 local function tick()
  if closed then return false,'Map input is shut down.'end
  local s=ctx.snapshot()
  if not s or s.offline~=true or s.phase~=4 or s.combat or not ctx.valid(s.pawn)or not ctx.valid(s.pc)
   or not ctx.valid(s.pc.Pawn)or s.pc.Pawn:GetAddress()~=s.pawn:GetAddress()
   or(ctx.ui and ctx.ui.opened)or ctx.appearanceActive or(ctx.textPrompt and ctx.textPrompt.active())then clear();return true end
  local popup=findMap(s);if not ctx.valid(popup)then clear();return true end
  local id=session(s,popup)
  if active~=id then
   clear();refreshKeys();active=id;popupId=popup:GetAddress()
   for _,name in ipairs(shortcuts)do held[name]=s.pc:IsInputKeyDown(key(name))==true end
   show(s);return true -- a held shortcut cannot confirm when the map appears
  end
  if pending then
   local ok,current=ctx.mapTravel.inspect()
   local age=(ctx.mapTime or os.time)()-pending.time
   if not ok or age<0 or age>30 or math.abs(current.world.X-pending.point.X)>2 or math.abs(current.world.Y-pending.point.Y)>2 then
    pending=nil;ctx.mapTravel.reset();message=not ok and tostring(current)or age>30 and'Preview expired. Choose the point again.'or'Destination moved. Preview the new point.'
   end
  end
  show(s) -- Do not accept input if the visible explanation could not render.
  local pressed,anyDown=false,false
  for _,name in ipairs(shortcuts)do
   local down=eventHeld[name]==true or s.pc:IsInputKeyDown(key(name))==true
   anyDown=anyDown or(down and not conflicts[name])
   if (edges[name]or(down and not held[name]))and not conflicts[name]then pressed=true end
   edges[name]=nil
   held[name]=down
  end
  if pending and not pending.armed then
   if not anyDown then pending.armed=true end
   pressed=false
  end
  if not pressed then return true end
  if not ctx.mapTravel.status().verified then message='Map travel is waiting for compatibility verification.';show(s);return true end
  if pending then
   local ok,why=ctx.mapTravel.travel(pending.token);pending=nil;ctx.mapTravel.reset()
   message=ok and'Travel complete. Close the map to resume.'or tostring(why)
  else
   local ok,current=ctx.mapTravel.inspect()
   if not ok then message=tostring(current)
   else
    local good,preview=ctx.mapTravel.preview()
    if good then pending={token=preview.token,label=preview.label,point={X=current.world.X,Y=current.world.Y},time=(ctx.mapTime or os.time)(),armed=false};message=nil
    else message=tostring(preview)end
   end
  end
  show(s);return true
 end
 function api.tick()
  if running then return true end;running=true;local ok,a,b=pcall(tick);running=false
  if not ok or a==false then
   local why=tostring(ok and b or a);clear();lastError=why
   if lastLog~=why then lastLog=why;if ctx.log then ctx.log('Map travel input: '..why)end end
   return false,why
  end
  lastError=nil;return a,b
 end
 function api.start()
  if closed then return false,'Map input is shut down.'end
  if type(RegisterHook)=='function'and #keyHooks==0 then
   for _,event in ipairs({'Pressed','Released'})do
    local path='/Script/SwtEngine.SwtScreen:OnKey'..event
    local pre,post=RegisterHook(path,function(o,k)
     if closed or not popupId then return end
     local object=o:get();if not ctx.valid(object)or object:GetAddress()~=popupId then return end
     local name=k:get().KeyName:ToString();if name~='F9'and name~='Gamepad_LeftThumbstick'then return end
     if event=='Pressed'then if not eventHeld[name]then edges[name]=true end;eventHeld[name]=true
     else eventHeld[name]=false end
    end)
    keyHooks[#keyHooks+1]={path,pre,post}
   end
  end
  if not handle then handle=LoopInGameThreadWithDelay(16,function()if not closed then api.tick()end end)end
  return handle~=nil
 end
 function api.stop()if handle then CancelDelayedAction(handle);handle=nil end;clear();return true end
 function api.shutdown()api.stop();closed=true;for _,h in ipairs(keyHooks)do UnregisterHook(h[1],h[2],h[3])end;keyHooks={};return true end
 function api.state()return{active=active~=nil,pending=pending~=nil,error=lastError,running=handle~=nil}end
 return api
end
return M
