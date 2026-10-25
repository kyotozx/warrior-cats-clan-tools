-- Renderer adapter: all widgets are created by the root's native game skin.
local M={}
local padNames={Gamepad_FaceButton_Bottom='A / Cross',Gamepad_FaceButton_Right='B / Circle',Gamepad_FaceButton_Left='X / Square',Gamepad_FaceButton_Top='Y / Triangle',Gamepad_LeftShoulder='LB / L1',Gamepad_RightShoulder='RB / R1',Gamepad_LeftTrigger='LT / L2',Gamepad_RightTrigger='RT / R2',Gamepad_LeftThumbstick='Left stick click',Gamepad_RightThumbstick='Right stick click',Gamepad_Special_Left='View / Touchpad',Gamepad_Special_Right='Menu / Options',Gamepad_LeftX='Left stick horizontal',Gamepad_LeftY='Left stick vertical',Gamepad_RightX='Right stick horizontal',Gamepad_RightY='Right stick vertical',Gamepad_LeftTriggerAxis='Left trigger axis',Gamepad_RightTriggerAxis='Right trigger axis'}
local function keyLabel(key)
 if not key then return'Unrecognized native key'end
 return padNames[key]or key:gsub('Gamepad_DPad_','D-pad '):gsub('SpaceBar','Space'):gsub('LeftControl','Left Ctrl'):gsub('RightControl','Right Ctrl'):gsub('([a-z])([A-Z])','%1 %2')
end
local function limitLabel(n)return n==0 and'Unlimited'or tostring(math.floor(n+.5))..' FPS'end
local function bindingLabel(row)
 local label=row.label or('Command '..row.command)
 if row.kind==1 and row.device=='keyboard'then
  local negative=row.scale_bits>=2147483648
  local pairs={[60]={'Move forward','Move backward'},[61]={'Move right','Move left'},[62]={'Look up','Look down'},[63]={'Look right','Look left'},[64]={'Rotate appearance right','Rotate appearance left'}}
  if pairs[row.command]then label=pairs[row.command][negative and 2 or 1]end
 end
 return label
