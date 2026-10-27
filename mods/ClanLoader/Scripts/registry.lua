local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua');local M={}
function M.validId(id)return type(id)=='string'and id:match('^[A-Za-z][A-Za-z0-9_]*$')and #id<=64 end
function M.states(text)
 local result,seen={},{};for line in (text..'\n'):gmatch('(.-)\r?\n')do local id,n=line:match('^%s*([%w_]+)%s*:%s*([01])%s*$');if id then assert(not seen[id:lower()],'Duplicate mod entry: '..id);seen[id:lower()]=true;result[id]=n=='1'end end
 return result
end
function M.update(text,id,enabled)
 assert(M.validId(id),'Invalid mod ID.');local rows={};local nl=text:find('\r\n',1,true)and'\r\n'or'\n'
 for line in (text..'\n'):gmatch('(.-)\r?\n')do local found=line:match('^%s*([%w_]+)%s*:');if not found or found:lower()~=id:lower()then rows[#rows+1]=line end end
 while rows[#rows]==''do table.remove(rows)end;rows[#rows+1]=id..' : '..(enabled and'1'or'0');return table.concat(rows,nl)..nl
end
function M.new(ctx)
 local api={};local listPath=ctx.root..'../mods.txt';local startupStates=M.states(assert(ctx.read(listPath),'Mod list unavailable.'));local startup={}
 local function registry()
  local raw=assert(ctx.read(ctx.root..'registry.json'),'Run the external manager to register your installed mods.')
  local r=json.decode(raw);assert(r.schema==1 and type(r.mods)=='table','Invalid mod registry.');return r
 end
 local function marker(id)return ctx.root..'../'..id..'/enabled.txt'end
 -- UE4SS resolves mods.txt names case-sensitively, even on Windows. Only
 -- writes normalize an old spelling; displaying it as active would hide a
 -- mod that the runtime never started.
 local function enabled(states,id)return states[id]==true or ctx.read(marker(id))~=nil end
 -- Capture marker activation now, before any toggles change files for next launch.
 for _,m in ipairs(registry().mods)do assert(M.validId(m.id),'Invalid registered mod.');startup[m.id:lower()]=enabled(startupStates,m.id)end
 function api.list()
  local r=registry();local states=M.states(assert(ctx.read(listPath)));local rows={};local seen={}
  for _,m in ipairs(r.mods)do
   assert(M.validId(m.id)and not seen[m.id:lower()]and type(m.name)=='string'and type(m.version)=='string','Invalid registered mod.');seen[m.id:lower()]=true
   local active=enabled(states,m.id);local wasActive=startup[m.id:lower()]==true
   rows[#rows+1]={id=m.id,name=m.name,version=m.version,description=m.description or'',enabled=active,atStartup=wasActive,restart=active~=wasActive,dependencies=m.dependencies or{}}
  end
  return rows
 end
 function api.toggle(id)
  assert(M.validId(id),'Invalid mod ID.');assert(id:lower()~='clanloader','The manager must stay enabled. Use the external manager to remove it.')
  local rows=api.list();local entry;local byId={};for _,m in ipairs(rows)do byId[m.id:lower()]=m;if m.id==id then entry=m end end
  assert(entry,'Unknown mod.')
  if not entry.enabled then for _,dep in ipairs(entry.dependencies)do assert(byId[dep:lower()]and byId[dep:lower()].enabled,'Enable the required mod first: '..tostring(dep))end
  else for _,m in ipairs(rows)do if m.enabled then for _,dep in ipairs(m.dependencies)do assert(dep:lower()~=id:lower(),'Disable '..m.name..' first.')end end end end
  local old=assert(ctx.read(listPath));local new=M.update(old,id,not entry.enabled);ctx.write(listPath..'.clanloader-backup',old)
  local markerPath=marker(id);local oldMarker=ctx.read(markerPath)
  if oldMarker~=nil then ctx.write(markerPath..'.clanloader-backup',oldMarker)end
  local ok,err=pcall(function()
   ctx.write(listPath,new);assert(ctx.read(listPath)==new,'Mod list readback failed.')
   if oldMarker~=nil then ctx.remove(markerPath);assert(ctx.read(markerPath)==nil,'Enable marker removal failed.')end
  end)
  if not ok then
   local restored,restoreErr=pcall(function()
    ctx.write(listPath,old);assert(ctx.read(listPath)==old,'Mod list restore failed.')
    if oldMarker~=nil then ctx.write(markerPath,oldMarker);assert(ctx.read(markerPath)==oldMarker,'Enable marker restore failed.')end
   end)
   if not restored then error(tostring(err)..' Rollback failed: '..tostring(restoreErr)..'. Restore the .clanloader-backup files.')end
   error(err)
  end;return true
 end
 return api
end
return M
