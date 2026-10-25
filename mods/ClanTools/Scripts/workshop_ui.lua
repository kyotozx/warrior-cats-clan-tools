local M={}
function M.new(ctx,p)
 local api={};local query,category,page,quantity,free='', 'all',1,1,false
 local preview,result
 local function backend()return assert(ctx.workshop,'Workshop is unavailable.')end
 local function clear()backend().cancel();preview=nil;result=nil end
 local function review(e)
  local ok,r=backend().preview(e.index,quantity,free)
  if ok then preview=r;result=nil else p.notify(r)end;p.refresh()
 end
 local function confirmation()
  if result then
   p.text(result.complete and'Crafting complete'or'Crafting stopped',430,135,1350,36,nil,true)
   p.text(result.message,445,260,1320,20)
   if result.complete then
    p.image(result.entry.icon,460,350,128)
    p.text(result.entry.name,630,370,1100,30,nil,true)
    p.text('In inventory: '..result.after,630,428,1100,22)
    p.text(result.entry.category=='Decoration'and'Place your decoration at a compatible den spot using the original customization menu.'or'Your items are available in the original inventory.',445,590,1320,20)
   end
   if result.backup then p.text('A backup from before this craft has been saved.',445,800,1320,18)end
   p.button('Back to workshop',430,914,1350,62,function()clear();p.refresh()end)
   return
  end
  local r=preview
  p.text('Review your craft',430,135,1350,36,nil,true)
  p.text(r.free and'Free crafting: no materials will be consumed.'or'Original recipe: the material costs below will be consumed.',432,202,1340,19)
  p.panel(430,270,1350,150);p.image(r.entry.icon,450,290,105)
  p.text(r.quantity..' × '..r.entry.name,590,291,1140,28,nil,true)
  p.text('Inventory: '..r.current..' to '..r.after..'  |  Completed immediately',590,351,1140,20)
  for i,c in ipairs(r.costs)do
   local y=450+(i-1)*83;p.panel(430,y,1350,73);p.image(c.icon,446,y+8,56)
   p.text(c.name,530,y+16,650,22,nil,true)
   p.text(r.free and('Have '..c.current..'  ·  Free')or('Need '..c.need..'  ·  Have '..c.current..(c.current<c.need and'  ·  Missing '..(c.need-c.current)or'')),1200,y+20,550,18)
  end
  if #r.costs==0 then p.text('This item has no original crafting recipe. It is available through Free crafting.',445,470,1320,21)end
  p.text(r.allowed and(r.entry.category=='Decoration'and'Added to your inventory, ready to place at a compatible den spot.'or'Added directly to your inventory. A save backup is created before crafting.')or r.reason,445,822,1320,18)
  p.button('Cancel',430,914,410,62,function()clear();p.refresh()end)
  p.button('Refresh counts',860,914,410,62,function()review(r.entry)end)
  p.button(r.free and'Confirm free craft'or'Confirm craft',1290,914,490,62,function()
   local token=r.token;preview=nil;local _,receipt=backend().apply(token);result=receipt;p.refresh()
  end,true,r.allowed and ctx.workshopVerified==true)
 end
 function api.page()
  if preview or result then confirmation();return end
  p.text('Den workshop',430,135,1350,38,nil,true)
  p.text('Craft decorations and supplies. Decorations have original recipes; other items use Free crafting.',432,202,1340,18)
  p.button(query==''and'Search items'or'Search: '..query,430,275,650,64,function()
   p.prompt({title='Search workshop',value=query,maxLength=32,accept=function(v)query=v;page=1;p.refresh();return true end})
  end)
  p.button('Quantity: '..quantity,1100,275,270,64,function()
   p.prompt({title='Craft quantity',value=tostring(quantity),maxLength=2,validate=function(v)local n=tonumber(v);if n and n%1==0 and n>=1 and n<=99 then return tostring(n)end;return nil,'Choose 1 to 99.'end,accept=function(v)quantity=tonumber(v);p.refresh();return true end})
  end)
  p.button(free and'Cost: Free'or'Cost: Materials',1390,275,390,64,function()free=not free;p.refresh()end,free)
  local categories={{'all','All'},{'Decoration','Decorations'},{'Consumable','Herbs'},{'Materials','Materials'},{'Fresh-kill','Fresh-kill'},{'Cosmetic','Accessories'}}
  for i,c in ipairs(categories)do p.button(c[2],430+(i-1)*225,360,215,60,function()category=c[1];page=1;p.refresh()end,category==c[1])end
  local rows=backend().catalog(query,category);local pages=math.max(1,math.ceil(#rows/6));page=math.min(page,pages)
  local available=backend().available()
  for i=1,6 do local e=rows[(page-1)*6+i];if e then
   local x,y=430+((i-1)%2)*690,450+math.floor((i-1)/2)*110
   p.panel(x,y,660,96);p.image(e.icon,x+15,y+16,64)
   p.button(e.name,x+94,y+3,550,55,function()review(e)end,false,available)
   p.text(e.category=='Decoration'and(e.size..' decoration · '..(free and'Free'or'Original recipe'))or'Inventory supply · Free mode',x+104,y+61,535,15)
  end end
  if #rows==0 then p.text('No matching items. Change or clear your search.',450,500,1300,24)end
  p.text(available and'Crafted items are ready immediately. Use the original den menu to place decorations.'or'Enter your den to craft. You can browse the catalog from anywhere.',445,812,1320,18)
  p.text('Page '..page..' / '..pages..'  ·  '..#rows..' items  ·  Select an item to review its cost and quantity.',445,858,1320,17)
  p.button('Previous',430,914,410,62,function()page=page-1;p.refresh()end,false,page>1)
  p.button('Clear search',860,914,410,62,function()query='';page=1;p.refresh()end,false,query~='')
  p.button('Next',1290,914,490,62,function()page=page+1;p.refresh()end,false,page<pages)
 end
 function api.back()if preview or result then clear();p.refresh();return true end;return false end
 return api
end
return M
