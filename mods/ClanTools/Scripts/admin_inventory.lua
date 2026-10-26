-- Exact-build inventory grants. Preview and backup precede every native ADD.
local folder=debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')
local json=dofile(folder..'json.lua')
local runtimeValid=dofile(folder..'runtime_valid.lua').valid
local M={}
local function integer(v,lo,hi)return type(v)=='number'and v%1==0 and v>=lo and v<=hi end
local function clone(v)if type(v)~='table'then return v end;local r={};for k,x in pairs(v)do r[k]=clone(x)end;return r end
function M.parse(text,nonce,command)
 assert(type(text)=='string'and #text<4096,'Invalid inventory response.')
 local r={};for line in text:gmatch('[^\r\n]+')do local k,v=line:match('^([%w_]+)=(.+)$');assert(k and not r[k],'Malformed inventory response.');r[k]=v end
 assert(tonumber(r.nonce)==nonce,'Stale inventory response.')
 assert(r.status==(command=='PROBE'and'READY'or'APPLIED'),r.status or'Missing inventory response.')
 for _,k in ipairs({'current','after','allowed'})do r[k]=tonumber(r[k])end
 assert(integer(r.current,0,100000000)and integer(r.after,0,100000000)and integer(r.allowed,0,1),'Invalid inventory readback.')
 return r
end
function M.nativeAdapter(ctx,bin,library)
 bin=bin or(ctx.root or folder..'../')..'bin/';if not bin:match('[/\\]$')then bin=bin..'/'end
 local valid=ctx.valid or runtimeValid;local nonce=0;local dispatch
 local function address(o)assert(valid(o),'Inventory object is unavailable.');return o:GetAddress()end
 local function objects(s)
  assert(s and s.offline==true and s.phase==4 and not s.combat,'Inventory grants require offline exploration.')
  assert(valid(s.pc),'Player controller is unavailable.');local owner=s.pc.PlayerState;local ownerAddress=address(owner)
  local component=owner.InventoryComponent;local componentAddress=address(component)
  local class=StaticFindObject('/Script/Wrc.WrcInventoryComponent');local classAddress=address(class)
  assert(address(component:GetClass())==classAddress,'Unsupported inventory component class.')
  assert(address(component:GetOwner())==ownerAddress,'Inventory owner changed.')
  local manager=FindFirstOf('WrcSaveManager');local managerAddress=address(manager)
  return{componentAddress,ownerAddress,classAddress,managerAddress}
 end
 local function signature(o)return table.concat(o,':')end
 local function invoke(s,command,index,quantity,expected,identity)
  assert(integer(index,1,52)and integer(quantity,1,999)and integer(expected or 0,0,100000000),'Invalid inventory request.')
  local o=objects(s);assert(not identity or signature(o)==identity,'Inventory identity changed.')
  if not dispatch then dispatch=assert(package.loadlib(bin..(library or'admin-inventory.dll'),'ClanInventory_run'))end
  nonce=nonce+1
  local f=assert(io.open(bin..'admin-inventory-request.txt','wb'))
  assert(f:write(string.format('%d %s %x %x %x %x %d %d %d\n',nonce,command,o[1],o[2],o[3],o[4],index,quantity,expected or 0)));assert(f:close())
  dispatch()
  f=assert(io.open(bin..'admin-inventory-status.txt','rb'));local text=f:read('*a');f:close()
  return M.parse(text,nonce,command)
 end
 return{identity=function(s)return signature(objects(s))end,
  probe=function(s,index,quantity,identity)return invoke(s,'PROBE',index,quantity,0,identity)end,
  add=function(s,index,quantity,current,identity)return invoke(s,'ADD',index,quantity,current,identity)end}
end
function M.new(ctx)
 local api={};local adapter=ctx.inventoryAdapter or M.nativeAdapter(ctx);local valid=ctx.valid or runtimeValid
 local root=ctx.root or folder..'../';if not root:match('[/\\]$')then root=root..'/'end
 local catalog=ctx.inventoryCatalog
 if not catalog then
  local raw;if ctx.read then raw=ctx.read(root..'data/admin-inventory.json')else local f=assert(io.open(root..'data/admin-inventory.json','rb'));raw=f:read('*a');f:close()end
  catalog=json.decode(assert(raw,'Inventory catalog is unavailable.'))
 end
 assert(type(catalog)=='table'and #catalog==52,'Unsupported inventory catalog.')
 local byIndex,byTag={},{}
 for i,e in ipairs(catalog)do
  assert(type(e)=='table'and e.index==i and type(e.name)=='string'and #e.name>0 and type(e.tag)=='string'and e.tag:match('^Gameplay%.Inventory%.')and not byTag[e.tag]
   and(e.category=='Consumable'or e.category=='Materials')and type(e.icon)=='string'and e.icon:match('^/Game/'),'Invalid inventory catalog entry.')
  byIndex[i]=clone(e);byTag[e.tag]=byIndex[i]
 end
 local definitions={
  {id='healing',label='Healing herbs',tags={'Consumable.SmallHealingHerb','Consumable.MediumHealingHerb','Consumable.BigHealingHerb'}},
  {id='medicine',label='Medicine supplies',tags={'Consumable.AntidoteHerbPouch','Consumable.CatThymePouch','Consumable.ChamomilePouch','Consumable.LavenderPouch'}},
  {id='materials',label='Den materials',tags={'Materials.Moss','Materials.CattailReed','Materials.Rock','Materials.Rope','Materials.SharpeningTreeBark','Materials.DirtMound'}},
  {id='herbs',label='Raw herbs',tags={'Materials.Borage','Materials.Comfrey','Materials.Goldenrod','Materials.Thyme','Materials.Burdock','Materials.Willow'}},
 }
 local previews={};local sequence=0;local session;local closed=false;local lastResult;local now=ctx.now or os.time
 local function enabled()return ctx.inventoryVerified==true end
 local function current()
  assert(not closed,'Inventory tools are closed.');local s=ctx.snapshot()
  assert(s and s.offline==true and s.phase==4 and not s.combat and not ctx.appearanceActive,'Inventory grants require offline exploration.')
  assert(valid(s.pawn),'Player is unavailable.')
  assert(type(s.profile)=='string'and #s.profile>0 and integer(s.slot,0,99)and type(s.worldId)=='string','Active save is unavailable.')
  local identity=adapter.identity(s);assert(type(identity)=='string'and #identity>0,'Inventory identity is unavailable.')
  local key=table.concat({s.profile,s.slot,s.chapter or'',s.worldId,tostring(s.pawn:GetAddress()),identity},'|')
  if session~=key then session=key;previews={}end
  return s,identity
 end
 local function probe(s,e,quantity,identity)
  local r=adapter.probe(s,e.index,quantity,identity)
  assert(type(r)=='table'and integer(r.current,0,100000000)and integer(r.allowed,0,1),'Invalid inventory count or capacity.')
  assert(r.current<=100000000-quantity,'Inventory quantity would overflow.')
  return{index=e.index,name=e.name,icon=e.icon,quantity=quantity,current=r.current,after=r.current+quantity,allowed=r.allowed==1}
 end
 local function preview(entries,quantity,label)
  assert(integer(quantity,1,999),'Choose a whole quantity from 1 to 999.')
  local s,identity=current();local key=session;local rows={};local allowed=true
  for _,e in ipairs(entries)do local r=probe(s,e,quantity,identity);rows[#rows+1]=r;allowed=allowed and r.allowed end
  sequence=sequence+1;local token=tostring(sequence)
  previews={} -- A newly reviewed selection invalidates all older confirmations.
  previews[token]={session=key,identity=identity,rows=clone(rows),created=now(),label=label}
  return{token=token,rows=rows,label=label,quantity=quantity,total=quantity*#rows,allowed=allowed,enabled=enabled(),expires=60}
 end
 function api.catalog(query,category)
  local out={};query=tostring(query or''):lower()
  for _,e in ipairs(catalog)do if(not category or category=='all'or category==e.category)and(query==''or e.name:lower():find(query,1,true)or e.tag:lower():find(query,1,true))then out[#out+1]=clone(e)end end
  table.sort(out,function(a,b)return a.name<b.name end);return out
 end
 function api.bundles()local out={};for i,d in ipairs(definitions)do out[i]={id=d.id,label=d.label,count=#d.tags}end;return out end
 function api.preview(index,quantity)
  local ok,r=pcall(function()local e=assert(byIndex[index],'Choose an item from the catalog.');return preview({e},quantity,e.name)end)
  return ok,ok and r or tostring(r)
 end
 function api.previewBundle(id,quantity)
  local ok,r=pcall(function()
   local d;for _,b in ipairs(definitions)do if b.id==id then d=b;break end end;assert(d,'Choose a supply bundle.')
   local entries={};for _,tag in ipairs(d.tags)do entries[#entries+1]=assert(byTag['Gameplay.Inventory.'..tag],'Bundle catalog mismatch.')end
   return preview(entries,quantity,d.label)
  end);return ok,ok and r or tostring(r)
 end
 function api.apply(token)
  local completed={};local attempted;local backup;local consumed=false
  local ok,result=pcall(function()
   assert(enabled(),'Direct inventory grants have not been verified in this game build.')
   local s,identity=current();local p=assert(previews[tostring(token)],'Refresh the inventory preview before applying.')
   assert(p.session==session and p.identity==identity,'The active inventory changed.')
   assert(now()>=p.created and now()-p.created<=60,'This preview expired. Review the item counts again.')
   local function checkAll()
    for _,row in ipairs(p.rows)do local r=probe(s,byIndex[row.index],row.quantity,identity);assert(r.current==row.current,'Inventory quantities changed. Refresh the preview.');assert(r.allowed,'Your inventory has no room for this amount.')end
   end
   checkAll();assert(type(ctx.backupSave)=='function','Save backup is unavailable.')
   backup=ctx.backupSave(s);assert(type(backup)=='string'and #backup>0,'Save backup failed.')
   s,identity=current();assert(p.session==session and p.identity==identity,'The active save or inventory changed during backup.')
   assert(enabled(),'Direct inventory grants were disabled.');checkAll()
   previews[tostring(token)]=nil;consumed=true
   for _,row in ipairs(p.rows)do
    s,identity=current();assert(p.session==session and p.identity==identity,'The active save or inventory changed.')
    assert(enabled(),'Direct inventory grants were disabled.')
    local currentRow=probe(s,byIndex[row.index],row.quantity,identity)
    assert(currentRow.current==row.current and currentRow.allowed,'Inventory capacity or quantity changed during the bundle.')
    attempted=clone(row)
    local r=adapter.add(s,row.index,row.quantity,row.current,identity)
    assert(type(r)=='table'and r.current==row.current and r.after==row.after and r.allowed==1,'Inventory readback did not match. Refresh before retrying.')
    completed[#completed+1]=clone(row);attempted=nil
   end
   local total=0;for _,row in ipairs(completed)do total=total+row.quantity end
   local message=#completed==1 and('Added '..completed[1].quantity..' × '..completed[1].name..'.')or('Added '..total..' items across '..#completed..' item types.')
   return{message=message,rows=completed,backup=backup,complete=true}
  end)
  if ok then lastResult=clone(result);return true,result end
  if consumed then previews={}end
  local message=tostring(result)
  if attempted then message='Stopped after '..#completed..' confirmed additions. The last item may have been added; refresh before retrying. '..message
  elseif #completed>0 then message='Stopped after '..#completed..' confirmed additions. '..message end
  lastResult={message=message,rows=completed,uncertain=attempted,backup=backup,complete=false}
  return false,clone(lastResult)
 end
 function api.cancelPreview()previews={};return true end
 function api.capabilities()return{enabled=enabled(),items=#catalog,quantityMaximum=999,lastResult=clone(lastResult)}end
 function api.reset()session=nil;previews={};return true end
 function api.tick()
  -- Preview/apply revalidate the current inventory themselves. Background
  -- identity checks are needed only while there is an outstanding preview.
  if next(previews)==nil then return end
  local ok=pcall(current);if not ok then api.reset()end
 end
 function api.shutdown()api.reset();closed=true;return true end
 return api
end
return M
