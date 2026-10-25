-- Actual consumption observer. No inventory changes, heal calls or guessed success.
-- Root owns UI and the game-thread tick. Native installation is reversible.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local catalog=dofile(folder..'item_catalog.lua')
local labels=dofile(folder..'item_labels.lua')
local M={}
local function finite(x) return type(x)=='number' and x==x and math.abs(x)<math.huge end
local function integer(x) return finite(x) and x%1==0 end
local valid=dofile(folder..'runtime_valid.lua').valid
local function address(o) if not valid(o) then return 0 end;local ok,a=pcall(function()return o:GetAddress()end);return ok and a or 0 end
local function text(o) if type(o)=='string' then return o end;local ok,s=pcall(function()return o:ToString()end);return ok and s or nil end
local function number(n) if n%1==0 then return string.format('%.0f',n) end;return string.format('%.6g',n) end
local function resource(r)
 if type(r)~='table' or not r.valid then return nil end
 for _,k in ipairs({'before','after','max_before','max_after'})do if not finite(r[k]) then return nil end end
 if r.before<0 or r.after<0 or r.max_before<=0 or r.max_after<=0 or r.before>r.max_before+0.01 or r.after>r.max_after+0.01 then return nil end
 return {before=r.before,after=r.after,max_before=r.max_before,max_after=r.max_after,recovered=math.max(0,r.after-r.before)}
end