end
function M.new(ctx,p)
 assert(type(p)=='table'and p.text and p.button and p.panel and p.refresh and p.notify,'Settings UI primitives required')
 local api={};local state={device='keyboard',page=1,keyPage=1,customCap=120};local fpsLabel;local lastCounter
 local text,button,panel=p.text,p.button,p.panel
 local function refresh()fpsLabel=nil;p.refresh()end
 local function notice(message)p.notify(message)end
 local function video()return assert(ctx.settings_extensions,'Video settings backend is unavailable')end
 local function controls()return assert(ctx.keybinds,'Controls backend is unavailable')end
 local function invoke(fn,message,after)
  local ok,a,b=pcall(fn)
  if not ok or a==false then notice(tostring(ok and b or a));return false end
  if after then after()end
  if message then notice(message)end;refresh();return true
 end
 local function note(message,y)text(message,450,y,1290,17)end
 local function header(title,subtitle)
  text(title,430,135,1340,31,nil,true);text(subtitle,432,192,1340,17)
 end
 function api.counterText()
  local backend=ctx.settings_extensions;if not backend then return nil end
  local s=backend.status();if not s.counter then return nil end
  return s.fps and('FPS: '..math.floor(s.fps+.5))or'FPS: --'
 end
 function api.tick()
  if not fpsLabel then return end
  local label=api.counterText()or'FPS counter is off'
  if lastCounter~=label and ctx.valid and ctx.valid(fpsLabel)and FText then fpsLabel:SetText(FText(label));lastCounter=label end
 end
 function api.videoPage()
  header('Video settings','Changes apply to the game and are saved immediately.')
  local backend=video();local s=backend.status();local v=s.video
  if not v then panel(430,260,1350,180);note(s.error or'Video settings are unavailable.',290);button('Retry',450,350,240,62,refresh);return end
  panel(430,250,1350,255);note('Frame limit: '..limitLabel(v.limit),268)
  local limits={30,45,60,90,120,144,165,240,360,0}
  for i,cap in ipairs(limits)do
   local x=450+((i-1)%5)*262;local y=312+math.floor((i-1)/5)*84
   button(limitLabel(cap),x,y,242,65,function()invoke(function()return backend.set_fps(cap)end,'Frame limit set to '..limitLabel(cap)..'.')end,v.limit==cap,not v.fixed)
  end
  panel(430,523,1350,135);text('Custom limit',450,535,270,18,nil,true)
  local function change(delta)return function()state.customCap=math.max(15,math.min(1000,state.customCap+delta));refresh()end end
  button('- 10',450,575,145,63,change(-10));button('- 1',610,575,145,63,change(-1))
  text(state.customCap..' FPS',780,590,215,22,nil,true)
  button('+ 1',1010,575,145,63,change(1));button('+ 10',1170,575,145,63,change(10))
  button('Apply custom',1340,575,420,63,function()invoke(function()return backend.set_fps(state.customCap)end,'Custom frame limit saved.')end,false,not v.fixed)
  panel(430,677,1350,167)
  button('VSync: '..(v.vsync and'On'or'Off'),450,697,385,65,function()invoke(function()return backend.set_vsync(not v.vsync)end,'VSync updated.')end,v.vsync)
  button('FPS counter: '..(s.counter and'On'or'Off'),860,697,420,65,function()invoke(function()return backend.set_counter(not s.counter)end)end,s.counter)
  lastCounter=api.counterText()or'FPS counter is off';fpsLabel=text(lastCounter,1320,711,425,23,nil,true)
  note(v.vsync and'VSync may limit output to your display refresh rate.'or'VSync is off. Unlimited removes the game frame limiter.',787)
  text(v.fixed and'A fixed engine timestep is active; frame-limit controls are unavailable.'or s.custom_limit and'Custom frame limits replace the game\'s original 30–60 FPS smoothing.'or'The original game frame smoothing is currently in use.',450,862,1300,16)
  button('Restore original video settings',450,914,625,62,function()invoke(backend.restore_video,'Original video settings restored.')end,false,s.can_restore)
  if s.error then text(s.error:sub(1,110),1110,920,650,14)end
 end
 local function currentRows()
  local rows,err=controls().bindings(state.device)
  if rows==false or rows==nil then notice(err or'Controls unavailable');return{}end
  local visible={}
  for _,row in ipairs(rows)do if row.key then visible[#visible+1]=row end end
  table.sort(visible,function(a,b)
   local am=a.scope=='Menu / interface'and 1 or 0;local bm=b.scope=='Menu / interface'and 1 or 0
   if am~=bm then return am<bm end
   if a.command~=b.command then return a.command<b.command end
   return tostring(a.id)<tostring(b.id)
  end)
  return visible
 end
 local function selectKey(selected,key,allowConflict)
  invoke(function()return controls().rebind(selected.id,key,allowConflict and{allow_conflict=true}or nil)end,'Control updated: '..bindingLabel(selected)..'.',function()state.selected=nil;state.conflict=nil end)
 end
 local function picker()
  local selected=state.selected
  header('Choose a key',bindingLabel(selected)..'  |  Current: '..keyLabel(selected.key))
  if state.conflict then
   panel(430,290,1350,470);text('This key is already in use',460,315,1260,27,nil,true)
   text(keyLabel(state.conflict.key)..' is also assigned to:',460,376,1260,20)
   for i,label in ipairs(state.conflict.labels)do if i<=4 then text(label,485,422+(i-1)*43,1220,18)end end
   text('Both actions may respond in the same context.',460,620,1260,18)
   button('Choose another key',460,685,610,65,function()state.conflict=nil;refresh()end,true)
   button('Use this key anyway',1100,685,650,65,function()selectKey(selected,state.conflict.key,true)end)
   return
  end
  local keys=controls().available_keys(selected);local pages=math.max(1,math.ceil(#keys/20));state.keyPage=math.max(1,math.min(state.keyPage,pages))
  text('Page '..state.keyPage..' / '..pages,1510,255,260,18)
  for offset=0,19 do local key=keys[(state.keyPage-1)*20+offset+1];if key then
   local x=430+(offset%4)*342;local y=306+math.floor(offset/4)*102
   button(keyLabel(key),x,y,324,80,function()
    local labels={};local seen={};for _,row in ipairs(currentRows())do
     if row.id~=selected.id and row.command~=selected.command and row.key==key then local label=bindingLabel(row);if not seen[label]then labels[#labels+1]=label;seen[label]=true end end
    end
    if #labels>0 then state.conflict={key=key,labels=labels};refresh()else selectKey(selected,key,false)end
   end,key==selected.key)
  end end
  button('Previous keys',430,847,320,65,function()state.keyPage=state.keyPage-1;refresh()end,false,state.keyPage>1)
  button('Next keys',776,847,320,65,function()state.keyPage=state.keyPage+1;refresh()end,false,state.keyPage<pages)
  button('Cancel',1122,847,656,65,function()state.selected=nil;refresh()end)
  text('F6 remains available for recovery. Axis types and direction scales are preserved.',450,941,1300,15)
 end
 function api.keybindPage()
  fpsLabel=nil
  if state.selected then picker();return end
  header('Game controls','Keyboard and controller mappings are saved for the active profile.')
  if state.resetAll then
   panel(430,290,1350,390);text('Restore all game controls?',460,320,1260,27,nil,true)
   text('This removes every keyboard and controller override for this profile.',460,390,1260,20)
   text('The game\'s existing default or custom control scheme will be used.',460,443,1260,18)
   button('Keep current controls',460,558,610,70,function()state.resetAll=nil;refresh()end,true)
   button('Restore all controls',1100,558,650,70,function()invoke(controls().reset_all,'Game controls restored.',function()state.resetAll=nil end)end)
   return
  end
  button('Keyboard',430,235,300,62,function()state.device='keyboard';state.page=1;refresh()end,state.device=='keyboard')
  button('Controller',750,235,300,62,function()state.device='gamepad';state.page=1;refresh()end,state.device=='gamepad')
  button('Restore all controls',1360,235,420,62,function()state.resetAll=true;refresh()end)
  local rows=currentRows();local pages=math.max(1,math.ceil(#rows/7));state.page=math.max(1,math.min(state.page,pages))
  for offset=0,6 do local row=rows[(state.page-1)*7+offset+1];if row then
   local y=324+offset*79;panel(430,y,1350,70)
   text(bindingLabel(row),450,y+8,465,18,nil,true)
   text(row.custom and('Original: '..keyLabel(row.original))or row.reason or((row.scope or'Gameplay')..(row.kind==1 and' · Axis binding'or' · Button binding')),450,y+40,850,12)
   text(keyLabel(row.key),930,y+16,410,19)
   button('Change',1360,y+7,190,56,function()state.selected=row;state.keyPage=1;state.conflict=nil;refresh()end,false,row.editable)
   button('Reset',1570,y+7,190,56,function()invoke(function()return controls().reset_binding(row.id)end,'Control restored.')end,false,row.custom and row.editable)
  end end
  button('Previous',430,897,300,62,function()state.page=state.page-1;refresh()end,false,state.page>1)
  button('Next',750,897,300,62,function()state.page=state.page+1;refresh()end,false,state.page<pages)
  text('Page '..state.page..' / '..pages,1090,913,250,19)
  text('F6 and controller pause are recovery controls.',1320,907,460,13)
 end
 function api.back()
  if state.conflict then state.conflict=nil;refresh();return true end
  if state.selected then state.selected=nil;refresh();return true end
  if state.resetAll then state.resetAll=nil;refresh();return true end
  return false
 end
 function api.reset()state.selected=nil;state.conflict=nil;state.resetAll=nil;state.page=1;state.keyPage=1;fpsLabel=nil end
 return api
end
return M
