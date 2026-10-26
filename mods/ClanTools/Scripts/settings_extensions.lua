-- Real engine video settings and game command bindings. All public methods use dot calls.
local directory=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(directory..'json.lua')
local keyboardKeys=dofile(directory..'keyboard_keys.lua')
local runtimeValid=dofile(directory..'runtime_valid.lua').valid
local M={}
local editableLabels={[65]='Interact',[70]='Run',[71]='Crouch',[72]='Pounce',[74]='Map',[75]='Inventory',[76]='Quests',[77]='Scent tracking',[78]='Reset camera'}
local enumNames={[65]='Player_Interact',[70]='Player_Run',[71]='Player_Crouch',[72]='Player_Pounce',[74]='Player_Show_Map',[75]='Player_Show_Inventory',[76]='Player_Show_Quest',[77]='Player_Scent_Tracking',[78]='Player_Camera_Reset'}
local function finite(n)return type(n)=='number'and n==n and n~=math.huge and n~=-math.huge end
local function copy(t)local c={};for k,v in pairs(t)do c[k]=type(v)=='table'and copy(v)or v end;return c end
local function read(path)local f=io.open(path,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
local function save(path,value)
 local text=json.encode(value);local temp=path..'.tmp';local backup=path..'.previous'
 local f=assert(io.open(temp,'wb'));assert(f:write(text));assert(f:close())
 local old=read(path);if old then
  assert(not read(backup),'An unfinished settings backup needs recovery: '..backup)
  assert(os.rename(path,backup))
 end
 local ok,err=os.rename(temp,path)
 if not ok then if old then os.rename(backup,path)end;error(err)end
 if old then assert(os.remove(backup))end
end
function M.new(ctx)
 ctx=ctx or{};local api={};local lastError;local sample,fps;local appliedEngine;local sharedVSync;local cachedEngine
 local path=(ctx.mod_root or ctx.root or directory..'../')..'settings-extensions.json'
 local pref={version=1,counter=false,custom_limit=false}
 local load=ctx.load_preferences or function()local raw=read(path);return raw and json.decode(raw)end
 local persist=ctx.save_preferences or function(p)save(path,p)end
 local ok,loaded=pcall(load)
 if ok and type(loaded)=='table'and loaded.version==1 then
  pref.counter=loaded.counter==true;pref.custom_limit=loaded.custom_limit==true
  if type(loaded.original)=='table'and finite(loaded.original.limit)and type(loaded.original.vsync)=='boolean'and type(loaded.original.smooth)=='boolean'then pref.original=copy(loaded.original)end
 end
 local function valid(o)return o and(ctx.valid and ctx.valid(o)or not ctx.valid and runtimeValid(o))end
 local function backend()
  if ctx.video then return ctx.video end
  if not valid(cachedEngine)then cachedEngine=FindFirstOf('GameEngine')end
  local engine=cachedEngine;assert(valid(engine),'Game engine unavailable')
  local settings=engine.GameUserSettings;assert(valid(settings),'Game video settings unavailable')
  return {
   identity=engine:GetAddress(),
   get=function()return{limit=settings:GetFrameRateLimit(),vsync=settings:IsVSyncEnabled(),smooth=engine.bSmoothFrameRate,fixed=engine.bUseFixedFrameRate}end,
   apply=function(v)settings:SetFrameRateLimit(v.limit);settings:SetVSyncEnabled(v.vsync);engine.bSmoothFrameRate=v.smooth;settings:ApplyNonResolutionSettings()end,
   save=function()settings:SaveSettings()end,
   shared_vsync=function(v)return sharedVSync(v)end,
   persisted=function()
    local raw=assert(read((os.getenv('LOCALAPPDATA')or'')..'/Wrc/Saved/Config/Windows/GameUserSettings.ini'),'Saved video configuration unavailable')
    local section=raw:match('%[/Script/Engine.GameUserSettings%]([^%[]+)')or raw
    local limit=tonumber(section:match('FrameRateLimit=([^\r\n]+)'));local vsync=section:match('bUseVSync=([^\r\n]+)')
    return{limit=limit,vsync=vsync and vsync:lower()=='true'}
   end,
  }
 end
 local function current(b)
  local v=b.get();assert(type(v)=='table'and finite(v.limit)and type(v.vsync)=='boolean'and type(v.smooth)=='boolean','Unsupported engine settings field types');return v
 end
 local function same(a,b)return finite(a.limit)and math.abs(a.limit-b.limit)<0.01 and a.vsync==b.vsync and(a.smooth==nil or a.smooth==b.smooth)end
 local function transact(change,preferences)
  local b=backend();local old=current(b);assert(not old.fixed,'Fixed engine timestep is active; this frame limiter cannot override it safely')
  local oldPref=copy(pref);local desired=copy(old);change(desired)
  local changeShared=desired.vsync~=old.vsync and b.shared_vsync~=nil
  local oldShared;if changeShared then oldShared=b.shared_vsync();assert(type(oldShared)=='boolean','Shared VSync state unavailable')end
  local success,err=pcall(function()
   b.apply(desired);assert(same(current(b),desired),'Video setting readback failed');b.save()
   assert(same(b.persisted(),desired),'Saved video setting readback failed')
   if changeShared then assert(b.shared_vsync(desired.vsync)==desired.vsync,'Shared VSync save failed')end
   local nextPref=copy(pref);if not nextPref.original then nextPref.original=copy(old)end
   preferences(nextPref);persist(nextPref);pref=nextPref;appliedEngine=b.identity
  end)
  if not success then
   local reverted,rollback=pcall(function()b.apply(old);b.save();if changeShared then assert(b.shared_vsync(oldShared)==oldShared,'Shared VSync rollback failed')end;assert(same(current(b),old),'Video rollback readback failed');persist(oldPref)end)
   error(tostring(err)..(reverted and''or'; rollback failed: '..tostring(rollback)))
  end
  return true
 end
 local function guarded(fn,...)
  local success,a,b=pcall(fn,...);if success then lastError=nil;return a,b end
  lastError=tostring(a);if ctx.log then ctx.log('Settings: '..lastError)end;return false,lastError
 end
 function api.set_fps(limit)
  return guarded(function()
   if limit=='unlimited'then limit=0 end
   assert(finite(limit)and(limit==0 or limit>=15 and limit<=1000),'Choose Unlimited or a frame limit from 15 to 1000')
   return transact(function(v)v.limit=limit;v.smooth=false end,function(p)p.custom_limit=true end)
  end)
 end
 function api.set_vsync(enabled)
  return guarded(function()assert(type(enabled)=='boolean','VSync requires a boolean');return transact(function(v)v.vsync=enabled end,function()end)end)
 end
 function api.restore_video()
  return guarded(function()
   assert(pref.original,'No original video settings were captured');local original=copy(pref.original)
   return transact(function(v)v.limit=original.limit;v.vsync=original.vsync;v.smooth=original.smooth end,function(p)p.custom_limit=false;p.original=nil end)
  end)
 end
 function api.set_counter(enabled)
  return guarded(function()assert(type(enabled)=='boolean','Counter requires a boolean');local p=copy(pref);p.counter=enabled;persist(p);pref=p;sample=nil;fps=nil;return true end)
 end
 local function clock(snapshot)
  if ctx.frame_sample then return ctx.frame_sample(snapshot)end
  local world=snapshot and(snapshot.world or snapshot.pc or snapshot.gameState);assert(valid(world),'FPS counter world unavailable')
  local system=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
  local gameplay=StaticFindObject('/Script/Engine.Default__GameplayStatics')
  return system:GetFrameCount(),gameplay:GetRealTimeSeconds(world)
 end
 function api.tick(snapshot)
  return guarded(function()
   if pref.custom_limit then
    local b=backend();if appliedEngine~=b.identity then local v=current(b);assert(not v.fixed,'Fixed engine timestep is active');v.smooth=false;b.apply(v);assert(current(b).smooth==false,'Frame smoothing override failed');appliedEngine=b.identity end
   end
   if not pref.counter then return true end
   if not snapshot then sample=nil;fps=nil;return true end
   local count,seconds=clock(snapshot);assert(finite(count)and finite(seconds),'FPS counter sample invalid')
   if not sample or count<sample.count or seconds<=sample.time then sample={count=count,time=seconds};fps=nil
   elseif seconds-sample.time>=0.5 then fps=(count-sample.count)/(seconds-sample.time);sample={count=count,time=seconds}end
   return true
  end)
 end
 function api.status()
  local success,v=pcall(function()return current(backend())end)
  return{video=success and v or nil,error=lastError or(not success and tostring(v)or nil),counter=pref.counter,fps=fps,
   custom_limit=pref.custom_limit,can_restore=pref.original~=nil,vsync_note=success and v.vsync and'VSync can cap output at the display refresh rate.'or nil}
 end
 local bridge,requestId,byIndex=nil,0,nil
 local function key_context()
  if ctx.key_context then return ctx.key_context()end
  local s=ctx.snapshot and ctx.snapshot();assert(s and s.offline==true and valid(s.pc),'Load an offline campaign to change controls')
  local manager=FindFirstOf('WrcSaveManager');local input=s.pc.PlayerInput
  assert(valid(manager)and valid(input),'Game keyboard mapping unavailable')
  return{manager=manager,input=input,pc=s.pc,profile=s.profile}
 end
 local function native(action,command,value)
  if ctx.key_native then return ctx.key_native(action,command,value)end
  local c=key_context();local bin=(ctx.mod_root or ctx.root or directory..'../')..'bin/'
  if not bridge then bridge=assert(package.loadlib(bin..(ctx.settings_dll or'settings-bridge-v2.dll'),'Settings_command'))end
  requestId=requestId+1
  local f=assert(io.open(bin..'settings-request.txt','wb'))
  assert(f:write(string.format('%u %s %x %x %x %d %s\n',requestId,action,c.manager:GetAddress(),c.input:GetAddress(),c.pc:GetAddress(),command or 0,value or'-')));assert(f:close());bridge()
  local response=assert(read(bin..'settings-response.txt'),'No response from keyboard adapter')
  local id,status,message=response:match('^(%d+) (%S+)([^\r\n]*)')
  assert(tonumber(id)==requestId,'Stale keyboard adapter response');assert(status=='OK',message or'Keyboard adapter failed')
  return response
 end
 local function key_name(index,number)
  if ctx.key_name then return ctx.key_name(index,number)end
  if not byIndex then byIndex={};for name in pairs(keyboardKeys)do local n=FName(name);if n:ToString()==name then byIndex[n:GetComparisonIndex()]=name end end end
  return number==0 and byIndex[index]or nil
 end
 sharedVSync=function(value)
  local response=native('VSYNC',value==nil and 2 or value and 1 or 0)
  local actual=response:match('[\r\n]V ([01])');assert(actual,'Shared VSync response missing');actual=actual=='1'
  if value~=nil then
   assert(actual==value,'Shared VSync runtime readback failed');local c=key_context();c.manager:Save('ClanTools video settings',false,false)
   local all=json.decode(assert(read((os.getenv('LOCALAPPDATA')or'')..'/Wrc/Saved/SaveGames/WrcGame.json')))
   assert(all[c.profile]and all[c.profile].Shared and all[c.profile].Shared.SettingsData.VSync==value,'Shared VSync disk readback failed')
  end
  return actual
 end
 local function bindings()
  local response=native('LIST');local mode=response:match('[\r\n]M ([01])');assert(mode,'Keyboard mode is missing from response');local rows={custom_controls=mode=='1'}
  for line in response:gmatch('[^\r\n]+')do if line:sub(1,2)=='B 'then
   local command,kind,index,number,scale,enabled,raw=line:match('^B (%d+) (%d+) (%d+) (%d+) ([%d%.eE+%-]+) ([01]) (%S+)$')
   assert(command,'Invalid keyboard mapping response');command=tonumber(command);index=tonumber(index);number=tonumber(number)
   local name=key_name(index,number)
   rows[#rows+1]={command=command,kind=tonumber(kind),key=name,key_index=index,key_number=number,scale=tonumber(scale),editable=enabled=='1'and editableLabels[command]~=nil and name~=nil,
    label=editableLabels[command]or('Game command '..command),raw=raw,icon=name and keyboardKeys[name]}
  end end
  assert(#rows>0 and #rows<=256,'Keyboard map is empty or unsupported');return rows
 end
 function api.bindings()return guarded(bindings)end
 function api.available_keys()
  local out={};for name,icon in pairs(keyboardKeys)do
   if name~='Escape'and name~='Enter'and name~='F6'and not name:find('Mouse')then out[#out+1]={key=name,icon=icon}end
  end;table.sort(out,function(a,b)return a.key<b.key end);return out
 end
 local function save_controls(command,raw,custom)
  if ctx.save_controls then return ctx.save_controls(command,raw,custom)end
  local c=key_context();c.manager:Save('ClanTools controls',false,false)
  -- The game emits WrcGame.json through its own normal Save pathway. Verify that
  -- same profile's shared keyboard value; never patch this debug JSON ourselves.
  local document=json.decode(assert(read((os.getenv('LOCALAPPDATA')or'')..'/Wrc/Saved/SaveGames/WrcGame.json'),'Game settings save readback unavailable'))
  local profile=document[c.profile];local keyboard=profile and profile.Shared and profile.Shared.InputKeyboard
  if command then assert(keyboard and(keyboard[enumNames[command]]or'')==(raw=='-'and''or raw),'Saved keyboard setting readback failed')end
  local player=profile and profile.Shared and profile.Shared.PlayerSettingsData
  assert(player and player['0']and player['0'].CustomControls==custom,'Saved custom-controls mode readback failed')
  return true
 end
 local function rebind(command,newKey,reset)
  assert(editableLabels[command],'This command does not use the native editable keyboard settings')
  if not reset then
   assert(type(newKey)=='string'and keyboardKeys[newKey],'Choose a native game keyboard key')
   assert(newKey~='Escape'and newKey~='Enter'and newKey~='F6'and not newKey:find('Mouse'),'This key is reserved for menu access')
  end
  local rows=bindings();local previous
  for _,row in ipairs(rows)do
   if row.command==command and row.editable then assert(not previous,'Ambiguous game binding');previous=row
   elseif not reset and row.key==newKey then error('Key is already used by '..row.label)end
  end
  assert(previous,'Native editable binding not found')
  if not reset and previous.key==newKey then return true end
  local success,err=pcall(function()
   native(reset and'RAW'or'SET',command,reset and'-'or newKey)
   local changed
   local after=bindings();for _,row in ipairs(after)do if row.command==command then changed=row;break end end
   assert(changed and(reset and changed.raw=='-'or not reset and changed.key==newKey),'Rebuilt game mapping readback failed')
   assert(reset or after.custom_controls,'Native custom controls were not enabled')
   assert(save_controls(command,changed.raw,after.custom_controls)~=false,'Game did not save keyboard settings')
  end)
  if not success then
   local restored,why=pcall(function()native('RAW',command,previous.raw);native('MODE',rows.custom_controls and 1 or 0);local restoredRows=bindings();local found;for _,row in ipairs(restoredRows)do if row.command==command then found=row;break end end;assert(found and found.raw==previous.raw and found.key==previous.key and restoredRows.custom_controls==rows.custom_controls,'Keyboard rollback readback failed');assert(save_controls(command,previous.raw,rows.custom_controls)~=false,'Could not save keyboard rollback')end)
   error(tostring(err)..(restored and''or'; rollback failed: '..tostring(why)))
  end
  return true
 end
 function api.rebind(command,key)return guarded(rebind,command,key,false)end
 function api.reset_binding(command)return guarded(rebind,command,nil,true)end
 function api.set_custom_controls(enabled)
  return guarded(function()
   assert(type(enabled)=='boolean','Custom controls requires a boolean');local old=bindings().custom_controls
   local success,err=pcall(function()native('MODE',enabled and 1 or 0);assert(bindings().custom_controls==enabled,'Custom controls mode readback failed');assert(save_controls(nil,nil,enabled)~=false,'Could not save custom controls mode')end)
   if not success then local rollback,why=pcall(function()native('MODE',old and 1 or 0);assert(save_controls(nil,nil,old)~=false)end);error(tostring(err)..(rollback and''or'; rollback failed: '..tostring(why)))end
   return true
  end)
 end
 function api.shutdown()sample=nil;fps=nil;return true end
 return api
end
return M
