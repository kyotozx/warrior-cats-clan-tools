local M=dofile('mods/ClanTools/Scripts/admin_inventory_ui.lua')
local buttons,texts,images={}, {},{};local prompt;local canceled,applied,spawned=0,0,0;local enabled=false;local selected
local entry={index=1,name='Yarrow Leaves',icon='/Game/Icon'}
local b={catalog=function()return{entry}end,bundles=function()return{{id='herbs',label='Raw herbs',count=6}}end,
 capabilities=function()return{enabled=enabled}end,cancelPreview=function()canceled=canceled+1 end,
 preview=function(index,quantity)selected={index=index,quantity=quantity};return true,{token='1',label=entry.name,quantity=quantity,allowed=true,rows={{index=1,name=entry.name,icon=entry.icon,quantity=quantity,current=4,after=4+quantity,allowed=true}}}end,
 previewBundle=function(id,q)selected={bundle=id,quantity=q};return true,{token='2',label='Raw herbs',quantity=q,allowed=true,rows={}}end,
 apply=function(token)applied=applied+1;return true,{complete=true,message='Items added.',rows={},backup='backup'}end}
local ctx={inventoryTools=b,admin={capabilities=function()return{items={{id='Herb',label='Pickup herb'}},spawned=0,actions={spawn_item={enabled=true}}}end,
 action=function(id,args)if id=='spawn_item'then spawned=spawned+args.quantity end;return true,'OK'end}}
local p={button=function(label,x,y,w,h,fn,selected,active)assert(w>=180 and h>=62 and x>=430 and x+w<=1780 and y+h<=990);buttons[label]={fn=fn,enabled=active~=false}end,
 text=function(label)texts[#texts+1]=label end,image=function(path)images[#images+1]=path end,panel=function()end,notify=function()end,refresh=function()end,prompt=function(o)prompt=o end}
local ui=M.new(ctx,p)
local function draw()buttons={};texts={};ui.page()end
draw();assert(buttons.Inventory and buttons.Pickups and buttons['Yarrow Leaves']and #images==1)
buttons['Quantity: 1'].fn();assert(prompt.validate('999')=='999'and not prompt.validate('1000'));prompt.accept('999');draw();buttons['Yarrow Leaves'].fn();draw()
assert(selected.quantity==999 and not buttons['Confirm: add items'].enabled);assert(ui.back()and canceled>0)
enabled=true;draw();buttons['Yarrow Leaves'].fn();draw();assert(buttons['Confirm: add items'].enabled);buttons['Confirm: add items'].fn();draw();assert(applied==1 and buttons['Back to items'])
buttons['Back to items'].fn();draw();buttons['Supply bundles'].fn();draw();buttons['Raw herbs'].fn();draw();assert(selected.bundle=='herbs');assert(ui.back())
draw();buttons.Pickups.fn();draw();assert(buttons['Quantity: 10']and buttons['Clear spawned actors']);buttons['Pickup herb'].fn();assert(spawned==10)
assert(not ui.back())
print('PASS native inventory icon cards, large controls, quantity limits, gated confirmation, bundle selection and preserved pickup mode')
