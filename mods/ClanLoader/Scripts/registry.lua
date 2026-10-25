local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua');local M={}
function M.validId(id)return type(id)=='string'and id:match('^[A-Za-z][A-Za-z0-9_]*$')and #id<=64 end
function M.states(text)
 local result={};for line in (text..'\n'):gmatch('(.-)\r?\n')do local id,n=line:match('^%s*([%w_]+)%s*:%s*([01])%s*$');if id then assert(result[id]==nil,'Duplicate mod entry: '..id);result[id]=n=='1'end end
 return result
end
function M.update(text,id,enabled)
 assert(M.validId(id),'Invalid mod ID.');local rows={};local nl=text:find('\r\n',1,true)and'\r\n'or'\n'
 for line in (text..'\n'):gmatch('(.-)\r?\n')do if not line:match('^%s*'..id..'%s*:')then rows[#rows+1]=line end end
 while rows[#rows]==''do table.remove(rows)end;rows[#rows+1]=id..' : '..(enabled and'1'or'0');return table.concat(rows,nl)..nl
end
function M.new(ctx)
 local api={};local listPath=ctx.root..'../mods.txt';local startup=M.states(assert(ctx.read(listPath),'Mod list unavailable.'))
 local function registry()
  local raw=assert(ctx.read(ctx.root..'registry.json'),'Run the external manager to register your installed mods.')
  local r=json.decode(raw);assert(r.schema==1 and type(r.mods)=='table','Invalid mod registry.');return r
 end
 function api.list()
  local r=registry();local states=M.states(assert(ctx.read(listPath)));local rows={};local seen={}
  for _,m in ipairs(r.mods)do
   assert(M.validId(m.id)and not seen[m.id]and type(m.name)=='string'and type(m.version)=='string','Invalid registered mod.');seen[m.id]=true
   rows[#rows+1]={id=m.id,name=m.name,version=m.version,description=m.description or'',enabled=states[m.id]==true,atStartup=startup[m.id]==true,restart=(states[m.id]==true)~=(startup[m.id]==true),dependencies=m.dependencies or{}}
  end
  return rows
 end
 function api.toggle(id)
  assert(id~='ClanLoader','The manager must stay enabled. Use the external manager to remove it.')
  local rows=api.list();local entry;local byId={};for _,m in ipairs(rows)do byId[m.id]=m;if m.id==id then entry=m end end
  assert(entry,'Unknown mod.')
  if not entry.enabled then for _,dep in ipairs(entry.dependencies)do assert(byId[dep]and byId[dep].enabled,'Enable the required mod first: '..tostring(dep))end
  else for _,m in ipairs(rows)do if m.enabled then for _,dep in ipairs(m.dependencies)do assert(dep~=id,'Disable '..m.name..' first.')end end end end
  local old=assert(ctx.read(listPath));local new=M.update(old,id,not entry.enabled);ctx.write(listPath..'.clanloader-backup',old)
  local ok,err=pcall(function()ctx.write(listPath,new);assert(ctx.read(listPath)==new,'Mod list readback failed.')end)
  if not ok then pcall(ctx.write,listPath,old);error(err)end;return true
 end
 return api
end
return M
