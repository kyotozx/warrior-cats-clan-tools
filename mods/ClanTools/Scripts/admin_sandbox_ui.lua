local M={}
function M.new(ctx,p)
 local api={};local view='home';local xp=1000;local preview,chosen,statPreview;local page=1
 local function backend()return assert(ctx.sandbox,'Player progression tools unavailable.')end
 local function show(message)p.notify(type(message)=='table'and message.message or tostring(message));p.refresh()end
 local function heading(title,subtitle)p.text(title,430,135,1340,36,nil,true);p.text(subtitle,432,198,1340,17)end
 local function change(v)view=v;preview=nil;chosen=nil;statPreview=nil;page=1;p.refresh()end
 function api.page()
  local b=backend();local state=b.state()
  if view=='xp'then
   heading('Experience','Grant a chosen amount of XP through the original leveling system.')
   p.panel(430,275,1350,460)
   p.text('XP to add: '..xp,465,310,1250,32,nil,true)
   p.button('Enter amount',465,390,1270,72,function()
    p.prompt({title='XP to add',value=tostring(xp),maxLength=6,validate=function(value)local n=tonumber(value);if n and n%1==0 and n>=1 and n<=100000 then return tostring(n)end;return nil,'Choose a whole number from 1 to 100000.'end,
     accept=function(value)xp=tonumber(value);preview=nil;p.refresh();return true end})
   end)
   if preview then
    p.text('Level '..preview.level..' / '..preview.max_level..'  •  XP '..preview.current..' / '..preview.maximum,465,500,1250,25,nil,true)
    p.text('Add '..preview.amount..' XP to this save? This change is saved.',465,560,1250,22)
    p.button('Confirm: add XP',465,630,1270,72,function()local token=preview.token;preview=nil;local ok,r=b.apply_xp(token);show(r);return ok end,true)
   else p.button('Preview XP change',465,530,1270,86,function()local ok,r=b.preview_xp(xp);if ok then preview=r;p.refresh()else show(r)end end,false,state.xp_supported)end
   p.text('A save backup is created before XP is granted. Normal level caps still apply.',450,790,1300,18)
  elseif view=='moves'then
   heading('Unlock combat moves','Unlocks are permanent and shared across this profile. Equip moves in the original game menu.')
   local ok,rows=b.moves()
   if not ok then p.text(tostring(rows),450,320,1300,22);return end
   if chosen then
    p.panel(430,280,1350,500);p.text(chosen.name,465,315,1260,33,nil,true)
    p.text(chosen.description or'',465,395,1260,20)
    p.text('Stamina: '..tostring(chosen.stamina)..'  •  '..tostring(chosen.category),465,495,1260,20)
    p.button('Confirm: unlock move',465,635,1270,86,function()local tag=chosen.tag;chosen=nil;local _,r=b.unlock_move(tag);show(r)end,true,state.moves_supported)
   else
    local pages=math.max(1,math.ceil(#rows/8));page=math.min(page,pages)
    for i=1,8 do local row=rows[(page-1)*8+i];if row then
     p.button(row.name..(row.unlocked and'  •  Unlocked'or''),430+((i-1)%2)*690,285+math.floor((i-1)/2)*135,660,104,function()chosen=row;p.refresh()end,row.unlocked,not row.unlocked)
    end end
    p.button('Previous',430,914,410,62,function()page=page-1;p.refresh()end,false,page>1)
    p.text('Page '..page..' / '..pages,900,930,340,18)
    p.button('Next',1370,914,410,62,function()page=page+1;p.refresh()end,false,page<pages)
   end
  elseif view=='combat'then
   heading('Combat tools','Temporary changes for your party in offline battles.')
   p.panel(430,280,1350,230);p.text('Player damage: '..state.damage_multiplier..'x',460,310,1270,29,nil,true)
   p.button('Choose multiplier',460,390,1270,82,function()
    p.prompt({title='Player damage multiplier',value=tostring(state.damage_multiplier),maxLength=3,validate=function(value)local n=tonumber(value);if n and n%1==0 and n>=1 and n<=100 then return tostring(n)end;return nil,'Choose a whole number from 1 to 100.'end,
     accept=function(value)local ok,msg=b.set_damage_multiplier(tonumber(value));if ok then show(msg)end;return ok,msg end})
   end,false,state.damage_supported)
   p.button('One-hit victory: '..(state.one_hit and'On'or'Off'),430,550,1350,100,function()local _,msg=b.set_one_hit(not state.one_hit);show(msg)end,state.one_hit,state.damage_supported)
   p.button('Infinite stamina: '..(state.infinite_stamina and'On'or'Off'),430,690,1350,100,function()local _,msg=b.set_infinite_stamina(not state.infinite_stamina);show(msg)end,state.infinite_stamina,state.stamina_supported)
   p.text('Damage changes affect successful player hits. Misses and incoming enemy damage keep normal rules.',450,840,1300,18)
  elseif view=='stats'then
   heading('Player attributes','Changes are saved. Level-ups may recalculate attributes using the game’s normal rules.')
   local ok,r=b.stats()
   if not ok then p.text(tostring(r),450,320,1300,22);return end
   if statPreview then
    p.panel(430,285,1350,510);p.text(statPreview.key:upper(),465,315,1250,32,nil,true)
    p.text('Current: '..statPreview.before..'  →  New: '..statPreview.after,465,405,1250,29,nil,true)
    p.text('Before first edit this session: '..statPreview.original,465,485,1250,22)
    p.button('Confirm attribute change',465,640,1270,98,function()local token=statPreview.token;statPreview=nil;local _,result=b.apply_stat(token);show(result)end,true,state.stats_supported)
    return
   end
   for i,name in ipairs({'Prowess','Strength','Resilience','Instinct','Agility','Stamina'})do
    local x=430+((i-1)%2)*690;local y=285+math.floor((i-1)/2)*185
    p.panel(x,y,660,156);p.text(name..': '..tostring(r['stat'..(i-1)]),x+28,y+21,410,25,nil,true)
    p.text('Original: '..tostring(r['original_stat'..(i-1)]or r['stat'..(i-1)]),x+28,y+94,410,18)
    p.button('Edit',x+464,y+42,170,72,function()
     p.prompt({title=name,value=tostring(r['stat'..(i-1)]),maxLength=5,validate=function(value)local n=tonumber(value);if n and n%1==0 and n>=1 and n<=10000 then return tostring(n)end;return nil,'Choose a whole number from 1 to 10000.'end,
      accept=function(value)local good,result=b.preview_stat(name:lower(),tonumber(value));if good then statPreview=result;p.refresh();return true end;return false,result end})
    end,false,state.stats_supported)
   end
   p.button('Refresh attributes',430,914,1350,62,p.refresh)
  else
   heading('Player progression','Experience, original combat moves and player attributes.')
   for i,row in ipairs({{'xp','Add experience','Choose an amount and preview before applying.'},{'moves','Unlock moves','Select an individual move from your clan and universal moves.'},{'stats','Player attributes','Edit attributes and compare their original values.'},{'combat','Combat tools','Damage multiplier, one-hit victory and stamina.'}})do
    p.button(row[2],430,270+(i-1)*168,1350,100,function()change(row[1])end)
    p.text(row[3],450,380+(i-1)*168,1300,18)
   end
  end
 end
 function api.back()
  if statPreview then statPreview=nil;p.refresh();return true end
  if chosen then chosen=nil;p.refresh();return true end
  if preview then preview=nil;p.refresh();return true end
  if view~='home'then change('home');return true end
  return false
 end
 return api
end
return M
