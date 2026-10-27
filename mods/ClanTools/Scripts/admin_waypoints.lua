-- User-created travel bookmarks, separate from temporary admin state and saves.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua');local M={}
local function copy(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table'and copy(v)or v end;return out end
local function validPosition(p)
 if type(p)~='table'then return false end
 for _,k in ipairs({'X','Y','Z'})do local v=p[k];if type(v)~='number'or v~=v or math.abs(v)>1000000 then return false end end;return true
end
local function validName(n)return type(n)=='string'and #n>=1 and #n<=32 and n:match('^[%w _%-]+$')~=nil end
local function read(path)local f=io.open(path,'rb');if not f then return nil end;local raw=f:read(1048577);f:close();assert(#raw<=1048576,'Waypoint storage is too large.');return raw end
local function write(path,raw)local f=assert(io.open(path,'wb'));assert(f:write(raw));assert(f:close())end
function M.new(ctx)
 ctx=ctx or{};local root=ctx.root or ctx.mod_root or dir..'../';if not root:match('[/\\]$')then root=root..'/'end
 local path=root..'admin-waypoints.json';local state
 local function load()
  if state then return end
  local raw=ctx.waypoint_read and ctx.waypoint_read()or(not ctx.waypoint_read and read(path))
  if not raw then state={version=1,profiles={}};return end
  assert(type(raw)=='string'and #raw<=1048576,'Invalid waypoint storage.')
  local value=json.decode(raw);assert(type(value)=='table'and value.version==1 and type(value.profiles)=='table','Invalid waypoint storage format.')
  for profile,slots in pairs(value.profiles)do
   assert(type(profile)=='string'and type(slots)=='table','Invalid waypoint profile.')
   for slot,worlds in pairs(slots)do
    assert(type(slot)=='string'and slot:match('^%d+$')and type(worlds)=='table','Invalid waypoint save slot.')
    for world,points in pairs(worlds)do
     assert(type(world)=='string'and type(points)=='table','Invalid waypoint world.');local count=0
     for name,p in pairs(points)do count=count+1;assert(validName(name)and validPosition(p),'Invalid saved waypoint.')end
     assert(count<=20,'Too many saved waypoints.')
    end
   end
  end
  state=value
 end
 local function scope(s)
  assert(s and type(s.profile)=='string'and #s.profile>0 and type(s.slot)=='number'and s.slot>=0 and s.slot%1==0 and type(s.worldId)=='string'and #s.worldId>0,'Waypoint profile, slot and world are unavailable.')
  -- Keep old profile/slot entries untouched. A recycled slot must not acquire
  -- another character's travel bookmarks.
  local identity=assert(ctx.characterKey(s));load();return 'v2_'..identity,tostring(s.slot),s.worldId
 end
 local function persist(nextState)
  local raw=json.encode(nextState)
  if ctx.waypoint_write then assert(ctx.waypoint_write(raw)~=false,'Could not save waypoints.')
  else
   local tmp,old=path..'.tmp',path..'.previous';assert(not read(old),'Waypoint recovery file exists; preserve it before editing.')
   local before=read(path);write(tmp,raw)
   if before then assert(os.rename(path,old),'Cannot back up waypoint storage.')end
   local ok,why=os.rename(tmp,path)
   if not ok then if before then assert(os.rename(old,path),'Waypoint rollback failed.')end;error(why or'Could not commit waypoints.')end
   if before then assert(os.remove(old),'Cannot remove completed waypoint backup.')end
  end
  state=nextState
 end
 local api={}
 function api.list(s)
  local profile,slot,world=scope(s);local p=state.profiles[profile];p=p and p[slot];p=p and p[world];return copy(p or{})
 end
 function api.save(s,name,position)
  assert(validName(name),'Waypoint names need 1 to 32 letters, numbers, spaces, dashes or underscores.')
  assert(validPosition(position),'Invalid waypoint position.');local profile,slot,world=scope(s)
  local nextState=copy(state);nextState.profiles[profile]=nextState.profiles[profile]or{}
  local slots=nextState.profiles[profile];slots[slot]=slots[slot]or{};slots[slot][world]=slots[slot][world]or{}
  local points=slots[slot][world];local n=0;for _ in pairs(points)do n=n+1 end
  assert(points[name]or n<20,'At most 20 waypoints can be stored per world and save slot.')
  points[name]=copy(position);persist(nextState);return true
 end
 function api.delete(s,name)
  assert(validName(name),'Invalid waypoint name.');local profile,slot,world=scope(s)
  local points=api.list(s);assert(points[name],'Waypoint not found.')
  local nextState=copy(state);nextState.profiles[profile][slot][world][name]=nil;persist(nextState);return true
 end
 return api
end
return M
