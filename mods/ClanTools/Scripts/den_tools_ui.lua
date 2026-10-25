-- Uses the same native game buttons, fonts and panels as the other Clan Tools pages.
local M={}
function M.new(ctx,p)
 local api={};local page=1;local step=10;local turn=15
 local function backend()return assert(ctx.denTools,'Den layout tools are unavailable.')end
 local function action(fn,...)local ok,why=fn(...);if not ok then p.notify(tostring(why))end;p.refresh();return ok end
 local function heading(title,subtitle)p.text(title,430,135,1350,36,nil,true);p.text(subtitle,432,198,1340,17)end
 local function pretty(name)return tostring(name):gsub('^SM_',''):gsub('^SK_',''):gsub('_',' ')end
 function api.page()
  local b=backend();local s=b.status()
  if not s.active then
   heading('Den layout','Make your den your own.')
   p.panel(430,300,1350,350);p.text('Enter your clan den',470,350,1260,32,nil,true)
   p.text('Completed decorations will appear here while you are inside your den and playing offline.',470,430,1260,22)
   p.text(s.error or'Move and rotate decorations, add copies, then Apply or Cancel your preview.',470,530,1260,19)
   p.button('Refresh decorations',430,914,1350,62,p.refresh);return
  end
  local preview=s.preview
  if not preview then
   heading('Den layout','Choose a completed decoration. Each layout is saved separately for your clan.')
   if #s.rows==0 then p.text('Finish crafting a decoration to arrange it here.',450,340,1300,25)end
   local pages=math.max(1,math.ceil(#s.rows/8));page=math.min(page,pages)
   for i=1,8 do local row=s.rows[(page-1)*8+i];if row then
    p.button(pretty(row.name)..(row.copies>0 and'  •  '..row.copies..' copies'or''),430+((i-1)%2)*690,280+math.floor((i-1)/2)*128,660,102,
     function()action(b.begin,row.tag)end)
   end end
   p.button('Undo last applied layout',430,810,1350,68,function()action(b.undo)end,false,s.canUndo)
   p.button('Previous',430,914,410,62,function()page=page-1;p.refresh()end,false,page>1)
   p.text('Page '..page..' / '..pages,900,930,340,18)
   p.button('Next',1370,914,410,62,function()page=page+1;p.refresh()end,false,page<pages)
   return
  end
  local selected=preview.selected;local o=selected==0 and preview.layout.offset or preview.layout.copies[selected]
  local name=preview.tag;for _,row in ipairs(s.rows)do if row.tag==preview.tag then name=pretty(row.name)end end
  heading('Arrange decoration',name..'  •  '..(selected==0 and'Original'or'Copy '..selected)..'  •  Preview')
  p.button('Previous piece',430,250,420,62,function()action(b.selectCopy,math.max(0,selected-1))end,false,selected>0)
  p.button('Step: '..step..' cm',880,250,450,62,function()step=step==5 and 10 or step==10 and 25 or 5;p.refresh()end)
  p.button('Next piece',1360,250,420,62,function()action(b.selectCopy,math.min(#preview.layout.copies,selected+1))end,false,selected<#preview.layout.copies)
  local rows={
   {'Move forward',function()action(b.move,step,0,0)end,'Move back',function()action(b.move,-step,0,0)end},
   {'Move left',function()action(b.move,0,-step,0)end,'Move right',function()action(b.move,0,step,0)end},
   {'Raise',function()action(b.move,0,0,step)end,'Lower',function()action(b.move,0,0,-step)end},
   {'Rotate left '..turn..'°',function()action(b.rotate,-turn)end,'Rotate right '..turn..'°',function()action(b.rotate,turn)end},
   {'Duplicate piece',function()action(b.duplicate)end,'Remove copy',function()action(b.removeCopy)end},
  }
  for i,row in ipairs(rows)do local y=335+(i-1)*85
   p.button(row[1],430,y,660,70,row[2]);p.button(row[3],1120,y,660,70,row[4],false,i~=5 or selected>0)
  end
  p.button('Restore original layout',430,760,660,62,function()action(b.restoreLayout)end)
  p.button('Turn step: '..turn..'°',1120,760,660,62,function()turn=turn==5 and 15 or turn==15 and 45 or 5;p.refresh()end)
  p.text(string.format('Offset: %.0f / %.0f / %.0f cm  •  Rotation: %.0f°  •  Copies: %d',o.x,o.y,o.z,o.yaw,#preview.layout.copies),445,836,1320,18)
  p.text('Close the menu to inspect your preview; reopen to Apply or Cancel. Copies have no collision.',445,872,1320,17)
  p.button('Cancel preview',430,925,660,62,function()action(b.cancel)end)
  p.button('Apply layout',1120,925,660,62,function()action(b.apply)end,true)
 end
 function api.back()
  local b=backend();if b.status().preview then action(b.cancel);return true end;return false
 end
 return api
end
return M
