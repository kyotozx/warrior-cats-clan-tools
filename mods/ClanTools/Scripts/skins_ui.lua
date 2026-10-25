local M={}
function M.new(ctx,p)
 local api={};local page,selected,part=1,nil,'All';local favorites=false;local deleteArmed
 local function store()return ctx.skins.store end
 local function change(fn)local ok,why=pcall(fn);p.notify(ok and'Skin library updated.'or tostring(why):gsub('^.-:%d+: ',''));p.refresh()end
 function api.page()
  p.text('Your skins',430,135,1350,38,nil,true)
  p.text('Share your cat\'s appearance between characters. Names, clans and progress stay with each save.',432,202,1335,18)
  p.button('Save current look',430,275,430,64,function()p.prompt({title='Name your skin',value=ctx.playerName(),maxLength=40,accept=function(v)change(function()ctx.skins.save(v)end);return true end})end)
  p.button('Edit your cat',890,275,430,64,function()local ok,why=ctx.appearance.player();if not ok then p.notify(why)end end)
  p.button(favorites and'Favorites only'or'All skins',1350,275,430,64,function()favorites=not favorites;page=1;p.refresh()end,favorites)
  local all,why=store().list();local rows={};for _,e in ipairs(all)do if not favorites or e.favorite then rows[#rows+1]=e end end
  local pages=math.max(1,math.ceil(#rows/6));page=math.min(page,pages)
  for i=1,6 do local e=rows[(page-1)*6+i];if e then
   local x,y=430+((i-1)%2)*690,370+math.floor((i-1)/2)*115;p.panel(x,y,660,104)
   if p.portrait then p.portrait({role=-e.id,skin=e.values,clan=ctx.snapshot().clan},x+12,y+12,78)end
   p.button((e.favorite and'* 'or'')..e.label,x+102,y+13,540,74,function()selected=e.id;deleteArmed=nil;p.refresh()end,selected==e.id)
  end end
  if #rows==0 then p.text(why or'No skins yet. Save your current look to start your collection.',450,455,1300,23)end
  local e=selected and store().get(selected)
  p.text(e and('Selected: '..e.label..'  |  Load: '..part)or'Select a skin to preview it before applying.',445,730,1320,20)
  p.button('Preview skin',430,785,310,62,function()local ok,why=ctx.skins.preview(selected,part);if not ok then p.notify(why)end end,true,e~=nil)
  p.button('Parts: '..part,755,785,310,62,function()part=({All='Coat',Coat='Eyes',Eyes='Shape',Shape='All'})[part];p.refresh()end)
  p.button('Rename',1080,785,310,62,function()p.prompt({title='Rename skin',value=e.label,maxLength=40,accept=function(v)change(function()store().rename(selected,v)end);return true end})end,false,e~=nil)
  p.button(e and e.favorite and'Unfavorite'or'Favorite',1405,785,375,62,function()change(function()store().favorite(selected)end)end,false,e~=nil)
  p.button('Import',430,865,250,60,function()change(function()selected=store().import()end)end)
  p.button('Export',700,865,250,60,function()local ok,r=pcall(store().export,selected);p.notify(ok and'Saved skin-export.json in your ClanTools folder.'or r)end,false,e~=nil)
  p.button(deleteArmed==selected and e and'Confirm delete'or'Delete',970,865,250,60,function()if deleteArmed~=selected then deleteArmed=selected;p.refresh()else change(function()store().delete(selected);selected=nil;deleteArmed=nil end)end end,false,e~=nil)
  p.button('Previous',1240,865,250,60,function()page=page-1;p.refresh()end,false,page>1)
  p.button('Next',1510,865,270,60,function()page=page+1;p.refresh()end,false,page<pages)
  p.text('Page '..page..' / '..pages..'  |  '..#all..' / 128 skins  |  Coat, eyes and shape only; accessories remain unchanged.',445,950,1320,17)
 end
 return api
end
return M
