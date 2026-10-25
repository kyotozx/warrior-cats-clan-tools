local M={}
function M.new(ctx,ui)
 local api={};local page=1
 local function action(fn)local ok,message=fn();assert(ok,message);ui.notify(message);ui.refresh()end
 function api.page(selection,onLoaded)
  ui.text('Your companions, your routine',430,135,1350,38,nil,true)
  ui.text('Give exploration commands or save a party to use again later.',430,202,1330,17)
  local state=ctx.followers.state()
  ui.panel(430,280,1350,220)
  ui.button('Follow on map: '..(state.enabled and'On'or'Off'),460,300,390,64,function()action(function()return ctx.followers.set_enabled(not state.enabled)end)end,state.enabled)
  for i,command in ipairs({'follow','stay','regroup'})do
   ui.button(command,880+(i-1)*292,300,270,64,function()action(function()return ctx.followers.command(command)end)end,state.mode==command,state.enabled)
  end
  ui.text('Following distance: '..tostring(state.distance or 190)..' cm',460,406,600,24,nil,true)
  ui.button('Closer',1150,397,280,62,function()action(function()return ctx.followers.set_distance(math.max(100,(state.distance or 190)-50))end)end,false,(state.distance or 190)>100)
  ui.button('Further',1460,397,280,62,function()action(function()return ctx.followers.set_distance(math.min(600,(state.distance or 190)+50))end)end,false,(state.distance or 190)<600)
  ui.text('Saved parties',430,532,850,28,nil,true)
  ui.button('Save selected party',1320,520,460,64,function()
   ui.prompt({title='Party preset name',value='',maxLength=40,accept=function(name)
    local ok,message=ctx.partyPresets.save(name,selection);if ok then ui.notify(message);ui.refresh()end;return ok,message
   end})
  end)
  local presets=ctx.partyPresets.list();local pages=math.max(1,math.ceil(#presets/3));page=math.min(page,pages)
  for i=1,3 do local preset=presets[(page-1)*3+i];if preset then local y=606+(i-1)*101
   ui.panel(430,y,1350,88);ui.text(preset.name,458,y+10,690,24,nil,true);ui.text(#preset.roles..' companions',460,y+49,600,15)
   ui.button('Load',1210,y+12,250,62,function()action(function()return ctx.partyPresets.load(preset.id)end);onLoaded()end)
   ui.button('Delete',1490,y+12,250,62,function()action(function()return ctx.partyPresets.remove(preset.id)end)end)
  end end
  if #presets==0 then ui.text('No saved parties yet. Select companions, then save your first preset.',460,640,1250,23,nil,true)end
  if pages>1 then
   ui.button('Previous',430,925,280,60,function()page=math.max(1,page-1);ui.refresh()end,false,page>1)
   ui.text('Page '..page..' of '..pages,805,944,500,17)
   ui.button('Next',1500,925,280,60,function()page=math.min(pages,page+1);ui.refresh()end,false,page<pages)
  end
 end
 return api
end
return M
