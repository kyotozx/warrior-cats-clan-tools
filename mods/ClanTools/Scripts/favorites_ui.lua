local M={}
function M.new(ctx,p,registry)
 local model=dofile(debug.getinfo(1,'S').source:gsub('^@',''):match('^(.*[/\\])')..'favorites.lua').new(ctx,registry)
 local api={};local editing,page=false,1
 function api.page()
  p.text(editing and'Choose favorite actions'or'Favorite actions',430,135,1350,36,nil,true)
  p.text('Keep your most-used tools close. Actions follow the same offline and gameplay rules.',432,198,1340,17)
  local rows=model.list(editing);local pages=math.max(1,math.ceil(#rows/8));page=math.min(page,pages)
  if #rows==0 then p.text('Choose actions to build your quick-access menu.',455,400,1250,25,nil,true)end
  for i=1,8 do local row=rows[(page-1)*8+i];if row then
   p.button((editing and(row.selected and'★  'or'+  ')or'')..row.label,430+((i-1)%2)*690,290+math.floor((i-1)/2)*135,660,105,function()
    if editing then model.toggle(row.id)else local ok,message=model.run(row.id);if message then p.notify(message)end;if ok==false then return end end;p.refresh()
   end,row.selected)
  end end
  p.button('Previous',430,914,300,62,function()page=page-1;p.refresh()end,false,page>1)
  p.button(editing and'Done'or'Choose favorites',760,914,690,62,function()editing=not editing;page=1;p.refresh()end)
  p.button('Next',1480,914,300,62,function()page=page+1;p.refresh()end,false,page<pages)
 end
 function api.back()if editing then editing=false;page=1;p.refresh();return true end;return false end
 return api
end
return M
