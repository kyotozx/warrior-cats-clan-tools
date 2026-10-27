local M={}
local dir=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local fileKey=dofile(dir..'character_identity.lua').fileKey
function M.new(ctx)
 local root=ctx.root;local read=ctx.read;local write=ctx.write
 local nativeRead=assert(package.loadlib(root..'bin/clanparty.dll','ClanParty_read'))
 local nativeApply=assert(package.loadlib(root..'bin/clanparty.dll','ClanParty_apply'))
 local tagByIndex={};for _,clan in ipairs(ctx.clans)do local tag='Gameplay.Combat.Character.Cat.'..clan;tagByIndex[FName(tag):GetComparisonIndex()]=tag end
 local function encode(p)local t={tostring(#p)};for _,c in ipairs(p)do t[#t+1]=c.role..' '..c.tag end;return table.concat(t,'\n')..'\n'end
 local function decode(text)local p={};for role,tag in(text or''):gmatch('(%d+) ([%w%.]+)')do p[#p+1]={role=tonumber(role),tag=tag}end;return p end
 local api={error=nil}
 function api.read()
  nativeRead();assert(read(root..'bin/bridge-status.txt')=='READ OK\n','Party reader unavailable')
  local raw=assert(read(root..'bin/snapshot.txt'));local p={}
  for role,index,number in raw:gmatch('(%d+) (%d+) (%d+)')do assert(number=='0','Unsupported companion tag');p[#p+1]={role=tonumber(role),tag=assert(tagByIndex[tonumber(index)],'Unknown clan tag')}end
  assert(#p==tonumber(raw:match('^(%d+)'))and#p<=2,'Invalid party response');return p
 end
 local function apply(p)
  local out={tostring(#p)};for _,c in ipairs(p)do local n=FName(c.tag);assert(n:ToString()==c.tag);out[#out+1]=c.role..' '..n:GetComparisonIndex()..' 0'end
  write(root..'bin/request.txt',table.concat(out,'\n')..'\n');nativeApply()
  assert(read(root..'bin/bridge-status.txt')=='APPLIED OK\n','Party update failed');assert(encode(api.read())==encode(p),'Party readback mismatch')
 end
 local function guard()
  local s=assert(ctx.snapshot(),'Load an offline campaign first.');assert(s.offline and s.phase==4 and not s.combat,'Change companions during offline exploration.');return s
 end
 -- Older readers used the profile index, then the wrong runtime object, for
 -- character identity. Preserve their ambiguous files without replaying them.
 local function key(s)return root..'state/story-v3-'..fileKey(assert(ctx.characterKey(s)))..'_'..s.chapter end
 local function configPath(s)return root..'state/party-v3-'..fileKey(assert(ctx.characterKey(s)))..'.json'end
 local function validateConfig(c)
  assert(type(c)=='table'and type(c.enabled)=='boolean'and type(c.roles)=='table','Invalid party settings')
  local seen,n={},0;for i,r in pairs(c.roles)do assert(type(i)=='number'and i%1==0 and i>=1 and i<=2 and type(r)=='number'and r%1==0 and r>=0 and not seen[r],'Invalid companion selection');seen[r]=true;n=n+1 end
  assert(n==#c.roles and n<=2,'Invalid companion selection');return c
 end
 local function config(s)local r=read(configPath(s));return validateConfig(r and ctx.json.decode(r)or{enabled=false,roles={}})end
 local function roster(s)
  local cats,metadata=ctx.getCats(s);assert(type(cats)=='table'and(not metadata or metadata.valid~=false),metadata and metadata.reason or'Clan roster unavailable')
  local allowed={};for _,cat in ipairs(cats)do allowed[cat.role]=cat end;return allowed
 end
 local function desired(s,roles,strict)
  if #roles==0 then return {}end
  local allowed=roster(s);local result={};local clan=assert(ctx.clans[s.clan],'Clan unavailable')
  for _,role in ipairs(roles)do
   if allowed[role]then
    if ctx.validateCat then local ok,why=ctx.validateCat(allowed[role],s);assert(ok,why or'Clanmate data changed')end
    result[#result+1]={role=role,tag='Gameplay.Combat.Character.Cat.'..clan}
   elseif strict then error('Choose living cats from your current clan.')end
  end
  return result
 end
 local function rememberStory(s,current,target)
  local k=key(s);local last=read(k..'.last.txt')
  if not read(k..'.story.txt')or(current~=last and current~=target)then write(k..'.story.txt',current)end
 end
 function api.state()local s=guard();local c=config(s);c.current=api.read();return c end
 function api.select(roles)
  local s=guard();api.error=nil;validateConfig({enabled=true,roles=roles})
  local p=desired(s,roles,true);local previous=api.read();local oldConfig=read(configPath(s));local oldLast=read(key(s)..'.last.txt')
  ctx.backupSave(s);rememberStory(s,encode(previous),encode(p))
  local ok,err=pcall(function()
   apply(p) -- Persist the selection only after native readback confirms it.
   write(key(s)..'.last.txt',encode(p));write(configPath(s),ctx.json.encode({enabled=true,roles=roles}))
  end)
  if not ok then
   local rollbackOK,rollbackError=pcall(function()apply(previous);write(configPath(s),oldConfig or ctx.json.encode({enabled=false,roles={}}));write(key(s)..'.last.txt',oldLast or'')end)
   api.error=tostring(err)..(rollbackOK and''or'; rollback failed: '..tostring(rollbackError));error(api.error)
  end
  return true
 end
 function api.restore()
  local s=guard();api.error=nil;local k=key(s);local current=encode(api.read());local last=read(k..'.last.txt');local story=read(k..'.story.txt')
  if last and story and current==last then ctx.backupSave(s);apply(decode(story))end
  write(configPath(s),ctx.json.encode({enabled=false,roles={}}));write(k..'.last.txt','');return true
 end
 local lastSession,identityError
 function api.tick()
  local s=ctx.snapshot();if not s or not s.offline or s.phase~=4 or s.combat then return end
  local identityOK,session=pcall(configPath,s)
  if not identityOK then
   -- Identity can be temporarily unavailable while the game changes context.
   -- Do not turn that into a permanent party failure or hide a native failure.
   if not api.error or api.error==identityError then
    local reason=tostring(session);if api.error~=reason then ctx.log(reason)end
    identityError=reason;api.error=reason
   end
   return
  end
  if identityError and api.error==identityError then api.error=nil end;identityError=nil
  local ok,err=pcall(function()
   if lastSession~=session then api.error=nil;lastSession=session end
   if api.error then return end
   local c=config(s);if not c.enabled then return end
   local p=desired(s,c.roles,false)
   local k=key(s);local current=encode(api.read());local text=encode(p)
   rememberStory(s,current,text)
   if current~=text then apply(p)end;if read(k..'.last.txt')~=text then write(k..'.last.txt',text)end
  end)
  if not ok then api.error=tostring(err);ctx.log(api.error)end
 end
 return api
end
return M
