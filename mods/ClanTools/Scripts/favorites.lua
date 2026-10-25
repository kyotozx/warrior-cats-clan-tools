-- Only registered actions can be persisted; files never contain executable code.
local M={}
function M.new(ctx,registry)
 local path=ctx.root..'state/favorites.json';local ids={};local api={}
 local raw=ctx.read(path)
 if raw then
  local ok,data=pcall(ctx.json.decode,raw)
  if ok and type(data)=='table'and data.version==1 and type(data.actions)=='table'then
   local seen={};for _,id in ipairs(data.actions)do if type(id)=='string'and registry[id]and not seen[id]and #ids<12 then ids[#ids+1]=id;seen[id]=true end end
  end
 end
 function api.has(id)for _,v in ipairs(ids)do if v==id then return true end end;return false end
 function api.toggle(id)
  assert(registry[id],'Unknown favorite action.')
  local out={};for _,v in ipairs(ids)do if v~=id then out[#out+1]=v end end
  if #out==#ids then assert(#out<12,'Keep up to twelve favorite actions.');out[#out+1]=id end
  local serialized=ctx.json.encode({version=1,actions=out});ctx.write(path,serialized)
  assert(ctx.read(path)==serialized,'Favorites could not be saved.');ids=out;return true
 end
 function api.list(all)
  local out={}
  if all then for id,entry in pairs(registry)do out[#out+1]={id=id,label=entry.label,selected=api.has(id)}end;table.sort(out,function(a,b)return a.label<b.label end)
  else for _,id in ipairs(ids)do out[#out+1]={id=id,label=registry[id].label,selected=true}end end
  return out
 end
 function api.run(id)
  local entry=assert(registry[id],'Unknown favorite action.')
  if entry.available then local ok,why=entry.available();assert(ok,why or'This action is unavailable here.')end
  return entry.run()
 end
 return api
end
return M
