-- Data-only, cross-save cosmetic library. No identity or progression fields.
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(dir..'json.lua')
local validate=dofile(dir..'appearance_library.lua').values
local M={limit=128,build='26184573'}
local compatibleBuilds={['24847281']=true,['26184573']=true}
local function copy(v)return json.decode(json.encode(v))end
function M.label(s)
 if type(s)~='string' or not utf8.len(s)then return nil,'Enter a valid skin name.'end
 s=s:gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$','')
 if s==''or utf8.len(s)>40 then return nil,'Use 1 to 40 characters.'end
 return s
end
function M.new(ctx)
 local api={};local path=ctx.root..'skins.json';local data={schema=1,nextId=1,skins={}};local loadError
 local raw=ctx.read(path)
 if raw then
  local ok,v=pcall(json.decode,raw);local ids={}
  if ok and type(v)=='table'and v.schema==1 and type(v.skins)=='table'and #v.skins<=M.limit and type(v.nextId)=='number'and v.nextId%1==0 and v.nextId>=1 then
   for _,e in ipairs(v.skins)do
    if type(e)~='table'or type(e.id)~='number'or e.id%1~=0 or e.id<1 or e.id>=v.nextId or ids[e.id]or not M.label(e.label)or not validate(e.values)or type(e.favorite)~='boolean'then loadError='Skin library is invalid; original file was preserved.';break end
    ids[e.id]=true
   end
   if not loadError then data=v end
  else loadError='Skin library could not be read; original file was preserved.'end
 end
 local function commit(nextData)
  assert(not loadError,loadError);local old=ctx.read(path);local encoded=json.encode(nextData)
  if old then ctx.write(path..'.previous.txt',old)end
  local ok,err=pcall(function()ctx.write(path,encoded);assert(ctx.read(path)==encoded,'Skin library readback failed.')end)
  if not ok then if old then pcall(ctx.write,path,old)end;error(err)end
  data=nextData;return true
 end
 local function mutate(id,fn)
  local d=copy(data);for i,e in ipairs(d.skins)do if e.id==id then fn(e,d,i);return commit(d)end end
  error('Select a saved skin.')
 end
 function api.list()return copy(data.skins),loadError end
 function api.get(id)for _,e in ipairs(data.skins)do if e.id==id then return copy(e)end end end
 function api.save(label,values)
  label=assert(M.label(label));values=assert(validate(values),'Invalid skin values.');assert(#data.skins<M.limit,'Your skin library is full (128).')
  local d=copy(data);local id=d.nextId;d.nextId=id+1;d.skins[#d.skins+1]={id=id,label=label,values=values,favorite=false};commit(d);return id
 end
 function api.rename(id,label)label=assert(M.label(label));return mutate(id,function(e)e.label=label end)end
 function api.favorite(id)return mutate(id,function(e)e.favorite=not e.favorite end)end
 function api.delete(id)return mutate(id,function(_,d,i)table.remove(d.skins,i)end)end
 function api.export(id)
  local e=assert(api.get(id),'Select a skin.');local file=ctx.root..'skin-export.json'
  ctx.write(file,json.encode({format='ClanTools.Skin',schema=1,gameBuild=M.build,label=e.label,values=e.values}));return file
 end
 function api.import()
  local raw=assert(ctx.read(ctx.root..'skin-import.json'),'Place a skin in skin-import.json, or use the external manager to import it.')
  assert(#raw<=8192,'Skin import is too large.');local v=json.decode(raw)
  assert(type(v)=='table'and v.format=='ClanTools.Skin'and v.schema==1 and compatibleBuilds[v.gameBuild],'This skin is not compatible with this game build.')
  for k in pairs(v)do assert(k=='format'or k=='schema'or k=='gameBuild'or k=='label'or k=='values','Unexpected skin data.')end
  return api.save(v.label,v.values)
 end
 return api
end
function M.merge(current,skin,part)
 current=assert(validate(current));skin=assert(validate(skin));if part=='All'then return skin end
 local a,b={},{};for n in current:gmatch('%d+')do a[#a+1]=n end;for n in skin:gmatch('%d+')do b[#b+1]=n end
 local ranges={Shape={1,15},Coat={16,20},Eyes={21,22}};local r=assert(ranges[part],'Invalid skin section.')
 for i=r[1],r[2]do a[i]=b[i]end
 if part=='Coat'then a[23]=b[23];a[24]=b[24]end
 return table.concat(a,' ')
end
return M
