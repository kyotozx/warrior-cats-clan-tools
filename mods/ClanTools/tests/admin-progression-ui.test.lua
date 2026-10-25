local M=dofile('mods/ClanTools/Scripts/admin_progression_ui.lua')
local passed=0
local function test(name,fn)fn();passed=passed+1;print('PASS '..name)end
local function fixture()
 local api,objects;local calls,messages={},{};local verified={pile=true,bonds=true,quests=true};local sequence=0
 local status={status='idle'};local pile,bond=87,28;local cats={}
 for i=1,22 do cats[i]={role=i,name=string.format('Cat %02d',i),living=true,clan=1}end
 local backend={capabilities=function()return verified end,questState=function()return status end}
 function backend.preview(kind,args)
  sequence=sequence+1
  if kind=='pile'then return true,{token=tostring(sequence),current=pile,maximum=100,enabled=verified.pile}end
  if kind=='bond'then return true,{token=tostring(sequence),current=bond,maximum=100,name=cats[args.role].name,role=args.role,enabled=verified.bonds}end
  if calls.empty then return true,{}end
  return true,{{token=tostring(sequence),name='Making Your Mark',tag='Quest.Test',status=2,enabled=verified.quests}}
 end
 function backend.action(id,args)
  calls[#calls+1]={id=id,args=args}
  if calls.fail then return false,'The value changed. Refresh the preview.'end
  if id=='fill_pile'then local before=pile;pile=100;return true,{before=before,after=pile}end
  if id=='set_bond'or id=='restore_bond'then local before=bond;bond=id=='set_bond'and args.value or 28;return true,{before=before,after=bond}end
  if id=='complete_quest'then status={status='running',message='Advancing active quest objectives.'};return true,{queued=true}end
  status={status='stopped',message='Quest completion cancelled.'};return true,status
 end
 local function record(kind,label,x,y,w,h,fn,selected,enabled)
  assert(x>=430 and y>=135 and x+w<=1780 and y+h<=980,'Layout bounds: '..kind..' '..tostring(label))
  local o={kind=kind,label=label,fn=fn,enabled=enabled,SetText=function(self,s)self.label=s end};objects[#objects+1]=o;return o
 end
 local function render()objects={};api.page()end
 api=M.new({progression=backend,getCats=function()return cats,{valid=true,profile='test',slot=0}end,snapshot=function()return{offline=true,profile='test',slot=0,clan=1}end,valid=function()return true end},
 {text=function(s,x,y,w,size)return record('text',s,x,y,w,size*2.1)end,button=function(s,x,y,w,h,fn,sel,en)return record('button',s,x,y,w,h,fn,sel,en)end,panel=function(x,y,w,h)return record('panel','',x,y,w,h)end,notify=function(s)messages[#messages+1]=s end,refresh=render})
 local function find(label)for _,o in ipairs(objects)do if o.label==label then return o end end end
 return{api=api,render=render,calls=calls,messages=messages,verified=verified,backend=backend,has=find,click=function(label)local o=assert(find(label),'Missing '..label);assert(o.enabled~=false,'Disabled '..label);assert(o.fn)();end}
end
test('read-only landing and bounded native canvas across all views',function()
 local f=fixture();f.render();assert(#f.calls==0);f.click('Choose a clanmate');assert(f.has('22 clanmates  |  Page 1 / 2'));f.click('Next');assert(f.has('Cat 22'));f.click('Cat 22');assert(f.has('Current bond: 28 / 100'));assert(f.api.back());assert(f.api.back());assert(not f.api.back());assert(#f.calls==0)
end)
test('bond picker clamps and applies exactly selected value with preview token',function()
 local f=fixture();f.render();f.click('Choose a clanmate');f.click('Cat 01');for i=1,15 do f.click('+ 5')end
 assert(f.has('New bond: 100 / 100'));assert(f.has('+ 1').enabled==false);f.click('- 1');f.click('Apply bond');assert(f.calls[1].args.value==99 and f.calls[1].args.token);f.click('Restore session original');assert(f.calls[2].id=='restore_bond');assert(f.has('Current bond: 28 / 100'))
end)
test('failed mutation invalidates local preview until explicit refresh',function()
 local f=fixture();f.render();f.click('Choose a clanmate');f.click('Cat 01');f.click('+ 1');f.calls.fail=true;f.click('Apply bond');assert(f.has('Preview required'));assert(not f.has('Apply bond').enabled);assert(f.messages[#f.messages].title=='Change not applied');f.calls.fail=false;f.click('Refresh preview');assert(f.has('Current bond: 28 / 100'))
end)
test('verification disables mutations but keeps previews navigable',function()
 local f=fixture();f.verified.pile=false;f.verified.bonds=false;f.verified.quests=false;f.render();assert(not f.has('Fill fresh-kill pile').enabled);f.click('Choose a clanmate');f.click('Cat 01');f.click('+ 1');assert(not f.has('Apply bond').enabled);f.api.back();f.api.back();f.click('View active quests');f.click('Making Your Mark  |  In progress');assert(not f.has('Complete this quest').enabled);assert(#f.calls==0)
end)
test('quest requires selected confirmation and cancellation is explicit',function()
 local f=fixture();f.render();f.click('View active quests');f.click('Making Your Mark  |  In progress');assert(#f.calls==0);assert(f.api.back());assert(#f.calls==0);f.click('Making Your Mark  |  In progress');f.click('Complete this quest');assert(f.calls[1].id=='complete_quest');assert(f.has('Stop completing quest'));f.click('Stop completing quest');assert(f.calls[2].id=='cancel_quest')
end)
test('empty active quest list describes native acceptance requirement',function()
 local f=fixture();f.calls.empty=true;f.render();f.click('View active quests');assert(f.has('No active quests are available'));assert(#f.calls==0)
end)
test('pile fills to actual preview maximum and refreshes readback',function()
 local f=fixture();f.render();f.click('Fill fresh-kill pile');assert(f.calls[1].id=='fill_pile');assert(f.has('Current food: 100 / 100'))
end)
print(passed..' progression UI tests passed (mock renderer; live visual check required).')