-- Pure formatter for independently observed, synchronous native transactions.
function M.format(event,info)
 if type(event)~='table' or type(info)~='table' then return nil,'missing event metadata' end
 for _,k in ipairs({'before','after','requested','sequence','epoch'})do if not integer(event[k]) or event[k]<0 then return nil,'invalid transaction count' end end
 if event.sequence<1 or event.epoch<1 or event.requested<1 or event.after>event.before or event.before-event.after>event.requested then return nil,'inconsistent transaction' end
 local used=event.before-event.after
 -- A count decrement, rather than selection/input/eligibility, is the proof.
 if used==0 then return {kind='item_blocked',title='Item not used',lines={'The item could not be used. '..event.after..' remaining.'},item_tag=info.tag,name=info.name,remaining=event.after,consumed=0,sequence=event.sequence,original_sound=true} end
 local label=info.name and info.name~='' and info.name or 'Item'
 local out={kind='item_used',title='Used '..label,lines={number(event.after)..' remaining'},name=info.name,icon=labels[info.tag or'']and labels[info.tag].icon,item_tag=info.tag,remaining=event.after,consumed=used,sequence=event.sequence,resources={},original_sound=true}
 if used>1 then out.title='Used '..number(used)..' × '..label end
 for _,target in ipairs(event.targets or {})do
  local hp,sp=resource(target.health),resource(target.stamina)
  local name=(info.target_names or {})[target.actor] or (#(event.targets or {})==1 and 'You' or 'Companion')
  local details={}
  for _,entry in ipairs({{label='HP',data=hp},{label='Stamina',data=sp}})do
   local r=entry.data
   if r then
    local value=number(r.after)..'/'..number(r.max_after)
    details[#details+1]=entry.label..' '..(r.recovered>0 and ('+'..number(r.recovered)..' · ') or '')..value
   end
  end
  if #details>0 then out.lines[#out.lines+1]=name..': '..table.concat(details,'   |   ') end
  out.resources[#out.resources+1]={actor=target.actor,name=name,health=hp,stamina=sp}
 end
 return out
end

local function tokens(line)local out={};for s in line:gmatch('%S+')do out[#out+1]=s end;return out end
function M.parse_events(data)
 if type(data)~='string' or #data>1024*1024 then return nil,'invalid mailbox size' end
 local lines={};for line in data:gmatch('[^\r\n]+')do lines[#lines+1]=line end
 local header=tokens(lines[1] or '');local dropped=tonumber(header[3])
 if #header~=3 or header[1]~='ITEM_EVENTS' or header[2]~='1' or not integer(dropped) or dropped<0 then return nil,'invalid mailbox version' end
 local events,i={},2
 while i<=#lines do
  if #events>=64 then return nil,'mailbox exceeds ring bound' end
  local t=tokens(lines[i]);i=i+1
  if #t~=9 or t[1]~='E' then return nil,'invalid event record' end
  local e={epoch=tonumber(t[2]),sequence=tonumber(t[3]),tag_index=tonumber(t[4]),tag_number=tonumber(t[5]),before=tonumber(t[6]),after=tonumber(t[7]),requested=tonumber(t[8]),targets={}}
  local count=tonumber(t[9]);if not integer(count) or count<0 or count>4 then return nil,'invalid target count' end
  if not integer(e.tag_index) or e.tag_index<0 or not integer(e.tag_number) or e.tag_number<0 then return nil,'invalid gameplay tag' end
  for _=1,count do
   local row=tokens(lines[i] or '');i=i+1
   if #row~=12 or row[1]~='T' or not row[2]:match('^%x+$') or #row[2]>16 then return nil,'invalid target record' end
   local target={actor=row[2]:lower()}
   for n,key in ipairs({'health','stamina'})do
    local start=3+(n-1)*5
    if row[start]~='0' and row[start]~='1' then return nil,'invalid resource status' end
    target[key]={valid=row[start]=='1',before=tonumber(row[start+1]),after=tonumber(row[start+2]),max_before=tonumber(row[start+3]),max_after=tonumber(row[start+4])}
   end
   e.targets[#e.targets+1]=target
  end
  events[#events+1]=e
 end
 return events,nil,dropped
end

function M.new(ctx)
 assert(type(ctx)=='table' and type(ctx.notify)=='function','Item feedback requires ctx.notify(event).')
 local api={};local root=ctx.mod_root or ctx.root or folder..'../';if not root:match('[/\\]$')then root=root..'/'end
 local bin=root..'bin/';local enabled=true;local attached=false;local stopped=false
 local generation=0;local last_sequence=0;local key;local ticks=0;local current;local last_error;local snapshot_key
 local tag_by_index={};local names={};local native=ctx.item_native
 local cat_names
 local function log(s)if ctx.log then ctx.log('[ItemFeedback] '..s)end end
 local function error_once(s)if s~=last_error then last_error=s;log(s)end end
 local function read(name)local f=io.open(bin..name,'rb');if not f then return nil end;local s=f:read('*a');f:close();return s end
 local function write(name,s)local f=assert(io.open(bin..name,'wb'));assert(f:write(s));assert(f:close())end
 local function load_native()
  if native then return true end
  local library=ctx.item_dll or'item-feedback-v5.dll'
  local install,why=package.loadlib(bin..library,'ItemFeedback_install');if not install then return false,why end
  local drain=assert(package.loadlib(bin..library,'ItemFeedback_drain'))
  local remove=assert(package.loadlib(bin..library,'ItemFeedback_remove'))
  native={install=function(watch)write('item-watch.txt',watch);install();return read('item-status.txt')end,drain=function()drain();return read('item-events.txt')end,remove=function()remove();return read('item-status.txt')end}
  return true
 end
 local function tag_map()
  for tag in pairs(catalog)do
   if ctx.item_tag_index then tag_by_index[ctx.item_tag_index(tag)]=tag
   elseif FName then local name=FName(tag);if name:ToString()==tag then tag_by_index[name:GetComparisonIndex()]=tag end end
  end
 end
 local function item_name(tag)
  if names[tag] then return names[tag] end
  if ctx.item_name then local ok,n=pcall(ctx.item_name,tag);if ok and type(n)=='string' and n~='' then names[tag]=n;return n end end
  if labels[tag]then names[tag]=labels[tag].name;return names[tag]end
  -- Real localized item title from the game's reflected data-table query.
  local ok,n=pcall(function()
   local manager=FindFirstOf('WrcQuestManager');if not valid(manager) then manager=FindFirstOf('QuestManager')end
   if not valid(manager) then return nil end
   local out={};manager:GetItemStatsDataFromTag({TagName=FName(tag)},out)
   local value=out.outStruct or out
   return text(value.Title)
  end)
  if ok and n and n~='' then names[tag]=n;return n end
  return nil
 end
 local function find_resource(class,actors,field,overwrite)
  if not FindAllOf then return end
  for _,component in ipairs(FindAllOf(class) or {})do
   if valid(component)then
    local ok,owner=pcall(function()return component:GetOwner()end)
    local id=ok and address(owner) or 0
    if actors[id] and (overwrite or not actors[id][field])then actors[id][field]=component end
   end
  end
 end
 local function discover(snapshot)
  if ctx.item_context then return ctx.item_context(snapshot) end
  if type(snapshot)~='table' or snapshot.offline~=true or not valid(snapshot.pawn)then return nil end
  local pawn=snapshot.pawn
  -- Combat possession can detach PlayerState from the exploration pawn while
  -- that pawn remains the campaign's MainCharacter. The controller retains it.
  local state
  if valid(snapshot.pc)then state=snapshot.pc.PlayerState end
  if not valid(state)then state=pawn.PlayerState end
  if not valid(state)then return nil end
  local inventory=state.InventoryComponent;if not valid(inventory)then return nil end
  local list={};local actors={}
  local function add(actor)
   local id=address(actor);if id~=0 and not actors[id] and #list<4 then
    local name=ctx.character_name and ctx.character_name(actor)
    if not name then
     local ok,result=pcall(function()
      if not cat_names then
       local f=io.open(root..'data/catalog.json','rb');if not f then return nil end
       local raw=f:read('*a');f:close();cat_names=dofile(folder..'json.lua').decode(raw).Names or{}
      end
      local custom=actor.MeshCustomizationComponent.CustomData
      local prefix,suffix=text(custom.PrefixNameId),text(custom.SuffixNameId)
      return prefix and suffix and cat_names[prefix..suffix]
     end)
     if ok then name=result end
    end
    name=name or'Companion'
    local t={actor=actor,name=name};list[#list+1]=t;actors[id]=t
   end
  end
  if snapshot.combat then
   local gs=snapshot.gameState;if not valid(gs)then return nil end
   local director=gs.Director;if not valid(director)then return nil end
   director.PlayerParty:ForEach(function(_,value)local component=value:get();if valid(component)then add(component:GetOwner())end end)
   if #list==0 then return nil end
  else
   list[1]={actor=pawn,name='You'};actors[address(pawn)]=list[1]
   pcall(function()pawn.Party:ForEach(function(_,value)add(value:get())end)end)
  end
  find_resource('SwtQuestHealthComponent',actors,'health',false)
  find_resource('SwtQuestStaminaComponent',actors,'stamina',false)
  if snapshot.combat then find_resource('SwtCombatStaminaComponent',actors,'stamina',true)end
  return {inventory=inventory,targets=list,session=tostring(snapshot.worldId or '')..':'..tostring(snapshot.profile or '')..':'..tostring(snapshot.combat==true)}
 end
 local function context_key(c)
  if type(c)~='table' or address(c.inventory)==0 then return nil end
  local parts={tostring(c.session or ''),string.format('%x',address(c.inventory))}
  for _,t in ipairs(c.targets or {})do
   if address(t.actor)==0 then return nil end
   parts[#parts+1]=string.format('%x/%x/%x',address(t.actor),address(t.health),address(t.stamina))
  end
  if #(c.targets or {})>4 then return nil end
  return table.concat(parts,':')
 end
 function api.reset(reason)
  local changed=attached or key~=nil or current~=nil
  if attached then
   local ok,result=pcall(native.remove)
   if not ok or type(result)~='string' or not result:match('^REMOVED')then error_once('Observer removal failed: '..tostring(result));return false end
  end
  attached=false;key=nil;current=nil;last_sequence=0;snapshot_key=nil
  if reason and changed then log('Reset: '..reason)end
  return true
 end
 function api.set_enabled(value)
  enabled=value==true;if not enabled then return api.reset('disabled')end;return true
 end
 function api.accept(event,info)
  if not enabled or stopped then return false end
  if not integer(event.sequence) or event.sequence<=last_sequence or event.epoch~=generation then return false end
  local message,why=M.format(event,info)
  if not message then error_once(why);return false end
  last_sequence=event.sequence
  -- Sound is already played by the game's successful item-use path. Do not
  -- duplicate it, and never emit a success cue for an unchanged inventory.
  ctx.notify(message);return true
 end
 function api.tick(snapshot)
  if stopped or not enabled then return end
  local ok,err=pcall(function()
   if not snapshot and ctx.snapshot then snapshot=ctx.snapshot()end
   -- Revoke immediately on scene/profile/combat changes, before draining an
   -- old observation. Expensive resource discovery remains amortized.
   local next_snapshot_key=type(snapshot)=='table' and table.concat({tostring(snapshot.worldId),tostring(snapshot.profile),tostring(snapshot.combat),tostring(snapshot.offline),tostring(address(snapshot.pawn))},':') or 'none'
   if attached and snapshot_key~=next_snapshot_key then assert(api.reset(),'could not reset old scene')end
   ticks=ticks+1
   if not attached or ticks%4==1 then
    local c=discover(snapshot);local next_key=context_key(c)
    if not next_key then api.reset();return end
    if next_key~=key then
     assert(api.reset(),'could not remove prior observer')
     local loaded,why=load_native();assert(loaded,why)
     tag_map();generation=generation+1
     local lines={string.format('1 %d %x %d',generation,address(c.inventory),#(c.targets or {}))}
     for _,t in ipairs(c.targets or {})do lines[#lines+1]=string.format('%x %x %x',address(t.actor),address(t.health),address(t.stamina))end
     local status=native.install(table.concat(lines,'\n')..'\n')
     if type(status)~='string'or not status:match('^INSTALLED')then pcall(native.remove);error(tostring(status))end
     attached=true;key=next_key;current=c;snapshot_key=next_snapshot_key;last_error=nil;log('Consumption observer attached.')
    end
   end
   if not attached then return end
   local data=native.drain();local events,why,dropped=M.parse_events(data)
   assert(events,why);if dropped>0 then log(dropped..' observations dropped; no fabricated catch-up notifications.')end
   local target_names={};for _,t in ipairs(current.targets or {})do target_names[string.format('%x',address(t.actor))]=t.name or 'Companion'end
   for _,event in ipairs(events)do
    local tag=event.tag_number==0 and tag_by_index[event.tag_index]
    if tag then api.accept(event,{tag=tag,name=item_name(tag),target_names=target_names})end
   end
  end)
  if not ok then error_once(tostring(err));api.reset()end
 end
 function api.shutdown()local ok=api.reset('shutdown');if ok then stopped=true end;return ok end
 function api.status()return {enabled=enabled,attached=attached,generation=generation,last_sequence=last_sequence,error=last_error}end
 return api
end
return M
