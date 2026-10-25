-- Den timer controls. All state changes use the game's normal completion path.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local labels=dofile(folder..'item_labels.lua')
local json=dofile(folder..'json.lua')
local M={speeds={1,2,5,10,'instant'}}
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local valid=dofile(folder..'runtime_valid.lua').valid
local function address(o)if not valid(o)then return 0 end;local ok,a=pcall(function()return o:GetAddress()end);return ok and a or 0 end
local function fields(s)local t={};for w in s:gmatch('%S+')do t[#t+1]=w end;return t end
local function allowed_speed(v)return v==1 or v==2 or v==5 or v==10 or v=='instant'end
-- UE4SS GetWorld may return a streamed level's outer world. OwningWorld is
-- the actual playing world; this reflected relationship also covers streaming.
function M.level_context(actor)
 local ok,level,world,visible=pcall(function()
  if not valid(actor)then return end
  local l=actor:GetLevel();if not valid(l)then return end
  local w=l.OwningWorld;if not valid(w)then return end
  return l,w,l.bIsVisible==true
 end)
 if ok then return level,world,visible end
end
-- AllHotspots is populated on entry but contains streamed spots from every clan.
-- The active exit door's actual box, pawn containment and clan are all required.
function M.discover(s)
 if not s or s.offline~=true or s.combat or not valid(s.pawn)or not valid(s.world)or type(s.clan)~='number'or s.clan<1 or s.clan>4 then return nil end
 local _,owningWorld=M.level_context(s.pawn);if not valid(owningWorld)then return nil end
 local world=address(owningWorld);local mathLib=StaticFindObject('/Script/Engine.Default__KismetMathLibrary');if not valid(mathLib)then return nil end
 local position=s.pawn:K2_GetActorLocation();local chosen
 for _,door in ipairs(FindAllOf('WrcHousingDoorActor')or{})do
  if valid(door)then
   local ok,result=pcall(function()
    local _,owner,visible=M.level_context(door)
    if not visible or address(owner)~=world or door.Clan~=s.clan or door.bIsExit~=true then return nil end
    local box=door.HotspotsContainerAreaComponent;if not valid(box)then return nil end
    local transform=box:K2_GetComponentToWorld();local extent=box:GetUnscaledBoxExtent()
    if not finite(extent.X)or not finite(extent.Y)or not finite(extent.Z)or extent.X<=0 or extent.Y<=0 or extent.Z<=0 then return nil end
    if mathLib:IsPointInBoxWithTransform(position,transform,extent)~=true then return nil end
    local list,seen={},{}
    local function collect(o)
     if not valid(o)then return end
     local _,hotspotWorld,hotspotVisible=M.level_context(o);local id=address(o)
     if not hotspotVisible or address(hotspotWorld)~=world or seen[id]then return end
     local tag=o.UniqueHotspotTag.TagName:ToString()
     if tag==''or tag=='None'or mathLib:IsPointInBoxWithTransform(o:K2_GetActorLocation(),transform,extent)~=true then return end
     seen[id]=true;list[#list+1]=o
    end
    door.AllHotspots:ForEach(function(_,entry)collect(entry:get())end)
    -- Teleporting into a loaded den does not populate the door's cached list.
    -- The same world/visibility/clan-volume checks still identify its hotspots.
    if #list==0 then
     local candidates=FindAllOf('WrcHousingHotspot')or{}
     if #candidates>4096 then return nil end
     for _,o in ipairs(candidates)do collect(o)end
    end
    if #list==0 then return nil end
    table.sort(list,function(a,b)return address(a)<address(b)end)
    return {actors=list,session=table.concat({tostring(s.profile),tostring(s.slot),tostring(s.worldId),tostring(world),tostring(address(door))},':')}
   end)
   if ok and result then if chosen then return nil end;chosen=result end
  end
 end
 return chosen
end
function M.parse(data)
 if type(data)~='string'or #data>131072 then return nil,'Invalid project mailbox'end
 local lines={};for line in data:gmatch('[^\r\n]+')do lines[#lines+1]=line end
 local h=fields(lines[1]or'');local epoch=tonumber(h[3]);if #h~=3 or h[1]~='CRAFTING'or h[2]~='1'or not epoch or epoch<1 or epoch%1~=0 then return nil,'Invalid project header'end
 local rows={};local seen={}
 for i=2,#lines do
  local r=fields(lines[i]);if #r~=7 or r[1]~='P'or not r[2]:match('^%x+$')or #r[2]>16 then return nil,'Invalid project record'end
  local row={actor=r[2]:lower(),state=tonumber(r[3]),duration=tonumber(r[4]),elapsed=tonumber(r[5]),tag_index=tonumber(r[6]),tag_number=tonumber(r[7])}
  for _,k in ipairs({'state','duration','elapsed','tag_index','tag_number'})do if not finite(row[k])or row[k]<0 then return nil,'Invalid project values'end end
  for _,k in ipairs({'state','duration','tag_index','tag_number'})do if row[k]%1~=0 then return nil,'Invalid project integer'end end
  if row.state>3 or row.duration>31536000 or seen[row.actor]or #rows>=256 then return nil,'Invalid project bounds'end
  seen[row.actor]=true;rows[#rows+1]=row
 end
 return rows,nil,epoch
end
function M.remaining(row,speed)
 local factor=speed=='instant'and 0 or speed
 if factor~=0 and factor~=1 and factor~=2 and factor~=5 and factor~=10 then return nil end
 if row.state~=1 then return 0 end
 return math.max(0,(factor==0 and 0 or math.ceil(row.duration/factor))-row.elapsed)
end
function M.new(ctx)
 assert(type(ctx)=='table','Crafting requires context')
 local api={};local root=ctx.mod_root or ctx.root or folder..'../';if not root:match('[/\\]$')then root=root..'/'end
 local bin=root..'bin/';local native=ctx.crafting_native;local epoch=0;local key;local attached=false;local stopped=false;local speed=1;local projects={};local error;local tick=0;local live;local labels_by_index={}
 local lastLogged;local retryAfter=0
 local function log(s)if ctx.log and s~=lastLogged then ctx.log('[Crafting] '..s);lastLogged=s end end
 local function read(name)local f=io.open(bin..name,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
 local function write(name,s)local f=assert(io.open(bin..name,'wb'));assert(f:write(s));assert(f:close())end
 local preferencePath=root..'crafting-settings.json'
 local function read_preference()
  if ctx.load_crafting_preferences then return ctx.load_crafting_preferences()end
  local f=io.open(preferencePath,'rb');if not f then return nil end;local data=f:read('*a');f:close();return json.decode(data)
 end
 local function persist(value)
  local data={version=1,speed=value}
  if ctx.save_crafting_preferences then return assert(ctx.save_crafting_preferences(data)~=false,'Could not save crafting speed')end
  local backup=preferencePath..'.previous';local tmp=preferencePath..'.tmp'
  local f=io.open(backup,'rb');if f then f:close();assert(false,'Unfinished crafting preference backup requires recovery')end
  f=assert(io.open(tmp,'wb'));assert(f:write(json.encode(data)));assert(f:close())
  f=io.open(preferencePath,'rb');local existed=f~=nil;if f then f:close();assert(os.rename(preferencePath,backup))end
  local ok,why=os.rename(tmp,preferencePath);if not ok then if existed then assert(os.rename(backup,preferencePath))end;assert(false,why)end
  if existed then local removed,why=os.remove(backup);if not removed then log('Saved speed, but could not remove old preference backup: '..tostring(why))end end;return true
 end
 do local ok,pref=pcall(read_preference);if ok and pref~=nil then
  if type(pref)=='table'and pref.version==1 and allowed_speed(pref.speed)then speed=pref.speed else error='Invalid saved crafting speed; using 1x';log(error)end
 elseif not ok then error='Could not read crafting settings: '..tostring(pref);log(error)end end
 local function load()
  if native then return end
  local library=ctx.crafting_dll or'crafting-v4.dll'
  local configure=assert(package.loadlib(bin..library,'Crafting_configure'))
  local scan=assert(package.loadlib(bin..library,'Crafting_scan'));local complete=assert(package.loadlib(bin..library,'Crafting_complete'));local remove=assert(package.loadlib(bin..library,'Crafting_remove'))
  native={configure=function(s)write('crafting-watch.txt',s);configure();return read('crafting-status.txt')end,
   scan=function()scan();return read('crafting-projects.txt')end,
   complete=function(s)write('crafting-complete.txt',s);complete();return read('crafting-status.txt')end,
   remove=function()remove();return read('crafting-status.txt')end}
 end
 local function discover(s)
  if ctx.crafting_context then return ctx.crafting_context(s)end
  return M.discover(s)
 end
 function api.reset()
  if attached then local ok,r=pcall(native.remove);if not ok or type(r)~='string'or not r:match('^REMOVED')then error='Could not restore crafting adapter';return false end end
  attached=false;key=nil;live=nil;projects={};return true
 end
 local function refresh(s)
  local c=discover(s);if not c or #(c.actors or{})==0 then assert(api.reset());return false end
  assert(#c.actors<=256,'Too many den hotspots')
  local parts={c.session or''};for _,o in ipairs(c.actors)do local a=address(o);assert(a~=0,'Stale den hotspot');parts[#parts+1]=string.format('%x',a)end
  local next_key=table.concat(parts,':')..':'..tostring(speed)
  if next_key~=key then
   assert(api.reset(),'Could not clear previous den');load();epoch=epoch+1
   local lines={string.format('1 %d %d %d',epoch,speed=='instant'and 0 or speed,#c.actors)}
   for _,o in ipairs(c.actors)do lines[#lines+1]=string.format('%x',address(o))end
   attached=true -- A partially failed native install still owns cleanup.
   local result=native.configure(table.concat(lines,'\n')..'\n');if type(result)~='string'or not result:match('^CONFIGURED')then api.reset();assert(false,tostring(result))end
   attached=true;key=next_key;live=c;error=nil
   if FName then for tag,label in pairs(labels)do if tag:find('Gameplay.Inventory.Decoration.',1,true)==1 then local name=FName(tag);if name:ToString()==tag then labels_by_index[name:GetComparisonIndex()]=label end end end end
  end
  return true
 end
 local function scan()
  local rows,why,e=M.parse(native.scan());assert(rows,why);assert(e==epoch,'Stale den observations');projects=rows
  for i,row in ipairs(projects)do local label=row.tag_number==0 and labels_by_index[row.tag_index];row.name=ctx.decoration_name and ctx.decoration_name(row.tag_index,row.tag_number)or(label and label.name);row.icon=label and label.icon;row.name=row.name or('Den project '..i);row.remaining=M.remaining(row,speed)end
 end
 function api.tick(s)
  if stopped or os.time()<retryAfter then return end
  local ok,why=pcall(function()
   s=s or(ctx.snapshot and ctx.snapshot());tick=tick+1
   -- World and offline conditions are checked before any native scan.
   if not refresh(s)then return end
   if tick%5==1 then scan()end
  end)
  if not ok then error=tostring(why);log(error);api.reset();retryAfter=os.time()+2 elseif attached then retryAfter=0;lastLogged=nil end
 end
 function api.set_speed(value)
  if not allowed_speed(value)then return false,'Choose 1x, 2x, 5x, 10x or Instant'end
  if stopped then return false,'Crafting module is stopped'end
  local old=speed;local snapshot=ctx.snapshot and ctx.snapshot();speed=value
  local ok,why=pcall(function()refresh(snapshot);if attached then scan()end;persist(value)end)
  if not ok then
   speed=old;local restored,restoreError=pcall(refresh,snapshot)
   error=tostring(why)..(restored and''or'; rollback failed: '..tostring(restoreError));return false,error
  end
  error=nil;return true
 end
 function api.complete_now(actor)
  if stopped then return false,'Crafting module is stopped'end
  local ok,why=pcall(function()
   assert(refresh(ctx.snapshot and ctx.snapshot()),'Enter your den first');scan()
   local selected;for _,row in ipairs(projects)do if row.actor==actor then selected=row;break end end
   assert(selected and selected.state==1,'This project is no longer building')
   local r=native.complete(string.format('%d %s\n',epoch,actor));assert(type(r)=='string'and r:match('^COMPLETED'),tostring(r));scan()
   if ctx.notify then ctx.notify({kind='crafting_complete',title='Den project complete',lines={selected.name..' is ready.'},original_sound=true})end
  end)
  if not ok then error=tostring(why);return false,error end
  error=nil;return true
 end
 function api.status()
  local active={};for _,row in ipairs(projects)do if row.state==1 or row.state==2 then active[#active+1]=row end end
  return {speed=speed,attached=attached,projects=active,hotspot_count=#projects,error=error,epoch=epoch,scope='Applies to projects in your current den while you are inside.'}
 end
 function api.shutdown()local ok=api.reset();if ok then stopped=true end;return ok end
 return api
end
return M
