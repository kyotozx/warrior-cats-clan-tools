-- Native menu and generated gameplay mappings, including axes and controller.
-- Independent of the game's limited CustomControls save override path.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua');local keyboard=dofile(dir..'keyboard_keys.lua');local gamepad=dofile(dir..'gamepad_keys.lua');local commands=dofile(dir..'input_commands.lua')
local runtimeValid=dofile(dir..'runtime_valid.lua').valid
local M={}
local function clone(t)local c={};for k,v in pairs(t)do c[k]=type(v)=='table'and clone(v)or v end;return c end
local function integer(n)return type(n)=='number'and n==math.floor(n)end
local function identity(r)return table.concat({r.device,r.command,r.kind,r.original,r.scale_bits},':')end
local function read(p)local f=io.open(p,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
local function write(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));assert(f:close())end
local function axis(key)
 if key:match('2D$')then return'vector'end
 if key:match('TriggerAxis$')then return'trigger'end
 if key=='Gamepad_LeftX'or key=='Gamepad_LeftY'or key=='Gamepad_RightX'or key=='Gamepad_RightY'then return'stick'end
 return'digital'
end
function M.new(ctx)
 ctx=ctx or{};local root=ctx.mod_root or ctx.root or dir..'../';if not root:match('[/\\]$')then root=root..'/'end
 local api={};local config={version=2,profiles={}};local current,attached,lastError;local generation=0;local native=ctx.remap_native
 local names,indexes={},{};local path=root..'keybinds.json'
 local function persist(value)
  if ctx.save_keybinds then return assert(ctx.save_keybinds(value)~=false,'Keybind save failed')end
  local tmp=path..'.tmp';local backup=path..'.previous';write(tmp,json.encode(value));local old=read(path)
  if old then assert(not read(backup),'Unfinished keybind backup requires recovery');assert(os.rename(path,backup))end
  local ok,err=os.rename(tmp,path);if not ok then if old then os.rename(backup,path)end;error(err)end
  if old then assert(os.remove(backup))end;return true
 end
 local function allowed(key,device)return type(key)=='string'and((device=='keyboard'and keyboard[key]~=nil)or(device=='gamepad'and gamepad[key]~=nil))end
 local function validate_rule(r)
  return type(r)=='table'and(r.device=='keyboard'or r.device=='gamepad')and integer(r.command)and r.command>=1 and r.command<110 and(r.kind==0 or r.kind==1)
   and integer(r.scale_bits)and r.scale_bits>=0 and r.scale_bits<=4294967295 and allowed(r.original,r.device)and allowed(r.key,r.device)and r.key~='F6'
 end
 local loadedOK,loaded=pcall(function()if ctx.load_keybinds then return ctx.load_keybinds()end;local raw=read(path);return raw and json.decode(raw)end)
 -- Patch 1.1 inserted two mouse-camera commands before customization yaw.
 -- Migrate in memory; persist only after a successful user edit.
 if loadedOK and type(loaded)=='table'and loaded.version==1 and type(loaded.profiles)=='table'then
  loaded=clone(loaded);loaded.version=2
  for _,list in pairs(loaded.profiles)do if type(list)=='table'then for _,rule in pairs(list)do
   if type(rule)=='table'and integer(rule.command)and rule.command>=64 then rule.command=rule.command+2 end
  end end end
 end
 if loadedOK and type(loaded)=='table'and loaded.version==2 and type(loaded.profiles)=='table'then
  local valid=true;for profile,list in pairs(loaded.profiles)do if type(profile)~='string'or type(list)~='table'or #list>192 then valid=false;break end;local seen={};for _,r in ipairs(list)do if not validate_rule(r)then valid=false;break end;local id=identity(r);if seen[id]then valid=false;break end;seen[id]=true end end
  if valid then config=loaded else lastError='Invalid saved keybindings; no overrides loaded'end
 elseif not loadedOK then lastError='Could not read keybindings: '..tostring(loaded)end
 local function index(key)
  if not indexes[key]then local n=ctx.key_index and ctx.key_index(key)or FName(key):GetComparisonIndex();assert(integer(n)and n>0,'Unknown native key '..key);indexes[key]=n;names[n]=key end;return indexes[key]
 end
 local function build_names()if not next(names)then for name in pairs(keyboard)do index(name)end;for name in pairs(gamepad)do index(name)end end end
 local function valid(o)return o and(ctx.valid and ctx.valid(o)or not ctx.valid and runtimeValid(o))end
 local function context(s)
  if ctx.remap_context then return ctx.remap_context(s)end
  assert(s and s.offline==true and type(s.profile)=='string'and valid(s.pc),'Load an offline campaign to edit controls')
  local input=s.pc.PlayerInput;assert(valid(input),'Game player input unavailable')
  return{input=input:GetAddress(),pc=s.pc:GetAddress(),profile=s.profile,world=tostring(s.worldId),object_index=input:GetFullName()}
 end
 local function same(a,b)return a and b and a.input==b.input and a.pc==b.pc and a.profile==b.profile and a.world==b.world and a.object_index==b.object_index end
 local function transport()
  if native then return native end
  local bridge=assert(package.loadlib(root..'bin/'..(ctx.remap_dll or'settings-remap-v3.dll'),'Remap_command'));local sequence=0
  local function send(action,c,rules)
   sequence=sequence+1;local lines={string.format('%d %s %x %x %d %d',sequence,action,c and c.input or 0,c and c.pc or 0,generation,#(rules or{}))}
   for _,r in ipairs(rules or{})do lines[#lines+1]=string.format('%d %d %d %d 0 %u %d 0',r.device=='gamepad'and 0 or 1,r.command,r.kind,index(r.original),r.scale_bits,index(r.key))end
   local responsePath=root..'bin/remap-response.txt';if read(responsePath)then assert(os.remove(responsePath))end
   write(root..'bin/remap-request.txt',table.concat(lines,'\n')..'\n');bridge()
   local response=assert(read(responsePath),'No native remap response');local id,status,message=response:match('^(%d+) (%S+) ([^\r\n]+)')
   assert(tonumber(id)==sequence,'Stale native remap response');assert(status=='OK',message or'Native remap failed');return response
  end
  native={apply=function(c,rules)send('APPLY',c,rules);return true end,remove=function()send('REMOVE');return true end,
   list=function(c)
    local response=send('LIST',c);build_names();local rows={}
    for line in response:gmatch('[^\r\n]+')do if line:sub(1,2)=='B 'then
     local d,command,kind,source,sourceNumber,scale,target,targetNumber=line:match('^B ([01]) (%d+) ([01]) (%d+) (%d+) (%d+) (%d+) (%d+)$')
     assert(d,'Invalid native remap row');local r={device=d=='0'and'gamepad'or'keyboard',command=tonumber(command),kind=tonumber(kind),scale_bits=tonumber(scale),original=sourceNumber=='0'and names[tonumber(source)]or nil,key=targetNumber=='0'and names[tonumber(target)]or nil}
     rows[#rows+1]=r
    end end;assert(#rows>0 and #rows<=512,'Unsupported native input map');return rows
   end}
  return native
 end
 local function report(e)lastError=tostring(e);if ctx.log then ctx.log('Game controls: '..lastError)end end
 local function guarded(fn,... )local ok,a,b=pcall(fn,...);if ok then lastError=nil;return a,b end;report(a);return false,lastError end
 local function stop()
  if attached then assert(transport().remove()~=false,'Could not restore native input maps');attached=nil end
  current=nil;return true
 end
 local function ensure(s)
  local c=context(s);if not same(current,c)then stop();generation=generation+1;current=c end;return c
 end
 local function rows_for(c)
  local rows=transport().list(c);local seen={}
  for _,r in ipairs(rows)do
   if r.original then r.id=identity(r);seen[r.id]=(seen[r.id]or 0)+1 end
   r.label=(commands[r.command]or('Command '..r.command)):gsub('^Player_',''):gsub('_',' '):gsub('([a-z])([A-Z])','%1 %2')
   r.editable=r.original~=nil and r.key~=nil and r.command>=1 and r.command<110 and axis(r.original)~='vector'and not(r.device=='gamepad'and(r.command==91 or r.command==24))
   r.scope=r.command<60 and'Menu / interface'or'Gameplay'
   r.custom=r.original~=r.key
   r.icon=r.device=='keyboard'and keyboard[r.key]or gamepad[r.key]and gamepad[r.key][ctx.controller_family or'xbox']
   if r.device=='gamepad'and(r.command==91 or r.command==24)then r.reason='The controller pause button is retained as a recovery control.'end
  end
  for _,r in ipairs(rows)do if r.id and seen[r.id]>1 then r.editable=false;r.reason='Ambiguous duplicate native binding'end end
  return rows
 end
 local function configured(c)return config.profiles[c.profile]or{}end
 local function apply(c,rules)
  local rows=rows_for(c);local byId={};for _,r in ipairs(rows)do if r.id then byId[r.id]=r end end
  for _,r in ipairs(rules)do local row=byId[identity(r)];assert(row and row.editable,'Saved binding is unavailable in this control scheme');assert(axis(r.original)==axis(r.key),'Incompatible axis type in saved keybinding')end
  -- Mark cleanup ownership before calling native code: even a failed install may
  -- require a retry to restore a partially exchanged vtable entry.
  attached=c;assert(transport().apply(c,rules)~=false,'Native map apply failed');attached=#rules>0 and c or nil
  local after=rows_for(c);local actual={};for _,r in ipairs(after)do if r.id then actual[r.id]=r.key end end
  for _,r in ipairs(rules)do assert(actual[identity(r)]==r.key,'Native remap readback failed')end
  return true
 end
 function api.bindings(device)
  return guarded(function()local c=ensure(ctx.snapshot and ctx.snapshot());local rows=rows_for(c);if not device then return rows end;local out={};for _,r in ipairs(rows)do if r.device==device then out[#out+1]=r end end;return out end)
 end
 function api.available_keys(row)
  local out={};for key in pairs(row.device=='gamepad'and gamepad or keyboard)do
   if key~='F6'and not key:find('Mouse')and axis(key)==axis(row.original)then out[#out+1]=key end
  end;table.sort(out);return out
 end
 local function transaction(id,key,reset,options)
  local c=ensure(ctx.snapshot and ctx.snapshot());local list=rows_for(c);local selected
  for _,r in ipairs(list)do if r.id==id then selected=r;break end end
  assert(selected and selected.editable,selected and selected.reason or'Binding unavailable')
  if not reset then
   assert(allowed(key,selected.device)and key~='F6'and not key:find('Mouse'),'Unsupported or reserved recovery key')
   assert(axis(key)==axis(selected.original),'Choose the same input type (button, stick axis, or trigger axis)')
   if not(options and options.allow_conflict)then for _,r in ipairs(list)do
    if r.device==selected.device and r.id~=id and r.key==key and r.command~=selected.command then error('Key already used by '..r.label..'; explicit conflict confirmation required')end
   end end
  end
  local before=clone(configured(c));local desired={};for _,r in ipairs(before)do if identity(r)~=id then desired[#desired+1]=r end end
  if not reset and key~=selected.original then desired[#desired+1]={device=selected.device,command=selected.command,kind=selected.kind,scale_bits=selected.scale_bits,original=selected.original,key=key}end
  assert(#desired<=192,'Too many input overrides')
  local ok,err=pcall(function()apply(c,desired);local nextConfig=clone(config);nextConfig.profiles[c.profile]=desired;persist(nextConfig);config=nextConfig end)
  if not ok then local restored,why=pcall(apply,c,before);error(tostring(err)..(restored and''or'; rollback failed: '..tostring(why)))end
  return true
 end
 function api.rebind(id,key,options)return guarded(transaction,id,key,false,options)end
 function api.reset_binding(id)return guarded(transaction,id,nil,true)end
 function api.reset_all()
  return guarded(function()local c=ensure(ctx.snapshot and ctx.snapshot());local old=clone(configured(c));local ok,err=pcall(function()apply(c,{});local p=clone(config);p.profiles[c.profile]={};persist(p);config=p end);if not ok then local restored,why=pcall(apply,c,old);error(tostring(err)..(restored and''or'; rollback failed: '..tostring(why)))end;return true end)
 end
 function api.tick(s)
  return guarded(function()
   if not s then return stop()end
   local c=ensure(s);if not attached and #configured(c)>0 then apply(c,configured(c))end;return true
  end)
 end
 function api.status()return{attached=attached~=nil,error=lastError,profile=current and current.profile,overrides=current and #configured(current)or 0,recovery='F6; original controller pause button',scope='Native menu navigation plus gameplay, movement, camera, pause, minigame and photo controls.'}end
 function api.shutdown()return guarded(stop)end
 return api
end
return M
