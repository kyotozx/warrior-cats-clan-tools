-- Profile-scoped display names. Narrative role and native name IDs stay intact.
local M={}
function M.validate(value)
 if type(value)~='string'then return nil,'Enter a name.'end
 value=value:gsub('^%s+',''):gsub('%s+$','')
 local count=utf8.len(value)
 if not count or count<1 or count>40 then return nil,'Use 1 to 40 characters.'end
 if value:find('[%z\1-\31\127]')or value:find('[<>]')then return nil,'Names cannot contain control characters or markup.'end
 return value
end
function M.new(ctx)
 local api={};local cache={}
 local function identity(s)
  assert(s and s.offline==true and type(s.profile)=='string'and s.profile:match('^[%w_-]+$'),'Load an offline campaign.')
  assert(type(s.slot)=='number'and s.slot%1==0 and s.slot>=0,'Invalid save slot.')
  return s.profile..'_'..s.slot
 end
 local function path(id)return ctx.root..'state/cat-names-'..id..'.json'end
 local function load(s)
  local id=identity(s);if cache[id]then return cache[id],id end
  local raw=ctx.read(path(id));local data=raw and ctx.json.decode(raw)or{version=1,names={}}
  assert(type(data)=='table'and data.version==1 and type(data.names)=='table','Invalid saved cat names.')
  for role,value in pairs(data.names)do
   assert(type(role)=='string'and role:match('^%d+$')and tonumber(role)>0 and tonumber(role)<255 and M.validate(value)==value,'Invalid saved cat name.')
  end
  cache[id]=data;return data,id
 end
 function api.get(s,role,fallback)
  local data=load(s);return data.names[tostring(role)]or fallback
 end
 function api.hasOverrides(s)
  return next(load(s).names)~=nil
 end
 function api.prepare(s,cat,value)
  local clean,why=M.validate(value);assert(clean,why)
  assert(cat and cat.living==true and cat.clan==s.clan and type(cat.role)=='number'and cat.role%1==0 and cat.role>0 and cat.role<255,'Choose a living clanmate.')
  if ctx.validateCat then local good,reason=ctx.validateCat(cat,s);assert(good,reason)end
  local data,id=load(s);local before=data.names[tostring(cat.role)]
  return{profile=s.profile,slot=s.slot,clan=s.clan,id=id,role=cat.role,name=clean,before=before,committed=false}
 end
 function api.commit(receipt)
  local s=ctx.snapshot();assert(identity(s)==receipt.id and s.clan==receipt.clan,'The active profile changed.')
  assert(not receipt.committed,'Name was already saved.')
  if ctx.validateCat then local good,why=ctx.validateCat({role=receipt.role,clan=s.clan,living=true},s);assert(good,why)end
  local data,id=load(s);assert(data.names[tostring(receipt.role)]==receipt.before,'Name changed while editing.')
  local names={};for k,v in pairs(data.names)do names[k]=v end;names[tostring(receipt.role)]=assert(M.validate(receipt.name))
  local serialized=ctx.json.encode({version=1,names=names});local target=path(id)
  local previous=ctx.read(target)or ctx.json.encode({version=1,names=data.names})
  ctx.write(target..'.previous.txt',previous)
  assert(ctx.read(target..'.previous.txt')==previous,'Previous names could not be backed up.')
  local good,why=pcall(function()ctx.write(target,serialized);assert(ctx.read(target)==serialized,'Name save could not be verified.')end)
  if not good then
   local restored=pcall(function()ctx.write(target,previous);assert(ctx.read(target)==previous,'Name rollback failed.')end)
   if not restored then cache[id]=nil;error('Name save failed and rollback could not be confirmed. Previous names are preserved in the backup.')end
   error(why)
  end
  cache[id]={version=1,names=names};receipt.committed=true;return true
 end
 function api.generate(cat,current)
  local suffix=cat.rank=='Kit'and'_KIT'or cat.rank=='Apprentice'and'_PAW'or cat.rank=='Leader'and'_STAR'
  local options,seen={},{}
  for key,value in pairs(ctx.catalog.Names)do
   local eligible=key:match('^STR_CAT_NAME%d+_')and(suffix and key:sub(-#suffix)==suffix or not suffix and not key:match('_KIT$')and not key:match('_PAW$')and not key:match('_STAR$'))
   if eligible and M.validate(value)and value~=current and not seen[value]then options[#options+1]=value;seen[value]=true end
  end
  assert(#options>0,'No generated names are available for this rank.')
  table.sort(options);return options[math.random(#options)]
 end
 function api.invalidate()cache={}end
 return api
end
return M
