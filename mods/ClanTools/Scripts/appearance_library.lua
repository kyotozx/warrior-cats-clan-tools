-- Cosmetic-only presets and original/edited comparison. Native reads and writes
-- refer exclusively to the owned preview; the existing transaction owns Apply.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(folder..'json.lua')
local M={schema=1,maxPresets=32}
local function values(text)
 if type(text)~='string'or #text>512 then return nil end
 local out={};for n in text:gmatch('%S+')do
  if not n:match('^%d+$')then return nil end
  local v=tonumber(n);if not v or v<0 or v>255 then return nil end;out[#out+1]=v
 end
 if #out~=24 or(out[23]~=0 and out[23]~=1)or out[24]>16 then return nil end
 return table.concat(out,' ')
end
M.values=values
local function cleanLabel(s)
 s=tostring(s or'Appearance'):gsub('[%c]',' '):gsub('^%s+',''):gsub('%s+$','')
 if s==''or not utf8.len(s)then return'Appearance'end
 local endByte=utf8.offset(s,71)
 return endByte and s:sub(1,endByte-1)or s
end
function M.new(ctx)
 assert(type(ctx.native)=='function'and type(ctx.ensureEditable)=='function'and type(ctx.target)=='function')
 local api={};local selected=1;local comparing=false
 local path=(ctx.root or'')..'appearance-presets.json'
 local read=ctx.read or function(p)local f=io.open(p,'rb');if not f then return end;local s=f:read('*a');f:close();return s end
 local write=ctx.write or function(p,s)local f=assert(io.open(p,'wb'));assert(f:write(s));f:close()end
 local data={schema=M.schema,presets={},originals={}}
 local loadError
 local raw=read(path)
 if raw then
  local ok,v=pcall(json.decode,raw)
  if ok and type(v)=='table'and v.schema==M.schema and type(v.presets)=='table'and type(v.originals)=='table'and #v.presets<=M.maxPresets then
   local good=true
   for _,p in ipairs(v.presets)do if type(p)~='table'or type(p.label)~='string'or not values(p.values)then good=false;break end end
   for key,p in pairs(v.originals)do if type(key)~='string'or type(p)~='table'or not values(p.values)then good=false;break end end
   if good then data=v else loadError='The appearance library contains an invalid preset.'end
  else loadError='The appearance library could not be read; it was kept unchanged.'end
 end
 local function allowed()
  local ok,err=ctx.ensureEditable();if not ok then return nil,err or'No editable appearance preview.'end
  return true
 end
 local function send(command)
  local ok,err=allowed();if not ok then return nil,err end
  return ctx.native(command)
 end
 local function persist(nextData)
  if loadError then return nil,loadError end
  local content=json.encode(nextData);local previous=read(path)
  local ok,err=pcall(function()
   if previous then write(path..'.previous.txt',previous)end
   write(path,content);assert(read(path)==content,'Appearance library readback failed')
  end)
  if not ok then if previous then pcall(write,path,previous)end;return nil,tostring(err)end
  data=nextData;return true
 end
 local function clone()return json.decode(json.encode(data))end
 local function export(command)
  local r,err=send(command);if not r then return nil,err end
  local v=values(tostring(r.action):match('^COSMETICS%s+(.+)$'))
  if not v then return nil,'The game did not return a valid cosmetic preset.'end
  return v
 end
 local function key()
  local s=ctx.snapshot and ctx.snapshot();local t=ctx.target()
  if not s or not t or type(s.profile)~='string'or type(t.role)~='number'then return nil end
  -- Earlier originals used the wrong character-slot reader. Keep those entries
  -- and shared presets intact, but never restore an unproven legacy original.
  local identity,why=ctx.characterKey(s);if not identity then return nil,why end
  return 'v3:'..identity..':'..tostring(s.chapter)..':'..tostring(t.role)
 end
 local function edited()
  if not comparing then return true end
  local ok,err=send('COMPARE 0');if not ok then return nil,err end;comparing=false;return true
 end
 function api.comparisonActive()return comparing end
 function api.leaveComparison()return edited()end
 function api.begin()
  comparing=false;local k,why=key();if not k then return nil,why or'Character identity is unavailable.'end;if data.originals[k]then return true end
  local v,err=export('ORIGINAL_READ');if not v then return nil,err end
  local nextData=clone();nextData.originals[k]={values=v,label=cleanLabel(ctx.target().name)}
  return persist(nextData)
 end
 function api.randomize()
  local ok,err=edited();if not ok then return nil,err end
  return send('RANDOMIZE')
 end
 function api.compare()
  local desired=not comparing;local ok,err=send('COMPARE '..(desired and'1'or'0'))
  if not ok then return nil,err end;comparing=desired;return true
 end
 function api.reset()
  local ok,err=send('RESET');if not ok then return nil,err end;comparing=false;return true
 end
 function api.restoreOriginal()
  local k=key();local entry=k and data.originals[k]
  if not entry then return nil,'No original appearance was recorded for this cat.'end
  local ok,err=edited();if not ok then return nil,err end
  return send('PREVIEW_LOAD '..entry.values)
 end
 local function playerStore()return (ctx.target()or{}).player and ctx.skins and ctx.skins.store end
 function api.presets()
  local store=playerStore();if store then local list,err=store.list();return list,selected,err end
  local list={};for i,p in ipairs(data.presets)do list[i]={label=p.label}end
  return list,selected,loadError
 end
 function api.selectPreset(delta)
  local ok,err=allowed();if not ok then return nil,err end
  local list=api.presets();if #list==0 then return nil,'Save a preview to create your first preset.'end
  selected=((selected-1+(delta or 1))%#list)+1;return true
 end
 function api.savePreset(label)
  local store=playerStore();if store then local v,err=export('PREVIEW_READ');if not v then return nil,err end;store.save(label or(ctx.target()or{}).name or'Skin',v);selected=#store.list();return true end
  if loadError then return nil,loadError end
  if #data.presets>=M.maxPresets then return nil,'The library is full (32 presets). Delete one before saving another.'end
  local v,err=export('PREVIEW_READ');if not v then return nil,err end
  local name=cleanLabel(label or(ctx.target()or{}).name)..' '..tostring(#data.presets+1)
  local nextData=clone();nextData.presets[#nextData.presets+1]={label=name,values=v}
  local ok;ok,err=persist(nextData);if ok then selected=#data.presets end;return ok,err
 end
 function api.loadPreset()
  local list=playerStore()and api.presets()or data.presets;local p=list[selected];if not p then return nil,'Select a saved appearance first.'end
  local ok,err=edited();if not ok then return nil,err end
  return send('PREVIEW_LOAD '..p.values)
 end
 function api.deletePreset()
  local store=playerStore();if store then local list=store.list();local e=list[selected];if not e then return nil,'Select a saved skin.'end;store.delete(e.id);selected=math.max(1,selected-1);return true end
  local ok,err=allowed();if not ok then return nil,err end
  if not data.presets[selected]then return nil,'There is no selected preset.'end
  local nextData=clone();table.remove(nextData.presets,selected)
  ok,err=persist(nextData);if ok then selected=math.max(1,math.min(selected,#data.presets))end;return ok,err
 end
 return api
end
return M
