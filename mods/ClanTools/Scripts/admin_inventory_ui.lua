-- Native item browser: direct inventory grants and the original pickup spawner.
local M={}
function M.new(ctx,p)
 local api={};local mode='inventory';local query,page,quantity,category='',1,1,'all';local preview,result,selection
 local pickupBundles={
  {label='Healing herbs',ids={'SmallHealingHerb','MediumHealingHerb','BigHealingHerb'}},
  {label='Catnip',ids={'SmallCatnip','MediumCatnip','BigCatnip'}},
  {label='Medicine supplies',ids={'AntidoteHerbPouch','CatThymePouch','ChamomilePouch','LavenderPouch'}}
 }
 local function backend()return assert(ctx.inventoryTools,'Direct inventory tools are unavailable.')end
 local function message(r)return type(r)=='table'and r.message or tostring(r)end
 local function clearPreview()if ctx.inventoryTools then ctx.inventoryTools.cancelPreview()end;preview=nil;selection=nil;result=nil end
 local function changeMode(value)clearPreview();mode=value;page=1;query='';category='all';if mode=='pickups'then quantity=math.min(quantity,10)end;p.refresh()end
 local function requestPreview(chosen)
  local b=backend();local ok,r
  if chosen.bundle then ok,r=b.previewBundle(chosen.bundle,chosen.quantity)else ok,r=b.preview(chosen.index,chosen.quantity)end
  if ok then preview=r;selection=chosen;result=nil else preview=nil;selection=nil;p.notify(message(r))end;p.refresh()
 end
 local function quantityPrompt()
  local maximum=mode=='pickups'and 10 or 999
  p.prompt({title='Quantity per item',value=tostring(quantity),maxLength=3,
   validate=function(value)local n=tonumber(value);if n and n%1==0 and n>=1 and n<=maximum then return tostring(n)end;return nil,'Choose a whole number from 1 to '..maximum..'.'end,
   accept=function(value)quantity=tonumber(value);p.refresh();return true end})
 end
 local function controls()
  p.button(query==''and'Search items'or'Search: '..query,430,335,800,64,function()
   p.prompt({title='Search items',value=query,maxLength=32,accept=function(value)query=value;page=1;p.refresh();return true end})
  end)
  p.button('Clear',1250,335,180,64,function()query='';page=1;p.refresh()end,false,query~='')
  p.button('Quantity: '..quantity,1450,335,330,64,quantityPrompt)
 end
 local function card(entry,x,y,fn,enabled)
  local label=entry.name or entry.label
  if p.image and entry.icon then
   p.panel(x,y,660,94);p.image(entry.icon,x+15,y+15,64)
   p.button(label,x+96,y+13,550,68,fn,false,enabled)
  else p.button(label,x,y,660,94,fn,false,enabled)end
 end
 local function confirmation()
  local b=backend();local rows=preview and preview.rows or result.rows
  p.text(preview and preview.label or(result.complete and'Items added'or'Inventory update stopped'),430,335,1350,28,nil,true)
  p.text(preview and('Add '..preview.quantity..' of each item. Current inventory counts are shown below.')or result.message,432,390,1340,18)
  for i,row in ipairs(rows or{})do
   local x=430+((i-1)%2)*690;local y=450+math.floor((i-1)/2)*118
   p.panel(x,y,660,102)
   if p.image and row.icon then p.image(row.icon,x+15,y+18,64)end
   local offset=p.image and row.icon and 96 or 24
   p.text(row.name,x+offset,y+15,640-offset,23,nil,true)
   p.text(row.current..' → '..row.after..'  (+'..row.quantity..')'..(preview and not row.allowed and'  •  No room'or''),x+offset,y+58,640-offset,18)
  end
  if preview then
   local cap=b.capabilities()
   p.text(not cap.enabled and'Direct grants are awaiting validation for this game build.'or not preview.allowed and'This amount exceeds inventory capacity. Cancel and choose a smaller quantity.'or'A save backup is created before adding items. Each addition follows the game inventory rules.',445,820,1320,18)
   p.button('Cancel',430,914,410,62,function()clearPreview();p.refresh()end)
   p.button('Refresh counts',860,914,410,62,function()requestPreview(selection)end)
   p.button('Confirm: add items',1290,914,490,62,function()
    local token=preview.token;preview=nil;selection=nil
    local _,r=b.apply(token);result=type(r)=='table'and r or{message=tostring(r),rows={},complete=false};p.refresh()
   end,true,cap.enabled and preview.allowed)
  else
   if result.uncertain then p.text('Unconfirmed item: '..result.uncertain.name..'. Its quantity may have changed; review a fresh preview before retrying.',445,820,1320,18)
   elseif result.backup then p.text('The save backup from before this operation has been preserved.',445,820,1320,18)end
   p.button('Back to items',430,914,1350,62,function()clearPreview();p.refresh()end)
  end
 end
 local function inventory()
  if not ctx.inventoryTools then p.text('Direct inventory tools are unavailable.',445,350,1300,24);return end
  if preview or result then confirmation();return end
  controls()
  local categories={{'all','All items'},{'Consumable','Consumables'},{'Materials','Materials'},{'bundles','Supply bundles'}}
  for i,c in ipairs(categories)do p.button(c[2],430+(i-1)*345,420,315,62,function()category=c[1];page=1;p.refresh()end,category==c[1])end
  local rows=category=='bundles'and backend().bundles()or backend().catalog(query,category)
  if category=='bundles'and query~=''then local filtered={};for _,r in ipairs(rows)do if r.label:lower():find(query:lower(),1,true)then filtered[#filtered+1]=r end end;rows=filtered end
  local pages=math.max(1,math.ceil(#rows/6));page=math.min(page,pages)
  for i=1,6 do local entry=rows[(page-1)*6+i];if entry then
   card(entry,430+((i-1)%2)*690,510+math.floor((i-1)/2)*110,function()
    requestPreview({index=entry.index,bundle=category=='bundles'and entry.id or nil,quantity=quantity})
   end,true)
  end end
  if #rows==0 then p.text('No matching items.',450,550,1300,24)end
  p.text('Page '..page..' / '..pages..'  •  '..#rows..' results  •  Select an item to review its current quantity.',445,850,1320,18)
  p.button('Previous',430,914,660,62,function()page=page-1;p.refresh()end,false,page>1)
  p.button('Next',1120,914,660,62,function()page=page+1;p.refresh()end,false,page<pages)
 end
 local function pickups()
  controls();local cap=ctx.admin.capabilities();local rows={};local canSpawn=cap.actions and cap.actions.spawn_item and cap.actions.spawn_item.enabled
  for _,e in ipairs(cap.items or{})do if query==''or e.label:lower():find(query:lower(),1,true)or e.id:lower():find(query:lower(),1,true)then rows[#rows+1]=e end end
  local pages=math.max(1,math.ceil(#rows/6));page=math.min(page,pages)
  for i=1,6 do local entry=rows[(page-1)*6+i];if entry then
   card(entry,430+((i-1)%2)*690,425+math.floor((i-1)/2)*110,function()
    local _,r=ctx.admin.action('spawn_item',{id=entry.id,quantity=quantity});p.notify(message(r));p.refresh()
   end,canSpawn and cap.spawned+quantity<=30)
  end end
  if #rows==0 then p.text('No matching items.',455,460,1250,25,nil,true)end
  for i,b in ipairs(pickupBundles)do p.button(b.label,430+(i-1)*458,780,434,70,function()
   local current=ctx.admin.capabilities();assert(current.spawned+#b.ids*quantity<=30,'Clear spawned actors before adding this bundle.')
   local done=0;for _,id in ipairs(b.ids)do local ok,r=ctx.admin.action('spawn_item',{id=id,quantity=quantity});if not ok then p.notify('Bundle stopped after '..done..' pickups: '..message(r));p.refresh();return end;done=done+quantity end
   p.notify(done..' pickups spawned. Collect them to add them to your inventory.');p.refresh()
  end,false,canSpawn and cap.spawned+#b.ids*quantity<=30)end
  p.text('Page '..page..' / '..pages..'  •  '..cap.spawned..' spawned actors  •  Collect pickups to receive their items.',445,868,1320,17)
  p.button('Previous',430,914,400,62,function()page=page-1;p.refresh()end,false,page>1)
  p.button('Clear spawned actors',860,914,490,62,function()local _,r=ctx.admin.action('clear_spawned');p.notify(message(r));p.refresh()end)
  p.button('Next',1380,914,400,62,function()page=page+1;p.refresh()end,false,page<pages)
 end
 function api.page()
  p.text('Items & supplies',430,135,1350,36,nil,true)
  p.text(mode=='inventory'and'Add items directly through the original inventory system. Review counts before confirming.'or'Spawn nearby pickups and collect them normally. Quantity applies to each item in a bundle.',432,198,1340,17)
  p.button('Inventory',430,250,660,64,function()changeMode('inventory')end,mode=='inventory')
  p.button('Pickups',1120,250,660,64,function()changeMode('pickups')end,mode=='pickups')
  if mode=='inventory'then inventory()else pickups()end
 end
 function api.back()if preview or result then clearPreview();p.refresh();return true end;return false end
 return api
end
return M
