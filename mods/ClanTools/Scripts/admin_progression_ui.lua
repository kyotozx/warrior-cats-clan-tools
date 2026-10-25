-- Native widgets and spatial keyboard/controller focus are supplied by the host.
local M={}
local function short(value,n)local s=tostring(value or'');return #s>n and s:sub(1,n-3)..'...'or s end
local function number(v)return type(v)=='number'and string.format('%.1f',v):gsub('%.0$','')or'--'end
function M.new(ctx,p)
 assert(p and p.text and p.button and p.panel and p.refresh and p.notify,'Progression UI primitives required.')
 local text,button,panel=p.text,p.button,p.panel
 local api={};local state={view='home',catPage=1,questPage=1,value=0};local statusWidget,statusText
 local function backend()return assert(ctx.progression,'Progression tools are unavailable.')end
 local function refresh()statusWidget=nil;p.refresh()end
 local function call(fn,...)
  local ok,a,b=pcall(fn,...);if not ok then return false,tostring(a)end
  if a==false then return false,tostring(b)end;return true,b or a
 end
 local function preview(kind,args)return call(function()return backend().preview(kind,args)end)end
 local function heading(title,subtitle)
  text(title,430,135,1340,31,nil,true);text(subtitle,432,192,1340,17)
 end
 local function note(s,y)text(short(s,145),450,y,1300,17)end
 local function caps()local ok,r=pcall(function()return backend().capabilities()end);return ok and r or{}end
 local function job()local ok,r=pcall(function()return backend().questState()end);return ok and r or{status='idle'}end
 local function loadPile()local ok,r=preview('pile');state.pile=ok and r or nil;state.pileError=not ok and r or nil end
 local function loadBond(role)
  local ok,r=preview('bond',{role=role});state.bond=ok and r or nil;state.bondError=not ok and r or nil
  state.role=role;if ok then state.value=r.current end
 end
 local function loadQuests()
  local ok,r=preview('quests');state.quests=ok and r or{};state.questError=not ok and r or nil;state.questPage=1
 end
 local function navigate(view)state.view=view;refresh()end
 local function apply(id,args)
  local ok,r=call(function()return backend().action(id,args)end)
  if not ok then
   state.bond=nil;state.pile=nil;state.selectedQuest=nil
   p.notify({title='Change not applied',lines={short(r,180),'Refresh the preview before trying again.'}})
   if state.view=='confirm'then state.view='quests';loadQuests()end
  elseif id=='complete_quest'then
   p.notify('Selected quest completion started.');state.selectedQuest=nil;state.view='quests';loadQuests()
  elseif id=='cancel_quest'then p.notify(r.message or'Quest completion stopped.');loadQuests()
  elseif id=='fill_pile'then p.notify('Fresh-kill pile: '..number(r.before)..' -> '..number(r.after)..'.');loadPile()
  else p.notify('Bond saved: '..number(r.before)..' -> '..number(r.after)..'.');loadBond(state.role)end
  refresh();return ok
 end
 local function footer(back)
  button(back or'Back',430,914,330,62,function()api.back()end)
 end
 local function home()
  heading('Clan progression',"Manage your clan's food, relationships and active quests.")
  if not state.pile and not state.pileError then loadPile()end
  local r=state.pile;local enabled=r and r.enabled and caps().pile and job().status~='running'
  panel(430,258,1350,224);text('Fresh-kill pile',450,275,1270,25,nil,true)
  note(r and('Current food: '..number(r.current)..' / '..number(r.maximum))or state.pileError or'Pile unavailable.',327)
  button('Fill fresh-kill pile',450,395,480,65,function()if state.pile then apply('fill_pile',{token=state.pile.token})end end,false,enabled)
  local lock=ctx.pileLock and ctx.pileLock.state()or{}
  button(lock.enabled and'Food lock: On'or'Lock current food',955,395,480,65,function()
   local _,message=ctx.pileLock.set(not lock.enabled);p.notify(message);loadPile();refresh()
  end,lock.enabled,lock.enabled or lock.available)
  button('Refresh',1460,395,300,65,function()loadPile();refresh()end)
  panel(430,505,1350,158);text('Clanmate bonds',450,522,1270,25,nil,true)
  button('Choose a clanmate',450,579,1310,65,function()navigate('bonds')end)
  panel(430,686,1350,158);text('Selected quests',450,703,1270,25,nil,true)
  button('View active quests',450,760,1310,65,function()loadQuests();navigate('quests')end)
  note('Changes are saved. A backup is created automatically before each change.',866)
  if r and not r.enabled then note('Pile editing is awaiting verification for this game build.',933)end
 end
 local function roster()
  local ok,cats,meta=pcall(ctx.getCats or function()error('Clan roster unavailable.')end)
  if not ok or not meta or not meta.valid then return{},tostring(ok and'Clan roster unavailable.'or cats)end
  local okS,s=pcall(ctx.snapshot);if not okS or not s then return{},'Active save unavailable.'end
  if s.offline~=true or s.profile~=meta.profile or s.slot~=meta.slot then return{},'Clan roster belongs to another session.'end
  local out={};for _,cat in ipairs(cats)do if cat.living and cat.clan==s.clan and type(cat.role)=='number'and cat.role>0 then out[#out+1]=cat end end
  table.sort(out,function(a,b)return tostring(a.name)<tostring(b.name)end);return out
 end
 local function bonds()
  heading('Clanmate bonds','Choose a living clanmate to preview and edit their current bond.')
  local cats,err=roster();local pages=math.max(1,math.ceil(#cats/12));state.catPage=math.min(state.catPage,pages)
  text(#cats..' clanmates  |  Page '..state.catPage..' / '..pages,450,245,1290,18)
  if err then note(err,325)end
  for i=1,12 do local cat=cats[(state.catPage-1)*12+i];if cat then
   button(short(cat.name or'Clanmate',28),430+((i-1)%3)*456,310+math.floor((i-1)/3)*130,438,100,function()loadBond(cat.role);navigate('bond')end)
  end end
  footer('Back to progression')
  button('Previous',790,914,460,62,function()state.catPage=state.catPage-1;refresh()end,false,state.catPage>1)
  button('Next',1280,914,500,62,function()state.catPage=state.catPage+1;refresh()end,false,state.catPage<pages)
 end
 local function bond()
  local r=state.bond;local enabled=r and r.enabled and caps().bonds and job().status~='running'
  heading(r and r.name or'Clanmate bond','Adjust the selected bond, then apply the previewed change.')
  panel(430,260,1350,210)
  text(r and('Current bond: '..number(r.current)..' / 100')or'Preview required',450,285,1270,27,nil,true)
  note(r and'Bond values are whole numbers from 0 to 100.'or state.bondError or'Refresh before applying another change.',350)
  button('Refresh preview',450,395,1310,62,function()loadBond(state.role);refresh()end)
  panel(430,492,1350,200);text('New bond: '..state.value..' / 100',450,512,1270,28,nil,true)
  local function adjust(delta)return function()state.value=math.max(0,math.min(100,state.value+delta));refresh()end end
  for i,item in ipairs({{'- 5',-5},{'- 1',-1},{'+ 1',1},{'+ 5',5}})do
   button(item[1],450+(i-1)*332,591,312,76,adjust(item[2]),false,r~=nil and(item[2]<0 and state.value>0 or item[2]>0 and state.value<100))
  end
  button('Apply bond',430,725,660,78,function()if state.bond then apply('set_bond',{token=state.bond.token,value=state.value})end end,false,enabled and state.value~=r.current)
  button('Restore session original',1120,725,660,78,function()if state.bond then apply('restore_bond',{token=state.bond.token})end end,false,enabled)
  note(r and not r.enabled and'Bond editing is awaiting verification for this game build.'or'Restore uses the value before your first edit during this session.',844)
  footer('Back to clanmates')
 end
 local function questStatus()
  local s=job();statusText=s.status=='idle'and'Choose one quest to continue.'or short(s.message or s.status,140)
  statusWidget=text(statusText,450,258,1300,17)
  if s.status=='running'then button('Stop completing quest',1120,914,660,62,function()apply('cancel_quest')end)end
  return s
 end
 local function quests()
  heading('Selected quests','Finish active objectives and turn in one successful quest through the game reward system.')
  local s=questStatus();local list=state.quests or{};local pages=math.max(1,math.ceil(#list/6));state.questPage=math.min(state.questPage,pages)
  if state.questError then note(state.questError,328)
  elseif #list==0 then
   panel(430,325,1350,210);text('No active quests are available',450,350,1290,26,nil,true)
   note('Accept a quest in the game, then refresh this list.',414)
  else
   for i=1,6 do local q=list[(state.questPage-1)*6+i];if q then
    local suffix=q.status==3 and'  |  Ready to turn in'or'  |  In progress'
    button(short(q.name or q.tag,85)..suffix,430,322+(i-1)*83,1350,68,function()state.selectedQuest=q;navigate('confirm')end,false,s.status~='running')
   end end
  end
  text('Page '..state.questPage..' / '..pages,450,843,280,17)
  button('Previous',770,830,280,61,function()state.questPage=state.questPage-1;refresh()end,false,state.questPage>1)
  button('Next',1070,830,280,61,function()state.questPage=state.questPage+1;refresh()end,false,state.questPage<pages)
  button('Refresh quests',1370,830,410,61,function()loadQuests();refresh()end)
  footer('Back to progression')
 end
 local function confirm()
  local q=state.selectedQuest;if not q then state.view='quests';return quests()end
  heading('Complete selected quest','Review this quest before applying saved progression.')
  panel(430,275,1350,520);text(short(q.name or q.tag,90),450,302,1290,27,nil,true)
  note('Only this selected quest will be processed.',385)
  note('Its active objectives will complete, followed by the normal reward and turn-in pathway.',441)
  note('Dialogs, changed objectives or an unsupported step can stop the operation.',497)
  note('Already completed objectives remain saved if you cancel. A save backup is created first.',553)
  local enabled=q.enabled and caps().quests and job().status~='running'
  if not enabled then note('Quest completion is awaiting runtime verification for this game build.',618)end
  button('Complete this quest',450,693,1310,78,function()if state.selectedQuest then apply('complete_quest',{token=state.selectedQuest.token})end end,false,enabled)
  footer('Back to quests')
 end
 function api.page()
  statusWidget=nil
  if state.view=='home'then home()elseif state.view=='bonds'then bonds()elseif state.view=='bond'then bond()elseif state.view=='quests'then quests()else confirm()end
 end
 function api.back()
  if state.view=='home'then state.pile=nil;state.pileError=nil;return false end
  if state.view=='bond'then state.view='bonds';state.bond=nil
  elseif state.view=='confirm'then state.view='quests';state.selectedQuest=nil
  else state.view='home';state.pile=nil;state.pileError=nil end
  refresh();return true
 end
 function api.tick()
  if not statusWidget then return end
  local s=job();local message=s.status=='idle'and'Choose one quest to continue.'or short(s.message or s.status,140)
  if message~=statusText and ctx.valid and ctx.valid(statusWidget)and FText then statusWidget:SetText(FText(message));statusText=message end
 end
 return api
end
return M
