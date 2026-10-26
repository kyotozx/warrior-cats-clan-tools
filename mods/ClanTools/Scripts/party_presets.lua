-- Presets contain narrative-role IDs, never actor pointers or save data. Loading
-- delegates to party.select's existing backup, validation and rollback path.
local M={}
local function copy(a)local b={};for i,v in ipairs(a)do b[i]=v end;return b end
local function roles(value)
 assert(type(value)=='table'and #value<=2,'A party preset can contain up to two companions.')
 local out,seen={},{}
 for i,r in pairs(value)do assert(type(i)=='number'and i%1==0 and i>=1 and i<=#value and type(r)=='number'and r%1==0 and r>0 and r<255 and not seen[r],'Invalid party preset roles.');seen[r]=true;out[i]=r end
 return out
end
local function name(value)
 assert(type(value)=='string','Enter a preset name.')
 value=value:match('^%s*(.-)%s*$')
 local length=utf8.len(value)
 assert(length and length>=1 and length<=40 and not value:find('[%z\1-\31\127]'),'Use a name of 1–40 characters without control characters.')
 return value
end
function M.new(ctx,party)
 party=party or ctx.party
 assert(ctx.snapshot and ctx.getCats and ctx.read and ctx.write and ctx.json and party,'Party preset context is required.')
 local function session()
  local s=assert(ctx.snapshot(),'Load an offline campaign first.')
  assert(s.offline==true and s.phase==4 and not s.combat,'Manage party presets during offline exploration.')
  assert(type(s.profile)=='string'and s.profile:match('^[%w_%-]+$')and #s.profile<=128,'Invalid profile identity.')
  assert(type(s.clan)=='number'and s.clan>=1 and s.clan<=4,'Active clan unavailable.')
  assert(type(s.slot)=='number'and s.slot%1==0 and s.slot>=0,'Active character unavailable.')
  return s
 end
 local function path(s)return ctx.root..'state/party-presets-character-'..s.profile..'_'..s.slot..'.json'end
 local function read(s)
  local raw=ctx.read(path(s));if not raw then return{version=1,nextId=1,entries={}}end
  local data=ctx.json.decode(raw)
  assert(type(data)=='table'and data.version==1 and type(data.nextId)=='number'and data.nextId%1==0 and data.nextId>0 and data.nextId<1000000 and type(data.entries)=='table'and #data.entries<=12,'Invalid party preset file.')
  local seen={}
  for i,e in pairs(data.entries)do
   assert(type(i)=='number'and i%1==0 and i>=1 and i<=#data.entries and type(e)=='table'and type(e.id)=='number'and e.id%1==0 and e.id>0 and e.id<data.nextId and not seen[e.id],'Invalid party preset identity.')
   seen[e.id]=true;name(e.name);roles(e.roles);assert(type(e.clan)=='number'and e.clan%1==0 and e.clan>=1 and e.clan<=4,'Invalid preset clan.')
  end
  return data
 end
 local function eligible(s,selected)
  local cats,meta=ctx.getCats();assert(type(cats)=='table'and meta and meta.valid==true and meta.profile==s.profile and meta.slot==s.slot,'Clan roster belongs to another session.')
  local available={};for _,c in ipairs(cats)do if c.living==true and c.clan==s.clan then available[c.role]=c end end
  for _,r in ipairs(selected)do
   local cat=assert(available[r],'A saved companion is unavailable in your current clan. Edit or replace this preset.')
   if ctx.validateCat then local ok,why=ctx.validateCat(cat,s);assert(ok,why or'Companion identity changed.')end
  end
 end
 local api={}
 function api.list()
  local s=session();local data=read(s);local out={}
  for _,e in ipairs(data.entries)do if e.clan==s.clan then out[#out+1]={id=e.id,name=e.name,clan=e.clan,roles=copy(e.roles)}end end
  return out
 end
 function api.save(label,selected)
  local ok,result=pcall(function()
   local s=session();label=name(label);local data=read(s)
   if selected==nil then selected={};for _,e in ipairs(party.read())do selected[#selected+1]=e.role end end
   selected=roles(selected);eligible(s,selected)
   local entry
   for _,e in ipairs(data.entries)do if e.name==label and e.clan==s.clan then entry=e;break end end
   if not entry then assert(#data.entries<12,'You can save up to 12 party presets per character.');entry={id=data.nextId,name=label,clan=s.clan};data.nextId=data.nextId+1;data.entries[#data.entries+1]=entry end
   entry.roles=copy(selected);ctx.write(path(s),ctx.json.encode(data));return'Party preset saved: '..label..'.'
  end)
  return ok,tostring(result)
 end
 function api.load(id)
  local ok,result=pcall(function()
   local s=session();local data=read(s);local entry
   for _,e in ipairs(data.entries)do if e.id==id and e.clan==s.clan then entry=e end end
   assert(entry,'This party preset is unavailable for the current clan.');eligible(s,entry.roles)
   assert(party.select(copy(entry.roles))~=false,'Could not apply this party preset.')
   return'Party preset loaded: '..entry.name..'.'
  end)
  return ok,tostring(result)
 end
 function api.remove(id)
  local ok,result=pcall(function()
   local s=session();local data=read(s);local index
   for i,e in ipairs(data.entries)do if e.id==id and e.clan==s.clan then index=i end end
   assert(index,'This party preset is unavailable for the current clan.')
   local entry=table.remove(data.entries,index);ctx.write(path(s),ctx.json.encode(data));return'Party preset removed: '..entry.name..'.'
  end)
  return ok,tostring(result)
 end
 return api
end
return M
